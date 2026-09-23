//// A room is a process. It owns the room's state, appends to its log, and holds the long-polls
//// of everyone waiting in it: a wait is a message this process answers later. Nothing else
//// touches a room's data, so there is nothing to lock.

import gleam/bit_array
import gleam/crypto
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject, type Timer}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import gleam/string
import parlor/clock
import parlor/config.{type Config, human_duration, parse_number}
import parlor/fail.{type HttpError}
import parlor/fields
import parlor/store.{type Message, type Participant, type State, type Tombstone}
import simplifile

// ---- the room's data -------------------------------------------------------------------------

pub type Room {
  Room(
    state: State,
    /// Newest first: appending and reading what is new are both cheap.
    messages: List(Message),
    count: Int,
    /// Participants' messages and their bytes: what the caps count. Join and leave lines do not.
    posts: Int,
    bytes: Int,
    /// Changed since state.json was last written (activity times); written at the next sweep.
    dirty: Bool,
  )
}

pub type Content {
  Open(Room)
  Gone(Tombstone)
}

/// What the web layer needs to answer a read: the selected messages and the room around them.
pub type Reading {
  Reading(
    messages: List(Message),
    cursor: Int,
    status: String,
    present: Int,
    total: Int,
    left: Capacity,
  )
}

/// What /messages can still take, as numbers a writer compares with its own size. None when the
/// operator set no cap.
pub type Capacity {
  Capacity(bytes: Option(Int), messages: Option(Int))
}

pub type Joined {
  Joined(handle: String, token: String)
}

