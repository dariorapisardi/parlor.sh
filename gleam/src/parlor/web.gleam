//// HTTP: routes, content negotiation, and the text every response is made of. The pages are the
//// ones in docs/, rendered the same way the Node server renders them, so both servers serve the
//// same bytes for the same room.

import exception
import gleam/bit_array
import gleam/bytes_tree
import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/float
import gleam/http.{Get, Head, Post}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/io
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import mist.{type Connection, type ResponseData}
import parlor/clock
import parlor/config.{type Config}
import parlor/fail.{type HttpError}
import parlor/fields
import parlor/registry
import parlor/room.{type Reading}
import parlor/store.{type Message}
import simplifile

pub type Docs {
  Docs(
    index_md: String,
    room_md: String,
    index_html: String,
    room_html: String,
    example_html: String,
    example: Example,
  )
}

/// A whole room from a real test (tests/runs/02), served as a static page at /example so the
/// front page can link to a room that never expires. Not a room: no id, nothing to join.
pub type Example {
  Example(
    topic: String,
    created_at: String,
    host: String,
    messages: List(Message),
  )
}

pub type Web {
  Web(config: Config, registry: Subject(registry.Msg))
}

/// The pages, stored once for the whole server: each connection is a process, and whatever its
/// handler closes over is copied into it.
pub fn store_docs(docs: Docs) -> Nil {
  put_global("docs", docs)
}

fn docs() -> Docs {
  get_global("docs")
}

@external(erlang, "parlor_ffi", "put_global")
fn put_global(key: String, value: Docs) -> Nil

@external(erlang, "parlor_ffi", "get_global")
fn get_global(key: String) -> Docs

@external(erlang, "parlor_ffi", "collect_garbage")
fn collect_garbage() -> Nil

pub fn load_docs(config: Config) -> Result(Docs, String) {
  let dir = config.root <> "/docs/"
  let read = fn(name) {
    simplifile.read(dir <> name)
    |> result.map_error(fn(e) { name <> ": " <> simplifile.describe_error(e) })
  }
  use style <- result.try(read("style.css.inc"))
  use theme <- result.try(read("theme.html.inc"))
  let page = fn(name) {
    use text <- result.map(read(name))
    text
    |> replace_first("{{style}}", style)
    |> replace_first("{{theme}}", theme)
  }
  use index_md <- result.try(page("index.md"))
  use room_md <- result.try(page("room.md"))
  use index_html <- result.try(page("index.html"))
  use room_html <- result.try(page("room.html"))
  use example_html <- result.try(page("example.html"))
  use example_lines <- result.try(read("example-room.jsonl"))
  use example <- result.try(parse_example(example_lines))
  Ok(Docs(index_md:, room_md:, index_html:, room_html:, example_html:, example:))
}

fn parse_example(text: String) -> Result(Example, String) {
  let header = {
    use topic <- decode.field("topic", decode.string)
    use created_at <- decode.field("created_at", decode.string)
    use host <- decode.field("host", decode.string)
    decode.success(#(topic, created_at, host))
  }
  case string.split(text, "\n") |> list.filter(fn(l) { l != "" }) {
    [] -> Error("example-room.jsonl is empty")
    [first, ..rest] -> {
      let error = fn(e) { "example-room.jsonl: " <> string.inspect(e) }
      use #(topic, created_at, host) <- result.try(
        json.parse(first, header) |> result.map_error(error),
      )
      use messages <- result.map(
        list.try_map(rest, json.parse(_, store.message_decoder()))
        |> result.map_error(error),
      )
      Example(topic:, created_at:, host:, messages:)
    }
  }
}

// ---- requests ------------------------------------------------------------------------------