/// A request body as the web layer read it: the text, or Error when it was over MAX_BODY. The
/// room decides when that matters, so errors come in the same order as from the Node server.
pub type Input {
  Input(
    raw: Result(String, Nil),
    content_type: String,
    query: List(#(String, String)),
  )
}

pub type Query {
  Query(since: Int, for_me: Bool)
}

pub type Msg {
  /// A copy of the room, for its page, /logs and /participants. `messages: False` leaves the
  /// log out of the copy.
  View(messages: Bool, reply: Subject(Content))
  Read(
    token: Option(String),
    query: Query,
    wait_ms: Int,
    client: String,
    reply: Subject(Result(Reading, HttpError)),
  )
  Join(
    token: Option(String),
    input: Input,
    reply: Subject(Result(Joined, HttpError)),
  )
  Post(
    token: Option(String),
    input: Input,
    reply: Subject(Result(Message, HttpError)),
  )
  Leave(token: Option(String), reply: Subject(Result(Nil, HttpError)))
  Close(
    token: Option(String),
    input: Input,
    reply: Subject(Result(String, HttpError)),
  )
  Purge(token: Option(String), reply: Subject(Result(Tombstone, HttpError)))
  Sweep
  /// The server is going down: answer every held wait now, write what is unwritten.
  Drain
  Expire(ref: Int)
}

/// What a room needs from outside: the configuration, and the server-wide count of held waits
/// (MAX_WAITERS, MAX_WAITERS_PER_CLIENT), which the registry keeps.
pub type Deps {
  Deps(config: Config, try_hold: fn(String) -> Bool, release: fn(String) -> Nil)
}

type Waiter {
  Waiter(
    ref: Int,
    handle: Option(String),
    query: Query,
    client: String,
    reply: Subject(Result(Reading, HttpError)),
    timer: Timer,
  )
}

type Window {
  Window(count: Int, reset: Int)
}

type Actor {
  Actor(
    content: Content,
    waiters: List(Waiter),
    next_ref: Int,
    windows: Dict(String, Window),
    self: Subject(Msg),
    deps: Deps,
  )
}

// ---- starting ------------------------------------------------------------------------------

/// A new room, with its host. Returns the room's subject and the host's token.
pub fn create(
  deps: Deps,
  id: String,
  topic: String,
  ttl: Int,
  host: String,
) -> Result(#(Subject(Msg), process.Pid, Joined), actor.StartError) {
  start(deps, fn() {
    let now = clock.now()
    let state =
      store.State(
        id:,
        topic:,
        status: "open",
        created_at: now,
        last_activity: now,
        ttl:,
        ended_at: None,
        participants: [],
        delete_after: None,
      )
    let room =
      Room(state:, messages: [], count: 0, posts: 0, bytes: 0, dirty: False)
    let #(room, me) = add_participant(deps.config, room, host, "host")
    persist(deps.config, room)
    let room =
      append_quiet(
        deps.config,
        room,
        system_line(me.handle <> " created the room"),
      )
    Ok(#(Open(room), me))
  })
}

/// A room from the data directory. Rooms that ended by expiring (an older status) are open again.
pub fn load(
  deps: Deps,
  id: String,
) -> Result(#(Subject(Msg), process.Pid, Nil), actor.StartError) {
  start(deps, fn() {
    use loaded <- result.try(store.load(
      deps.config.data_dir,
      id,
      deps.config.ttl,
    ))
    case loaded {
      store.Purged(t) -> Ok(#(Gone(t), Nil))
      store.Live(state, messages, legacy) -> {
        let status = case state.status {
          "expired" -> "open"
          s -> s
        }
        let state = case status {
          "open" ->
            store.State(..state, status:, delete_after: None, ended_at: None)
          _ -> store.State(..state, status:)
        }
        let posts = list.filter(messages, fn(m) { m.kind == "message" })
        Ok(#(
          Open(Room(
            state:,
            messages: list.reverse(messages),
            count: list.length(messages),
            posts: list.length(posts),
            bytes: list.fold(posts, 0, fn(n, m) { n + string.byte_size(m.body) }),
            dirty: legacy || status != state.status,
          )),
          Nil,
        ))
      }
    }
  })
}

fn start(
  deps: Deps,
  init: fn() -> Result(#(Content, a), String),
) -> Result(#(Subject(Msg), process.Pid, a), actor.StartError) {
  actor.new_with_initialiser(30_000, fn(self) {
    use #(content, extra) <- result.map(init())
    Actor(content:, waiters: [], next_ref: 0, windows: dict.new(), self:, deps:)
    |> actor.initialised
    |> actor.returning(#(self, extra))
  })
  |> actor.on_message(handle)
  |> actor.start
  |> result.map(fn(started) {
    let #(subject, extra) = started.data
    #(subject, started.pid, extra)
  })
}

// ---- messages ------------------------------------------------------------------------------

fn handle(a: Actor, msg: Msg) -> actor.Next(Actor, Msg) {
  let config = a.deps.config
  case a.content, msg {
    content, View(with_messages, reply) -> {
      process.send(reply, case content, with_messages {
        Open(room), False -> Open(Room(..room, messages: []))
        _, _ -> content
      })
      actor.continue(a)
    }

    Gone(t), Read(reply:, ..) -> reply_gone(a, t, reply)
    Gone(t), Join(reply:, ..) -> reply_gone(a, t, reply)
    Gone(t), Post(reply:, ..) -> reply_gone(a, t, reply)
    Gone(t), Leave(reply:, ..) -> reply_gone(a, t, reply)
    Gone(t), Close(reply:, ..) -> reply_gone(a, t, reply)
    Gone(t), Purge(reply:, ..) -> reply_gone(a, t, reply)

    Open(room), Read(token, query, wait_ms, client, reply) -> {
      let #(room, me) = authenticate(room, token)
      let handle = option.map(me, fn(p) { p.handle })
      let a = Actor(..a, content: Open(room))
      let hold =
        wait_ms > 0
        && !is_draining()
        && room.state.status == "open"
        && !has_news(room, handle, query)
        && a.deps.try_hold(client)
      case hold {
        False -> {
          process.send(reply, Ok(reading(config, room, handle, query)))
          actor.continue(a)
        }
        True -> {
          let timer = process.send_after(a.self, wait_ms, Expire(a.next_ref))
          let w =
            Waiter(ref: a.next_ref, handle:, query:, client:, reply:, timer:)
          actor.continue(
            Actor(..a, waiters: [w, ..a.waiters], next_ref: a.next_ref + 1),
          )
        }
      }
    }

    Open(room), Expire(ref) -> {
      let #(expired, rest) = list.partition(a.waiters, fn(w) { w.ref == ref })
      list.each(expired, answer(config, room, _, a.deps))
      actor.continue(Actor(..a, waiters: rest))
    }
    Gone(_), Expire(_) -> actor.continue(a)

    Open(room), Join(token, input, reply) -> {
      let #(a, result) = join(a, room, token, input)
      process.send(reply, result)
      actor.continue(a)
    }

    Open(room), Post(token, input, reply) -> {
      let #(a, result) = post(a, room, token, input)
      process.send(reply, result)
      actor.continue(a)
    }

    Open(room), Leave(token, reply) -> {
      let #(room, me) = authenticate(room, token)
      let a = Actor(..a, content: Open(room))
      case require(room, token, me) {
        Error(e) -> {
          process.send(reply, Error(e))
          actor.continue(a)
        }
        Ok(me) ->
          case me.left || room.state.status != "open" {
            True -> {
              process.send(reply, Ok(Nil))
              actor.continue(a)
            }
            False -> {
              let room = set_left(room, me.handle, True)
              persist(config, room)
              let a = append(a, room, system_line(me.handle <> " left"), True)
              process.send(reply, Ok(Nil))
              actor.continue(a)
            }
          }
      }
    }

    Open(room), Close(token, input, reply) -> {
      let #(a, result) = close(a, room, token, input)
      process.send(reply, result)
      actor.continue(a)
    }

    Open(room), Purge(token, reply) -> {
      let #(room, me) = authenticate(room, token)
      let a = Actor(..a, content: Open(room))
      case require(room, token, me) {
        Error(e) -> {
          process.send(reply, Error(e))
          actor.continue(a)
        }
        Ok(me) if me.role != "host" -> {
          process.send(
            reply,
            Error(fail.bare(403, "only the host can purge the room")),
          )
          actor.continue(a)
        }
        Ok(me) -> {
          let now = clock.now_ms()
          let t =
            store.Tombstone(
              id: room.state.id,
              purged_by: me.handle,
              purged_at: clock.iso(now),
              created_at: room.state.created_at,
              messages_removed: room.count,
              participants: list.length(room.state.participants),
              delete_after: clock.iso(now + room.state.ttl * 1000),
            )
          let purged =
            Room(..room, state: store.State(..room.state, status: "purged"))
          list.each(a.waiters, answer(config, purged, _, a.deps))
          store.purge(config.data_dir, room.state.id, t)
          process.send(reply, Ok(t))
          actor.continue(Actor(..a, content: Gone(t), waiters: []))
        }
      }
    }

    content, Sweep -> sweep(a, content)

    Open(room), Drain -> {
      list.each(a.waiters, answer(config, room, _, a.deps))
      let room = case room.dirty {
        True -> persist(config, room)
        False -> room
      }
      actor.continue(Actor(..a, content: Open(room), waiters: []))
    }
    Gone(_), Drain -> actor.continue(a)
  }
}

fn reply_gone(
  a: Actor,
  t: Tombstone,
  reply: Subject(Result(b, HttpError)),
) -> actor.Next(Actor, Msg) {
  process.send(reply, Error(purged_error(t)))
  actor.continue(a)
}

pub fn purged_error(t: Tombstone) -> HttpError {
  fail.new(
    410,
    "room was purged",
    "Purged by " <> t.purged_by <> " at " <> t.purged_at <> ".",
  )
  |> fail.with_headers([#("x-robots-tag", "noindex, nofollow")])
}

// Answer a held wait with the room as it is now, and stop counting it.
fn answer(config: Config, room: Room, w: Waiter, deps: Deps) -> Nil {
  process.cancel_timer(w.timer)
  deps.release(w.client)
  process.send(w.reply, Ok(reading(config, room, w.handle, w.query)))
}

// ---- joining, posting, closing -------------------------------------------------------------

fn join(
  a: Actor,
  room: Room,
  token: Option(String),
  input: Input,
) -> #(Actor, Result(Joined, HttpError)) {
  let config = a.deps.config
  let id = room.state.id
  case room.state.status {
    "open" -> {
      let #(room, me) = authenticate(room, token)
      let a = Actor(..a, content: Open(room))
      let full =
        config.max_participants > 0
        && list.length(room.state.participants) >= config.max_participants
      case me, full, input.raw {
        Some(_), _, _ -> #(
          a,
          Error(fail.new(
            409,
            "you are already in this room",
            "Use the token you already have.",
          )),
        )
        _, True, _ -> #(
          a,
          Error(fail.new(
            403,
            "room is full",
            "Limit is "
              <> int.to_string(config.max_participants)
              <> " participants.",
          )),
        )
        _, _, Error(_) -> #(a, Error(too_large(config)))
        None, False, Ok(raw) ->
          case fields.parse(raw, input.content_type, input.query, form: True) {
            Error(e) -> #(a, Error(e))
            Ok(f) -> {
              let wanted =
                fields.clean_handle(fields.text(f, "handle"), "guest")
              let #(room, me) = add_participant(config, room, wanted, "guest")
              let room = touch(room)
              persist(config, room)
              let a = append(a, room, system_line(me.handle <> " joined"), True)
              #(a, Ok(me))
            }
          }
      }
    }
    status -> #(
      a,
      Error(fail.new(
        410,
        "room is " <> status,
        "The log is still readable: GET /r/" <> id <> "/logs",
      )),
    )
  }
}

const full_hint = "Only the host can end it, with a last message (POST /close with a body), usually pointing to a new room. Wait for that, or start a new room."

fn post(
  a: Actor,
  room: Room,
  token: Option(String),
  input: Input,
) -> #(Actor, Result(Message, HttpError)) {
  let config = a.deps.config
  let #(room, me) = authenticate(room, token)
  let a = Actor(..a, content: Open(room))
  let left = capacity(config, room)
  let result = {
    use me <- result.try(require(room, token, me))
    use <- guard(room.state.status != "open", fn() {
      fail.new(
        410,
        "room is " <> room.state.status,
        "No more posts. The log is still readable.",
      )
    })
    // Same rule for everyone, host included: a post must leave room for one more message.
    use <- guard(left.messages == Some(0) || left.bytes == Some(0), fn() {
      fail.new(403, "room is full", full_hint)
    })
    Ok(me)
  }
  case result {
    Error(e) -> #(a, Error(e))
    Ok(me) -> {
      let #(a, limited) = rate_limit(a, me.handle)
      case limited {
        Error(e) -> #(a, Error(e))
        Ok(Nil) ->
          case post_checked(config, room, me, input, left) {
            Error(e) -> #(a, Error(e))
            Ok(#(body, to, reply_to)) -> {
              let room = case me.left {
                True -> Room(..set_left(room, me.handle, False), dirty: True)
                False -> room
              }
              let line =
                store.Message(
                  id: 0,
                  ts: "",
                  kind: "message",
                  from: Some(me.handle),
                  to:,
                  reply_to:,
                  body:,
                )
              let a = append(a, room, line, True)
              let assert Open(Room(messages: [posted, ..], ..)) = a.content
              #(a, Ok(posted))
            }
          }
      }
    }
  }
}

fn post_checked(
  config: Config,
  room: Room,
  me: Participant,
  input: Input,
  left: Capacity,
) -> Result(#(String, Option(String), Option(Int)), HttpError) {
  let _ = me
  use raw <- result.try(input.raw |> result.replace_error(too_large(config)))
  use f <- result.try(fields.parse(
    raw,
    input.content_type,
    input.query,
    form: False,
  ))
  let body = fields.body(f, raw)
  use <- guard(fields.is_blank(body), fn() {
    fail.new(
      400,
      "empty message",
      "Send the text as the request body, or JSON {\"body\": \"...\"}.",
    )
  })
  let size = string.byte_size(body)
  use <- guard(
    case left.bytes {
      Some(b) -> size > b
      None -> False
    },
    fn() {
      fail.new(
        403,
        "message does not fit",
        "Your message is "
          <> int.to_string(size)
          <> " bytes; "
          <> int.to_string(option.unwrap(left.bytes, 0))
          <> " remain. Shorten it, or post a link.",
      )
    },
  )
  use Nil <- result.try(reject_tokens(room, body))
  use to <- result.try(case fields.truthy(f, "to") {
    False -> Ok(None)
    True -> {
      let raw_to = fields.text(f, "to")
      case by_handle(room, fields.clean_handle(raw_to, "")) {
        Ok(target) -> Ok(Some(target.handle))
        Error(_) ->
          Error(fail.new(
            404,
            "no participant \"" <> raw_to <> "\"",
            "Participants: "
              <> list.map(room.state.participants, fn(p) { p.handle })
            |> string.join(", "),
          ))
      }
    }
  })
  use reply_to <- result.try(case fields.truthy(f, "reply_to") {
    False -> Ok(None)
    True ->
      case parse_number(fields.text(f, "reply_to")) {
        // NaN: JavaScript stores it, and JSON writes it as null.
        Error(_) -> Ok(None)
        Ok(0.0) -> Ok(Some(0))
        Ok(n) -> {
          let whole = float.truncate(n)
          case int.to_float(whole) == n && whole >= 1 && whole <= room.count {
            True -> Ok(Some(whole))
            False ->
              Error(fail.new(
                400,
                "cannot reply to #" <> number_text(n),
                "No such message.",
              ))
          }
        }
      }
  })
  Ok(#(body, to, reply_to))
}

fn number_text(n: Float) -> String {
  let whole = float.truncate(n)
  case int.to_float(whole) == n {
    True -> int.to_string(whole)
    False -> float.to_string(n)
  }
}

fn close(
  a: Actor,
  room: Room,
  token: Option(String),
  input: Input,
) -> #(Actor, Result(String, HttpError)) {
  let config = a.deps.config
  let #(room, me) = authenticate(room, token)
  let a = Actor(..a, content: Open(room))
  let checked = {
    use me <- result.try(require(room, token, me))
    use <- guard(me.role != "host", fn() {
      fail.new(
        403,
        "only the host can close the room",
        "You can POST /leave instead.",
      )
    })
    use raw <- result.try(input.raw |> result.replace_error(too_large(config)))
    use f <- result.try(fields.parse(
      raw,
      input.content_type,
      input.query,
      form: False,
    ))
    let body = fields.body(f, raw)
    let last_word = !fields.is_blank(body) && room.state.status == "open"
    use Nil <- result.try(case last_word {
      True -> reject_tokens(room, body)
      False -> Ok(Nil)
    })
    Ok(
      #(me, case last_word {
        True -> Some(body)
        False -> None
      }),
    )
  }
  case checked {
    Error(e) -> #(a, Error(e))
    Ok(#(me, last_word)) -> {
      // An optional last word, written even when the room is full: that space is held back for
      // exactly this. Not waking anyone yet: the close line that follows releases every waiter
      // with both, typically "continued at <url>" and the closed status in one response.
      let a = case last_word {
        Some(body) ->
          append(
            a,
            room,
            store.Message(
              id: 0,
              ts: "",
              kind: "message",
              from: Some(me.handle),
              to: None,
              reply_to: None,
              body:,
            ),
            False,
          )
        None -> a
      }
      let a = end(a, me.handle <> " closed the room")
      let assert Open(room) = a.content
      #(a, Ok(room.state.status))
    }
  }
}

fn end(a: Actor, reason: String) -> Actor {
  let assert Open(room) = a.content
  case room.state.status {
    "open" -> {
      let now = clock.now_ms()
      let room =
        Room(
          ..room,
          state: store.State(
            ..room.state,
            status: "closed",
            ended_at: Some(clock.iso(now)),
            delete_after: Some(clock.iso(now + room.state.ttl * 1000)),
          ),
        )
      let a = append(a, room, system_line(reason), True)
      let assert Open(room) = a.content
      let room = persist(a.deps.config, room)
      Actor(..a, content: Open(room))
    }
    _ -> a
  }
}

// ---- the log -------------------------------------------------------------------------------

fn system_line(body: String) -> Message {
  store.Message(
    id: 0,
    ts: "",
    kind: "system",
    from: None,
    to: None,
    reply_to: None,
    body:,
  )
}

// Appends without anyone to wake: for a room being created.
fn append_quiet(config: Config, room: Room, line: Message) -> Room {
  let line = store.Message(..line, id: room.count + 1, ts: clock.now())
  store.append(config.data_dir, room.state.id, line)
  let #(posts, bytes) = case line.kind {
    "message" -> #(room.posts + 1, room.bytes + string.byte_size(line.body))
    _ -> #(room.posts, room.bytes)
  }
  Room(
    ..room,
    messages: [line, ..room.messages],
    count: line.id,
    posts:,
    bytes:,
  )
}