type Ctx {
  Ctx(
    req: Request(Connection),
    base: String,
    parts: List(String),
    query: List(#(String, String)),
    html: Bool,
    token: Option(String),
    client: String,
    body: Result(String, Nil),
  )
}

pub fn handler(web: Web) -> fn(Request(Connection)) -> Response(ResponseData) {
  fn(req: Request(Connection)) {
    let body = case req.method {
      Post -> read_body(req, web.config.max_body)
      _ -> Ok("")
    }
    let answer =
      exception.rescue(fn() {
        case route(web, context(web.config, req, body)) {
          Ok(resp) -> resp
          Error(e) -> error_response(e)
        }
      })
    let resp = case answer {
      Ok(resp) -> resp
      Error(crash) -> {
        io.println_error("internal error: " <> string.inspect(crash))
        error_response(fail.bare(500, "internal error"))
      }
    }
    // A body we stopped reading at MAX_BODY is still in the connection: close it rather than
    // read the rest as the next request. And close when the client asked to.
    let asked =
      request.get_header(req, "connection") |> result.map(string.lowercase)
    case body, asked {
      Error(_), _ | _, Ok("close") ->
        response.set_header(resp, "connection", "close")
      _, _ -> resp
    }
  }
}

fn context(config: Config, req: Request(Connection), body) -> Ctx {
  let header = fn(name) { request.get_header(req, name) |> result.unwrap("") }
  // Links are printed with PUBLIC_URL when set; otherwise with the address the client used.
  let proto = case config.trust_proxy, header("x-forwarded-proto") {
    True, p if p != "" -> p
    _, _ -> "http"
  }
  let base = case config.public_url {
    "" -> proto <> "://" <> header("host")
    url -> url
  }
  Ctx(
    req:,
    base:,
    parts: path_parts(req.path),
    query: req.query |> option.map(fields.parse_query) |> option.unwrap([]),
    html: string.contains(header("accept"), "text/html"),
    token: bearer(header("authorization")),
    client: client_address(config, req),
    body:,
  )
}

// The path's segments as Node's URL parser leaves them: `\` is `/`, dot segments (also written
// `%2e`) are resolved, empty segments dropped.
fn path_parts(path: String) -> List(String) {
  path
  |> string.replace("\\", "/")
  |> string.split("/")
  |> list.drop(1)
  |> list.fold([], fn(stack, segment) {
    case string.lowercase(segment) {
      ".." | ".%2e" | "%2e." | "%2e%2e" -> list.drop(stack, 1)
      "." | "%2e" -> stack
      _ -> [segment, ..stack]
    }
  })
  |> list.reverse
  |> list.filter(fn(p) { p != "" })
}

// Behind one trusted proxy, the proxy APPENDS the real client to X-Forwarded-For, so the
// rightmost entry is the one it wrote; anything to the left was supplied by the client.
// Assumes exactly one trusted proxy: revisit (hop count) if a CDN or second proxy is added.
fn client_address(config: Config, req: Request(Connection)) -> String {
  let forwarded = case config.trust_proxy {
    True -> request.get_header(req, "x-forwarded-for") |> result.unwrap("")
    False -> ""
  }
  case forwarded {
    "" ->
      mist.get_connection_info(req.body)
      |> result.map(fn(info) { mist.ip_address_to_string(info.ip_address) })
      |> result.unwrap("unknown")
    fwd ->
      string.split(fwd, ",") |> list.last |> result.unwrap("") |> string.trim
  }
}

// `Authorization: Bearer TOKEN`, as /^Bearer\s+(\S+)$/i reads it.
fn bearer(header: String) -> Option(String) {
  case string.lowercase(string.slice(header, 0, 6)) {
    "bearer" -> {
      let rest = string.drop_start(header, 6)
      let token = fields.js_trim_start(rest)
      case token != rest && token != "" && !has_space(token) {
        True -> Some(token)
        False -> None
      }
    }
    _ -> None
  }
}

fn has_space(s: String) -> Bool {
  fields.js_trim_start(s) != s
  || string.to_graphemes(s) |> list.any(fn(g) { fields.is_blank(g) })
}

// The body, up to MAX_BODY bytes; Error when there is more (the room answers 413 when it would
// have read it). Bytes that are not UTF-8 are replaced, not refused.
fn read_body(req: Request(Connection), max: Int) -> Result(String, Nil) {
  case mist.stream(req) {
    Error(_) -> Ok("")
    Ok(consume) -> read_chunks(consume, <<>>, max)
  }
}

fn read_chunks(consume, acc: BitArray, max: Int) -> Result(String, Nil) {
  case consume(65_536) {
    Ok(mist.Chunk(data, next)) -> {
      let acc = bit_array.append(acc, data)
      case bit_array.byte_size(acc) > max {
        True -> Error(Nil)
        False -> read_chunks(next, acc, max)
      }
    }
    Ok(mist.Done) | Error(_) -> Ok(fields.lossy_utf8(acc))
  }
}

// ---- routes --------------------------------------------------------------------------------

fn route(web: Web, c: Ctx) -> Result(Response(ResponseData), HttpError) {
  let method = case c.req.method {
    Head -> Get
    m -> m
  }
  case c.parts, method {
    [], Get -> Ok(front_page(web, c))
    ["example"], Get -> Ok(example(web, c))
    ["cli"], Get -> cli(web, c)
    [], Post -> create(web, c)
    ["r", id, ..rest], _ -> {
      let action = list.first(rest) |> option.from_result
      in_room(web, c, id, action, method)
    }
    _, _ -> Error(not_found(c))
  }
}

fn not_found(c: Ctx) -> HttpError {
  fail.new(404, "not found", "GET " <> c.base <> "/ explains this service.")
}

fn front_page(web: Web, c: Ctx) -> Response(ResponseData) {
  let vars = [
    #("base", c.base),
    #("ttl", config.human_duration(web.config.ttl)),
  ]
  let md = render(docs().index_md, vars)
  case c.html {
    True ->
      send(
        200,
        render(docs().index_html, [#("markdown", escape_html(md)), ..vars]),
        "text/html",
        [vary],
      )
    False -> send(200, md, "text/markdown", [vary])
  }
}

fn example(web: Web, c: Ctx) -> Response(ResponseData) {
  let ex = docs().example
  let people =
    ex.messages
    |> list.filter_map(fn(m) { option.to_result(m.from, Nil) })
    |> list.unique
  case c.html {
    False -> {
      let n = list.length(people)
      let text =
        "# A sample room\n\nA whole room from a real test, kept as a static page: it is not a room you can join.\nTo open a real one, see "
        <> c.base
        <> "/\n\nTopic: "
        <> ex.topic
        <> "\n\n"
        <> format_text(
          ex.messages,
          list.length(ex.messages),
          "closed",
          n,
          n,
          room.Capacity(None, None),
        )
      send(200, text, "text/markdown", [vary])
    }
    True -> {
      let ms = fn(m: Message) { clock.parse_iso(m.ts) |> result.unwrap(0) }
      let first = list.first(ex.messages) |> result.map(ms) |> result.unwrap(0)
      let last = list.last(ex.messages) |> result.map(ms) |> result.unwrap(0)
      // Same markup as the room page's script builds, rendered here once, every string escaped.
      let rows =
        list.map(ex.messages, fn(m) {
          case m.kind {
            "system" ->
              "<div class=\"msg system\">* " <> escape_html(m.body) <> "</div>"
            _ ->
              "<div class=\"msg\"><span class=\"who\">"
              <> escape_html(option.unwrap(m.from, ""))
              <> case m.to {
                Some(to) -> " → " <> escape_html(to)
                None -> ""
              }
              <> "</span> <span class=\"meta\">#"
              <> int.to_string(m.id)
              <> case m.reply_to {
                Some(r) if r != 0 -> " · re #" <> int.to_string(r)
                _ -> ""
              }
              <> " · "
              <> string.slice(m.ts, 11, 8)
              <> " UTC</span><div class=\"body\">"
              <> escape_html(m.body)
              <> "</div></div>"
          }
        })
      let participants =
        people
        |> list.map(fn(h) {
          escape_html(h)
          <> case h == ex.host {
            True -> " (host)"
            False -> ""
          }
        })
        |> string.join(", ")
      let vars = [
        #("base", c.base),
        #("ttl", config.human_duration(web.config.ttl)),
        #("topic", escape_html(ex.topic)),
        #("date", string.slice(ex.created_at, 0, 10)),
        #(
          "duration",
          int.to_string(float.round(int.to_float(last - first) /. 1000.0))
            <> " seconds",
        ),
        #("participants", participants),
        #("transcript", string.join(rows, "\n")),
      ]
      send(200, render(docs().example_html, vars), "text/html", [vary])
    }
  }
}

fn cli(web: Web, c: Ctx) -> Result(Response(ResponseData), HttpError) {
  // The copy served here talks to this server by default, wherever it is hosted.
  case simplifile.read(web.config.cli_path) {
    Ok(script) ->
      Ok(
        send(
          200,
          replace_first(
            script,
            "${PARLOR_URL:-https://parlor.sh}",
            "${PARLOR_URL:-" <> c.base <> "}",
          ),
          "text/plain",
          [],
        ),
      )
    Error(e) -> {
      io.println_error(
        "cannot read "
        <> web.config.cli_path
        <> ": "
        <> simplifile.describe_error(e),
      )
      Error(fail.bare(500, "internal error"))
    }
  }
}

fn create(web: Web, c: Ctx) -> Result(Response(ResponseData), HttpError) {
  let config = web.config
  use Nil <- result.try(
    actor_call(web.registry, 5000, registry.MayCreate(c.client, _))
    |> result.replace_error(fail.bare(500, "internal error"))
    |> result.flatten,
  )
  use raw <- result.try(
    c.body
    |> result.replace_error(fail.new(
      413,
      "body too large",
      "Max " <> int.to_string(config.max_body) <> " bytes.",
    )),
  )
  use f <- result.try(fields.parse(raw, content_type(c), c.query, form: True))
  // `idle` was the earlier name.
  let wanted =
    fields.get(f, "ttl") |> option.lazy_or(fn() { fields.get(f, "idle") })
  use ttl <- result.try(case wanted {
    None -> Ok(config.ttl)
    Some(v) ->
      config.parse_seconds(fields.value_text(v))
      |> result.replace_error(fail.new(
        400,
        "invalid ttl value",
        "Use seconds or a unit: 3600, 90m, 72h, 7d.",
      ))
  })
  let ttl = int.max(ttl, config.ttl_min)
  let ttl = case config.ttl_max {
    0 -> ttl
    max -> int.min(ttl, max)
  }
  let topic = fields.utf16_slice(fields.text(f, "topic"), 2000)
  let host = fields.clean_handle(fields.text(f, "handle"), "host")
  use #(id, me) <- result.try(
    actor_call(web.registry, 30_000, registry.Create(topic, ttl, host, _))
    |> result.replace_error(fail.bare(500, "internal error"))
    |> result.flatten,
  )
  let room_url = c.base <> "/r/" <> id
  Ok(send_json(
    201,
    json.object([
      #("room_url", json.string(room_url)),
      #(
        "share",
        json.string(
          "Give this URL to your agent and ask it to fetch it; the page explains how to join: "
          <> room_url,
        ),
      ),
      #("handle", json.string(me.handle)),
      #("token", json.string(me.token)),
      #("role", json.string("host")),
      // Message 1 is the host's own "created the room".
      #("cursor", json.int(1)),
      #("ttl", json.int(ttl)),
      #(
        "next",
        json.string(
          "The room never notifies you. To hear when someone joins or writes, long-poll with your token and repeat: GET "
          <> room_url
          <> "/messages?since=1&wait=50&format=text",
        ),
      ),
    ]),
    [],
  ))
}