// `wake: False` appends without releasing anyone waiting: for a line that is immediately
// followed by another, so both arrive in one response.
fn append(a: Actor, room: Room, line: Message, wake: Bool) -> Actor {
  let room = append_quiet(a.deps.config, room, line)
  case wake {
    False -> Actor(..a, content: Open(room))
    True -> {
      let #(woken, still) =
        list.partition(a.waiters, fn(w) {
          room.state.status != "open" || has_news(room, w.handle, w.query)
        })
      list.each(woken, answer(a.deps.config, room, _, a.deps))
      Actor(..a, content: Open(room), waiters: still)
    }
  }
}

// Every message is visible to everyone. `for_me` is a convenience filter, not privacy.
fn select(room: Room, handle: Option(String), q: Query) -> List(Message) {
  room.messages
  |> list.take_while(fn(m) { m.id > q.since })
  |> list.reverse
  |> list.filter(fn(m) {
    !q.for_me
    || case handle {
      Some(h) -> m.from != Some(h) && mentions(m, h)
      None -> False
    }
  })
}

// A reader's own posts are returned like any other message but never count as "something
// arrived" for a long-poll.
fn has_news(room: Room, handle: Option(String), q: Query) -> Bool {
  select(room, handle, q)
  |> list.any(fn(m) { m.from != handle || m.kind == "system" })
}

// Addressed to `h`, or `@h` in the text: after a start or a non-handle character, and not
// followed by one (a trailing `.` still counts, "thanks @bob."). ASCII case-insensitive.
fn mentions(m: Message, h: String) -> Bool {
  m.to == Some(h)
  || {
    let body = fields.ascii_lower(m.body)
    let needle = "@" <> fields.ascii_lower(h)
    let before_ok = fn(prefix) {
      case string.last(prefix) {
        Error(_) -> True
        Ok(c) -> !is_handle_grapheme(c)
      }
    }
    let after_ok = fn(rest) {
      case string.first(rest) {
        Error(_) -> True
        Ok(".") -> True
        Ok(c) -> !is_handle_grapheme(c)
      }
    }
    mention_at(body, needle, before_ok, after_ok, "")
  }
}

fn mention_at(body, needle, before_ok, after_ok, seen) -> Bool {
  case string.split_once(body, needle) {
    Error(_) -> False
    Ok(#(prefix, rest)) -> {
      let seen = seen <> prefix
      case before_ok(seen) && after_ok(rest) {
        True -> True
        False -> mention_at(rest, needle, before_ok, after_ok, seen <> needle)
      }
    }
  }
}

fn is_handle_grapheme(g: String) -> Bool {
  case string.to_utf_codepoints(g) {
    [cp, ..] -> fields.is_handle_char(string.utf_codepoint_to_int(cp))
    [] -> False
  }
}