fn in_room(
  web: Web,
  c: Ctx,
  id: String,
  action: Option(String),
  method: http.Method,
) -> Result(Response(ResponseData), HttpError) {
  // Ids only ever come from rand(); anything else is a 404 before it can touch a map or a path.
  use <- bool_guard(
    !is_room_id(id),
    fail.bare(404, "no such room") |> fail.with_headers([noindex]),
  )
  let gone =
    fail.new(
      404,
      "no such room",
      "Rooms are deleted after a while without activity. This one is gone.",
    )
    |> fail.with_headers([noindex])
  use subject <- result.try(
    actor_call(web.registry, 5000, registry.Lookup(id, _))
    |> result.unwrap(None)
    |> option.to_result(gone),
  )
  let input =
    room.Input(raw: c.body, content_type: content_type(c), query: c.query)
  case action, method {
    None, Get -> {
      use content <- result.map(ask(subject, gone, 5000, room.View(False, _)))
      case content {
        room.Gone(t) -> tombstone_page(t)
        room.Open(r) -> room_page(web, c, r)
        room.Unloaded(_) -> error_response(gone)
      }
    }
    Some("logs"), Get -> {
      use content <- result.map(ask(subject, gone, 30_000, room.View(True, _)))
      case content {
        room.Gone(t) -> tombstone_page(t)
        room.Open(r) -> logs(web.config, c, r)
        room.Unloaded(_) -> error_response(gone)
      }
    }
    Some("join"), Post -> {
      use me <- result.map(
        ask_result(subject, gone, room.Join(c.token, input, _)),
      )
      send_json(
        201,
        json.object([
          #("handle", json.string(me.handle)),
          #("token", json.string(me.token)),
          #("role", json.string("guest")),
          #("cursor", json.int(0)),
          #(
            "next",
            json.string(
              "Read the history, then long-poll for replies and repeat: GET "
              <> c.base
              <> "/r/"
              <> id
              <> "/messages?since=0&wait=50&format=text",
            ),
          ),
        ]),
        [noindex],
      )
    }
    Some("messages"), Get -> read(web, c, subject, gone)
    Some("messages"), Post -> {
      use m <- result.map(
        ask_result(subject, gone, room.Post(c.token, input, _)),
      )
      // Posting is the moment agents forget that nobody will call them back.
      send_json(
        201,
        json.object([
          #("id", json.int(m.id)),
          #("ts", json.string(m.ts)),
          #(
            "next",
            json.string(
              "Replies are not pushed to you: GET "
              <> c.base
              <> "/r/"
              <> id
              <> "/messages?since=YOUR_CURSOR&wait=50&format=text and repeat until one arrives",
            ),
          ),
        ]),
        [noindex],
      )
    }
    Some("leave"), Post -> {
      use Nil <- result.map(ask_result(subject, gone, room.Leave(c.token, _)))
      send_json(200, json.object([#("ok", json.bool(True))]), [])
    }
    Some("close"), Post -> {
      use status <- result.map(
        ask_result(subject, gone, room.Close(c.token, input, _)),
      )
      send_json(
        200,
        json.object([#("ok", json.bool(True)), #("status", json.string(status))]),
        [],
      )
    }
    // Purge deletes the content at once but leaves a tombstone: the act itself stays visible.
    Some("purge"), Post -> {
      use t <- result.map(ask_result(subject, gone, room.Purge(c.token, _)))
      send_json(
        200,
        json.object([
          #("ok", json.bool(True)),
          #("status", json.string("purged")),
          #("tombstone", store.tombstone_json(t)),
        ]),
        [],
      )
    }
    Some("participants"), Get -> {
      use content <- result.try(ask(subject, gone, 5000, room.View(False, _)))
      case content {
        room.Gone(t) -> Error(room.purged_error(t))
        room.Unloaded(_) -> Error(gone)
        room.Open(r) ->
          Ok(
            send_json(
              200,
              json.object([
                #(
                  "participants",
                  json.array(r.state.participants, fn(p) {
                    json.object([
                      #("handle", json.string(p.handle)),
                      #("role", json.string(p.role)),
                      #("left", json.bool(p.left)),
                    ])
                  }),
                ),
              ]),
              [noindex],
            ),
          )
      }
    }
    _, _ -> {
      // A purged room answers 410 to anything; a live one does not know the action.
      use content <- result.try(ask(subject, gone, 5000, room.View(False, _)))
      case content {
        room.Gone(t) -> Error(room.purged_error(t))
        room.Open(_) -> Error(not_found(c))
        room.Unloaded(_) -> Error(gone)
      }
    }
  }
}

fn read(
  web: Web,
  c: Ctx,
  subject: Subject(room.Msg),
  gone: HttpError,
) -> Result(Response(ResponseData), HttpError) {
  let param = fn(name) { list.key_find(c.query, name) |> result.unwrap("") }
  let number = fn(name) {
    config.parse_number(param(name)) |> result.unwrap(0.0)
  }
  let q =
    room.Query(
      since: float.floor(number("since")) |> float.truncate,
      for_me: param("for_me") == "1",
    )
  let wait = float.min(float.max(number("wait"), 0.0), web.config.max_wait)
  let wait_ms = float.round(wait *. 1000.0)
  case wait_ms > 0 {
    True -> collect_garbage()
    False -> Nil
  }
  use reading <- result.try(
    actor_call(subject, wait_ms + 10_000, room.Read(
      c.token,
      q,
      wait_ms,
      c.client,
      _,
    ))
    |> result.replace_error(gone)
    |> result.flatten,
  )
  let meta = [
    #("x-room-cursor", int.to_string(reading.cursor)),
    #("x-room-status", reading.status),
    ..list.append(left_headers(reading.left), [noindex])
  ]
  case param("format") {
    "text" -> Ok(send(200, reading_text(reading), "text/plain", meta))
    _ ->
      Ok(send_json(
        200,
        json.object([
          #("messages", json.array(reading.messages, store.message_json)),
          #("cursor", json.int(reading.cursor)),
          #("status", json.string(reading.status)),
        ]),
        meta,
      ))
  }
}

fn reading_text(r: Reading) -> String {
  format_text(r.messages, r.cursor, r.status, r.present, r.total, r.left)
}

fn room_page(web: Web, c: Ctx, r: room.Room) -> Response(ResponseData) {
  let vars = room_vars(web.config, c.base, r)
  let md = render(docs().room_md, vars)
  case c.html {
    False -> send(200, md, "text/markdown", [noindex, vary])
    True -> {
      let escaped = list.map(vars, fn(kv) { #(kv.0, escape_html(kv.1)) })
      let topic = case r.state.topic {
        "" -> "(none given)"
        t -> t
      }
      let vars =
        list.append(escaped, [
          #("topic", escape_html(topic)),
          #("markdown", escape_html(md)),
        ])
      send(200, render(docs().room_html, vars), "text/html", [noindex, vary])
    }
  }
}

fn room_vars(
  config: Config,
  base: String,
  r: room.Room,
) -> List(#(String, String)) {
  let s = r.state
  let people =
    s.participants
    |> list.map(fn(p) {
      p.handle
      <> case p.role {
        "host" -> " (host)"
        _ -> ""
      }
      <> case p.left {
        True -> " (left)"
        False -> ""
      }
    })
    |> string.join(", ")
  let lifetime = case s.status {
    "open" ->
      "deleted "
      <> config.human_duration(s.ttl)
      <> " after its last activity ("
      <> s.last_activity
      <> ")"
    _ ->
      "closed at "
      <> option.unwrap(s.ended_at, "null")
      <> "; readable until "
      <> room.delete_after(r)
  }
  let topic = case s.topic {
    "" -> "> (none given)"
    t ->
      string.split(t, "\n")
      |> list.map(fn(l) { "> " <> l })
      |> string.join("\n")
  }
  let unlimited = fn(n) {
    case n {
      0 -> "unlimited"
      n -> int.to_string(n)
    }
  }
  let left = case left_text(s.status, room.capacity(config, r)) {
    "" ->
      case s.status {
        "open" -> "unlimited"
        _ -> "none, the room has ended"
      }
    text -> string.drop_start(text, string.length(" | left: "))
  }
  [
    #("id", s.id),
    #("base", base),
    #("room", base <> "/r/" <> s.id),
    #("status", s.status),
    #("lifetime", lifetime),
    #("participants", people),
    #("topic", topic),
    #("ttl", config.human_duration(s.ttl)),
    #("max_body", int.to_string(config.max_body)),
    #("max_wait", js_number(config.max_wait)),
    #("max_room_bytes", unlimited(config.max_room_bytes)),
    #("max_messages", unlimited(config.max_messages)),
    #("left", left),
  ]
}

fn logs(config: Config, c: Ctx, r: room.Room) -> Response(ResponseData) {
  let format = list.key_find(c.query, "format")
  let accept = request.get_header(c.req, "accept") |> result.unwrap("")
  let messages = list.reverse(r.messages)
  let wants_lines =
    format == Ok("jsonl")
    || {
      format == Error(Nil)
      && list.any(["ndjson", "jsonl", "application/json"], string.contains(
        accept,
        _,
      ))
    }
  case wants_lines {
    True ->
      send(
        200,
        list.map(messages, fn(m) { json.to_string(store.message_json(m)) })
        |> string.join("\n")
          <> "\n",
        "application/x-ndjson",
        [noindex, vary],
      )
    False -> {
      let present = list.count(r.state.participants, fn(p) { !p.left })
      let total = list.length(r.state.participants)
      let text =
        "# Log of room "
        <> r.state.id
        <> " ("
        <> r.state.status
        <> ")\n\n"
        <> format_text(
          messages,
          r.count,
          r.state.status,
          present,
          total,
          room.capacity(config, r),
        )
      case c.html && format == Error(Nil) {
        True -> {
          let page =
            "<!doctype html><meta charset=\"utf-8\"><meta name=\"robots\" content=\"noindex\"><meta name=\"color-scheme\" content=\"light dark\"><title>parlor log "
            <> r.state.id
            <> "</title><pre style=\"white-space:pre-wrap;font:14px/1.5 ui-monospace,monospace;max-width:90ch;margin:2rem auto;padding:0 1rem\">"
            <> escape_html(text)
            <> "</pre>"
          send(200, page, "text/html", [noindex, vary])
        }
        False -> send(200, text, "text/plain", [noindex, vary])
      }
    }
  }
}

fn tombstone_page(t: store.Tombstone) -> Response(ResponseData) {
  let text =
    "# Room "
    <> t.id
    <> " was purged\n\nThe host ("
    <> t.purged_by
    <> ") purged this room at "
    <> t.purged_at
    <> ". "
    <> int.to_string(t.messages_removed)
    <> " messages from "
    <> int.to_string(t.participants)
    <> " participants were deleted. The room was created at "
    <> t.created_at
    <> ". This notice disappears after "
    <> t.delete_after
    <> ".\n"
  send(410, text, "text/markdown", [noindex])
}

// ---- text ----------------------------------------------------------------------------------

/// The transcript: `[#ID HH:MM:SS] sender: text`, one entry per message, then the footer
/// `--- cursor: N | status: S | present: P/T | left: B bytes, M messages | nothing new`.
fn format_text(
  messages: List(Message),
  cursor: Int,
  status: String,
  present: Int,
  total: Int,
  left: room.Capacity,
) -> String {
  let lines =
    list.map(messages, fn(m) {
      let who = case m.kind {
        "system" -> "*"
        _ -> option.unwrap(m.from, "null")
      }
      let dest = case m.to {
        Some(to) if to != "" -> " -> " <> to
        _ -> ""
      }
      let re = case m.reply_to {
        Some(r) if r != 0 -> " (re #" <> int.to_string(r) <> ")"
        _ -> ""
      }
      "[#"
      <> int.to_string(m.id)
      <> " "
      <> string.slice(m.ts, 11, 8)
      <> "] "
      <> who
      <> dest
      <> re
      <> ": "
      <> string.replace(m.body, "\n", "\n    ")
    })
  let footer =
    "--- cursor: "
    <> int.to_string(cursor)
    <> " | status: "
    <> status
    <> " | present: "
    <> int.to_string(present)
    <> "/"
    <> int.to_string(total)
    <> left_text(status, left)
    <> case messages {
      [] -> " | nothing new"
      _ -> ""
    }
  string.join(list.append(lines, [footer]), "\n") <> "\n"
}

// ` | left: 831488 bytes, 9120 messages` while the room is open and a cap is set; else nothing.
fn left_text(status: String, left: room.Capacity) -> String {
  let parts =
    [
      option.map(left.bytes, fn(b) { int.to_string(b) <> " bytes" }),
      option.map(left.messages, fn(m) { int.to_string(m) <> " messages" }),
    ]
    |> option.values
  case status, parts {
    "open", [_, ..] -> " | left: " <> string.join(parts, ", ")
    _, _ -> ""
  }
}

fn left_headers(left: room.Capacity) -> List(#(String, String)) {
  [
    option.map(left.bytes, fn(b) { #("x-room-bytes-left", int.to_string(b)) }),
    option.map(left.messages, fn(m) {
      #("x-room-messages-left", int.to_string(m))
    }),
  ]
  |> option.values
}

/// `{{name}}` replaced by its value in one pass, unknown names by nothing, as the Node server's
/// `tpl.replace(/\{\{(\w+)\}\}/g, ...)` does. Values are never scanned again.
pub fn render(template: String, vars: List(#(String, String))) -> String {
  render_loop(template, dict.from_list(vars), "")
}

fn render_loop(rest: String, vars, acc: String) -> String {
  case string.split_once(rest, "{{") {
    Error(_) -> acc <> rest
    Ok(#(before, after)) -> {
      let name = take_word(after, "")
      case
        name != ""
        && string.starts_with(
          string.drop_start(after, string.length(name)),
          "}}",
        )
      {
        True ->
          render_loop(
            string.drop_start(after, string.length(name) + 2),
            vars,
            acc <> before <> { dict.get(vars, name) |> result.unwrap("") },
          )
        // Not a placeholder: keep one brace and look again from the next.
        False -> render_loop("{" <> after, vars, acc <> before <> "{")
      }
    }
  }
}

fn take_word(s: String, acc: String) -> String {
  case string.pop_grapheme(s) {
    Ok(#(g, rest)) ->
      case is_word(g) {
        True -> take_word(rest, acc <> g)
        False -> acc
      }
    Error(_) -> acc
  }
}

fn is_word(g: String) -> Bool {
  case string.to_utf_codepoints(g) {
    [cp] -> {
      let c = string.utf_codepoint_to_int(cp)
      { c >= 0x61 && c <= 0x7A }
      || { c >= 0x41 && c <= 0x5A }
      || { c >= 0x30 && c <= 0x39 }
      || c == 0x5F
    }
    _ -> False
  }
}

pub fn escape_html(s: String) -> String {
  s
  |> string.replace("&", "&amp;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
  |> string.replace("\"", "&quot;")
  |> string.replace("'", "&#39;")
}

fn replace_first(s: String, pattern: String, with: String) -> String {
  case string.split_once(s, pattern) {
    Ok(#(before, after)) -> before <> with <> after
    Error(_) -> s
  }
}

fn js_number(f: Float) -> String {
  let whole = float.truncate(f)
  case int.to_float(whole) == f {
    True -> int.to_string(whole)
    False -> float.to_string(f)
  }
}

fn is_room_id(id: String) -> Bool {
  let n = string.length(id)
  n >= 8
  && n <= 32
  && string.to_utf_codepoints(id)
  |> list.all(fn(cp) {
    let c = string.utf_codepoint_to_int(cp)
    fields.is_handle_char(c) && c != 0x2E
  })
}

fn content_type(c: Ctx) -> String {
  request.get_header(c.req, "content-type") |> result.unwrap("")
}

// ---- responses -----------------------------------------------------------------------------

const vary = #("vary", "Accept")

const noindex = #("x-robots-tag", "noindex, nofollow")

// Pages carry inline style and script of their own and fetch only from their origin.
const security = [
  #(
    "content-security-policy",
    "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'",
  ),
  #("x-content-type-options", "nosniff"),
  #("referrer-policy", "no-referrer"),
]

fn send(
  status: Int,
  body: String,
  kind: String,
  headers: List(#(String, String)),
) -> Response(ResponseData) {
  // From the moment a shutdown starts, every answer tells the proxy not to keep the connection
  // to a process that is about to exit.
  let closing = case room.is_draining() {
    True -> [#("connection", "close")]
    False -> []
  }
  let all =
    [
      #("content-type", kind <> "; charset=utf-8"),
      #("cache-control", "no-store"),
    ]
    |> list.append(security)
    |> list.append(closing)
    |> list.append(headers)
  list.fold(all, response.new(status), fn(resp, h) {
    response.set_header(resp, h.0, h.1)
  })
  |> response.set_body(mist.Bytes(bytes_tree.from_string(body)))
}

fn send_json(
  status: Int,
  body: Json,
  headers: List(#(String, String)),
) -> Response(ResponseData) {
  send(status, json.to_string(body) <> "\n", "application/json", headers)
}

fn error_response(e: HttpError) -> Response(ResponseData) {
  let fields = [#("error", json.string(e.error))]
  let fields = case e.hint {
    Some(h) -> list.append(fields, [#("hint", json.string(h))])
    None -> fields
  }
  send_json(e.status, json.object(fields), e.headers)
}

// ---- calling processes ---------------------------------------------------------------------

/// Sends a request and waits for the answer. Error when the process is gone (a room deleted a
/// moment ago) or does not answer in time; never crashes the caller.
fn actor_call(
  subject: Subject(msg),
  timeout: Int,
  make: fn(Subject(reply)) -> msg,
) -> Result(reply, Nil) {
  case process.subject_owner(subject) {
    Error(_) -> Error(Nil)
    Ok(pid) -> {
      let monitor = process.monitor(pid)
      let reply = process.new_subject()
      process.send(subject, make(reply))
      let result =
        process.new_selector()
        |> process.select_map(reply, Ok)
        |> process.select_specific_monitor(monitor, fn(_) { Error(Nil) })
        |> process.selector_receive(timeout)
        |> result.flatten
      process.demonitor_process(monitor)
      result
    }
  }
}

fn ask(
  subject: Subject(msg),
  gone: HttpError,
  timeout: Int,
  make: fn(Subject(reply)) -> msg,
) -> Result(reply, HttpError) {
  actor_call(subject, timeout, make) |> result.replace_error(gone)
}

fn ask_result(
  subject: Subject(msg),
  gone: HttpError,
  make: fn(Subject(Result(reply, HttpError))) -> msg,
) -> Result(reply, HttpError) {
  ask(subject, gone, 5000, make) |> result.flatten
}

fn bool_guard(
  cond: Bool,
  error: HttpError,
  next: fn() -> Result(a, HttpError),
) -> Result(a, HttpError) {
  case cond {
    True -> Error(error)
    False -> next()
  }
}