fn reading(
  config: Config,
  room: Room,
  handle: Option(String),
  q: Query,
) -> Reading {
  let msgs = select(room, handle, q)
  let cursor = case q.for_me {
    True ->
      list.last(msgs) |> result.map(fn(m) { m.id }) |> result.unwrap(q.since)
    False -> int.max(q.since, room.count)
  }
  let present = list.count(room.state.participants, fn(p) { !p.left })
  Reading(
    messages: msgs,
    cursor:,
    status: room.state.status,
    present:,
    total: list.length(room.state.participants),
    left: capacity(config, room),
  )
}

// One maximum-size message is always held back: the host's last word, which only /close writes.
pub fn capacity(config: Config, room: Room) -> Capacity {
  Capacity(
    bytes: case config.max_room_bytes {
      0 -> None
      max -> Some(int.max(0, max - config.max_body - room.bytes))
    },
    messages: case config.max_messages {
      0 -> None
      max -> Some(int.max(0, max - 1 - room.posts))
    },
  )
}

// The log is public, so a token in a message would hand out a seat in the room. Every run of 32
// token characters is checked, as `/[A-Za-z0-9_-]{32}/g` finds them.
fn reject_tokens(room: Room, body: String) -> Result(Nil, HttpError) {
  let hashes = list.map(room.state.participants, fn(p) { p.token_hash })
  let found =
    candidates(string.to_utf_codepoints(body), [], [])
    |> list.any(fn(t) { list.contains(hashes, sha256(t)) })
  case found {
    True ->
      Error(fail.new(
        400,
        "message contains a room token",
        "Tokens are secrets and this log is public; never post them. Nothing was sent.",
      ))
    False -> Ok(Nil)
  }
}

fn candidates(cps, run: List(String), acc: List(String)) -> List(String) {
  let flush = fn() {
    case list.length(run) >= 32 {
      True -> list.append(acc, chunks(list.reverse(run)))
      False -> acc
    }
  }
  case cps {
    [] -> flush()
    [cp, ..rest] -> {
      let c = string.utf_codepoint_to_int(cp)
      let token_char = fields.is_handle_char(c) && c != 0x2E
      case token_char {
        True -> candidates(rest, [string.from_utf_codepoints([cp]), ..run], acc)
        False -> candidates(rest, [], flush())
      }
    }
  }
}

fn chunks(chars: List(String)) -> List(String) {
  case list.length(chars) >= 32 {
    True -> [
      string.concat(list.take(chars, 32)),
      ..chunks(list.drop(chars, 32))
    ]
    False -> []
  }
}

// ---- participants and tokens ---------------------------------------------------------------

pub fn by_handle(room: Room, handle: String) -> Result(Participant, Nil) {
  let wanted = string.lowercase(handle)
  list.find(room.state.participants, fn(p) {
    string.lowercase(p.handle) == wanted
  })
}

fn add_participant(
  config: Config,
  room: Room,
  wanted: String,
  role: String,
) -> #(Room, Joined) {
  let handle = free_handle(room, wanted, wanted, 2)
  let token = rand(24)
  // Only the hash is kept: a copy of the data directory does not hand out control of rooms.
  let p =
    store.Participant(
      handle:,
      role:,
      token_hash: sha256(token),
      joined_at: clock.now(),
      left: False,
    )
  case config.test_tokens {
    "" -> Nil
    file -> {
      let _ =
        simplifile.append(
          file,
          room.state.id <> " " <> handle <> " " <> token <> "\n",
        )
      Nil
    }
  }
  let state =
    store.State(
      ..room.state,
      participants: list.append(room.state.participants, [p]),
    )
  #(Room(..room, state:), Joined(handle:, token:))
}

fn free_handle(
  room: Room,
  wanted: String,
  candidate: String,
  n: Int,
) -> String {
  case by_handle(room, candidate) {
    Error(_) -> candidate
    Ok(_) -> free_handle(room, wanted, wanted <> "-" <> int.to_string(n), n + 1)
  }
}

fn set_left(room: Room, handle: String, left: Bool) -> Room {
  let participants =
    list.map(room.state.participants, fn(p) {
      case p.handle == handle {
        True -> store.Participant(..p, left:)
        False -> p
      }
    })
  Room(..room, state: store.State(..room.state, participants:))
}

// Authenticated requests are what keeps a room alive ("if you don't use it you lose it").
fn authenticate(
  room: Room,
  token: Option(String),
) -> #(Room, Option(Participant)) {
  let me = case token {
    None -> None
    Some(t) -> {
      let given = bit_array.from_string(sha256(t))
      list.find(room.state.participants, fn(p) {
        crypto.secure_compare(bit_array.from_string(p.token_hash), given)
      })
      |> option.from_result
    }
  }
  case me, room.state.status {
    Some(_), "open" -> #(touch(room), me)
    _, _ -> #(room, me)
  }
}

fn require(
  room: Room,
  token: Option(String),
  me: Option(Participant),
) -> Result(Participant, HttpError) {
  case me {
    Some(p) -> Ok(p)
    None ->
      Error(fail.new(
        401,
        case token {
          Some(_) -> "unknown token for this room"
          None -> "missing Authorization: Bearer TOKEN header"
        },
        "Join first: POST /r/"
          <> room.state.id
          <> "/join?handle=YOUR_NAME returns your token.",
      ))
  }
}

fn touch(room: Room) -> Room {
  Room(
    ..room,
    state: store.State(..room.state, last_activity: clock.now()),
    dirty: True,
  )
}

pub fn rand(bytes: Int) -> String {
  crypto.strong_random_bytes(bytes) |> bit_array.base64_url_encode(False)
}

pub fn sha256(s: String) -> String {
  crypto.hash(crypto.Sha256, bit_array.from_string(s))
  |> bit_array.base16_encode
  |> string.lowercase
}

// ---- limits, expiry, persistence -----------------------------------------------------------

fn rate_limit(a: Actor, handle: String) -> #(Actor, Result(Nil, HttpError)) {
  let limit = a.deps.config.rate_post
  case limit {
    0 -> #(a, Ok(Nil))
    _ -> {
      let now = clock.now_ms()
      let w = case dict.get(a.windows, handle) {
        Ok(w) if now <= w.reset -> w
        _ -> Window(count: 0, reset: now + 60_000)
      }
      let w = Window(..w, count: w.count + 1)
      let a = Actor(..a, windows: dict.insert(a.windows, handle, w))
      case w.count > limit {
        False -> #(a, Ok(Nil))
        True -> #(a, Error(too_many(limit, 60, w.reset - now, "messages")))
      }
    }
  }
}

pub fn too_many(
  limit: Int,
  window: Int,
  left_ms: Int,
  what: String,
) -> HttpError {
  let retry = { left_ms + 999 } / 1000
  fail.new(
    429,
    "too many " <> what,
    "Limit is "
      <> int.to_string(limit)
      <> " per "
      <> human_duration(window)
      <> ". Try again in "
      <> int.to_string(retry)
      <> " s.",
  )
  |> fail.with_headers([#("retry-after", int.to_string(retry))])
}

fn too_large(config: Config) -> HttpError {
  fail.new(
    413,
    "body too large",
    "Max " <> int.to_string(config.max_body) <> " bytes.",
  )
}

/// When the room is deleted: one clock. Open rooms: TTL after the last activity (rolling).
/// Closed rooms: TTL after the close (fixed).
pub fn delete_after(room: Room) -> String {
  case room.state.delete_after {
    Some(d) -> d
    None ->
      case clock.parse_iso(room.state.last_activity) {
        Ok(ms) -> clock.iso(ms + room.state.ttl * 1000)
        Error(_) -> room.state.last_activity
      }
  }
}

fn sweep(a: Actor, content: Content) -> actor.Next(Actor, Msg) {
  let config = a.deps.config
  let now = clock.now_ms()
  let windows = dict.filter(a.windows, fn(_, w) { now <= w.reset })
  let a = Actor(..a, windows:)
  let expired = fn(iso) {
    case clock.parse_iso(iso) {
      Ok(ms) -> now > ms
      Error(_) -> False
    }
  }
  // Operator takedown is `rm -r DATA_DIR/<room id>`; it takes effect here.
  case store.exists(config.data_dir, room_id(content)), content {
    False, Open(room) -> {
      let removed =
        Room(..room, state: store.State(..room.state, status: "removed"))
      list.each(a.waiters, answer(config, removed, _, a.deps))
      actor.stop()
    }
    False, Gone(_) -> actor.stop()
    True, Gone(t) ->
      case expired(t.delete_after) {
        True -> {
          store.remove(config.data_dir, t.id)
          actor.stop()
        }
        False -> actor.continue(a)
      }
    True, Open(room) -> {
      // A participant blocked in a long-poll is present, however long the poll lasts.
      let room = case
        room.state.status == "open"
        && list.any(a.waiters, fn(w) { option.is_some(w.handle) })
      {
        True -> touch(room)
        False -> room
      }
      case expired(delete_after(room)) {
        True -> {
          store.remove(config.data_dir, room.state.id)
          list.each(a.waiters, answer(config, room, _, a.deps))
          actor.stop()
        }
        False -> {
          let room = case room.dirty {
            True -> persist(config, room)
            False -> room
          }
          actor.continue(Actor(..a, content: Open(room)))
        }
      }
    }
  }
}

fn room_id(content: Content) -> String {
  case content {
    Open(room) -> room.state.id
    Gone(t) -> t.id
  }
}

fn persist(config: Config, room: Room) -> Room {
  store.save_state(config.data_dir, room.state)
  Room(..room, dirty: False)
}

fn guard(
  cond: Bool,
  error: fn() -> HttpError,
  next: fn() -> Result(a, HttpError),
) -> Result(a, HttpError) {
  case cond {
    True -> Error(error())
    False -> next()
  }
}

@external(erlang, "parlor_ffi", "is_draining")
pub fn is_draining() -> Bool
