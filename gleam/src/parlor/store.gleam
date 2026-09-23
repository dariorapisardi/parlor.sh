//// Storage: the filesystem, in exactly the original Node server's layout and formats, so data
//// directories survive a change of server (the conformance suite's handoff tier checks it).
////
////   DATA_DIR/<room id>/state.json      metadata, participants (token hashes only), last activity
////   DATA_DIR/<room id>/log.jsonl       append-only messages; this is what /logs serves
////   DATA_DIR/<room id>/tombstone.json  replaces both after a purge

import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile

pub type Message {
  Message(
    id: Int,
    ts: String,
    kind: String,
    from: Option(String),
    to: Option(String),
    reply_to: Option(Int),
    body: String,
  )
}

pub type Participant {
  Participant(
    handle: String,
    role: String,
    token_hash: String,
    joined_at: String,
    left: Bool,
  )
}

/// What state.json holds. `ttl` is stamped per room at creation; `delete_after` is set once the
/// room has ended.
pub type State {
  State(
    id: String,
    topic: String,
    status: String,
    created_at: String,
    last_activity: String,
    ttl: Int,
    ended_at: Option(String),
    participants: List(Participant),
    delete_after: Option(String),
  )
}

pub type Tombstone {
  Tombstone(
    id: String,
    purged_by: String,
    purged_at: String,
    created_at: String,
    messages_removed: Int,
    participants: Int,
    delete_after: String,
  )
}

pub type Loaded {
  /// `legacy`: state.json had no `ttl` of its own (a room from before the single TTL); it is
  /// written back in the current format at the next sweep.
  Live(state: State, messages: List(Message), legacy: Bool)
  Purged(Tombstone)
}

// ---- JSON, field for field and in the Node server's key order --------------------------------

pub fn message_json(m: Message) -> Json {
  json.object([
    #("id", json.int(m.id)),
    #("ts", json.string(m.ts)),
    #("kind", json.string(m.kind)),
    #("from", json.nullable(m.from, json.string)),
    #("to", json.nullable(m.to, json.string)),
    #("reply_to", json.nullable(m.reply_to, json.int)),
    #("body", json.string(m.body)),
  ])
}

fn participant_json(p: Participant) -> Json {
  json.object([
    #("handle", json.string(p.handle)),
    #("role", json.string(p.role)),
    #("token_hash", json.string(p.token_hash)),
    #("joined_at", json.string(p.joined_at)),
    #("left", json.bool(p.left)),
  ])
}

fn state_json(s: State) -> Json {
  let fields = [
    #("id", json.string(s.id)),
    #("topic", json.string(s.topic)),
    #("status", json.string(s.status)),
    #("created_at", json.string(s.created_at)),
    #("last_activity", json.string(s.last_activity)),
    #("ttl", json.int(s.ttl)),
    #("ended_at", json.nullable(s.ended_at, json.string)),
    #("participants", json.array(s.participants, participant_json)),
  ]
  json.object(case s.delete_after {
    Some(d) -> list.append(fields, [#("delete_after", json.string(d))])
    None -> fields
  })
}

pub fn tombstone_json(t: Tombstone) -> Json {
  json.object([
    #("id", json.string(t.id)),
    #("purged_by", json.string(t.purged_by)),
    #("purged_at", json.string(t.purged_at)),
    #("created_at", json.string(t.created_at)),
    #("messages_removed", json.int(t.messages_removed)),
    #("participants", json.int(t.participants)),
    #("delete_after", json.string(t.delete_after)),
  ])
}

pub fn message_decoder() -> Decoder(Message) {
  use id <- decode.field("id", decode.int)
  use ts <- decode.field("ts", decode.string)
  use kind <- decode.field("kind", decode.string)
  use from <- decode.optional_field(
    "from",
    None,
    decode.optional(decode.string),
  )
  use to <- decode.optional_field("to", None, decode.optional(decode.string))
  use reply_to <- decode.optional_field(
    "reply_to",
    None,
    decode.optional(decode.int),
  )
  use body <- decode.optional_field("body", "", decode.string)
  decode.success(Message(id:, ts:, kind:, from:, to:, reply_to:, body:))
}

fn participant_decoder() -> Decoder(Participant) {
  use handle <- decode.field("handle", decode.string)
  use role <- decode.field("role", decode.string)
  use token_hash <- decode.field("token_hash", decode.string)
  use joined_at <- decode.optional_field("joined_at", "", decode.string)
  use left <- decode.optional_field("left", False, decode.bool)
  decode.success(Participant(handle:, role:, token_hash:, joined_at:, left:))
}

/// Rooms from before the single TTL carried `retention` and `idle_timeout`; they keep their
/// longest promise (`default_ttl` is the server's TTL).
fn state_decoder(default_ttl: Int) -> Decoder(#(State, Bool)) {
  use id <- decode.field("id", decode.string)
  use topic <- decode.optional_field("topic", "", decode.string)
  use status <- decode.field("status", decode.string)
  use created_at <- decode.field("created_at", decode.string)
  use last_activity <- decode.field("last_activity", decode.string)
  use ttl <- decode.optional_field("ttl", None, decode.optional(decode.int))
  use retention <- decode.optional_field("retention", 0, decode.int)
  use idle <- decode.optional_field("idle_timeout", 0, decode.int)
  use ended_at <- decode.optional_field(
    "ended_at",
    None,
    decode.optional(decode.string),
  )
  use participants <- decode.field(
    "participants",
    decode.list(participant_decoder()),
  )
  use delete_after <- decode.optional_field(
    "delete_after",
    None,
    decode.optional(decode.string),
  )
  let legacy = ttl == None
  let ttl = case ttl {
    Some(t) -> t
    None -> int.max(retention, int.max(idle, default_ttl))
  }
  decode.success(#(
    State(
      id:,
      topic:,
      status:,
      created_at:,
      last_activity:,
      ttl:,
      ended_at:,
      participants:,
      delete_after:,
    ),
    legacy,
  ))
}

fn tombstone_decoder() -> Decoder(Tombstone) {
  use id <- decode.field("id", decode.string)
  use purged_by <- decode.field("purged_by", decode.string)
  use purged_at <- decode.field("purged_at", decode.string)
  use created_at <- decode.field("created_at", decode.string)
  use messages_removed <- decode.field("messages_removed", decode.int)
  use participants <- decode.field("participants", decode.int)
  use delete_after <- decode.field("delete_after", decode.string)
  decode.success(Tombstone(
    id:,
    purged_by:,
    purged_at:,
    created_at:,
    messages_removed:,
    participants:,
    delete_after:,
  ))
}

// ---- the filesystem --------------------------------------------------------------------------

fn file(dir: String, id: String, name: String) -> String {
  dir <> "/" <> id <> "/" <> name
}

pub fn list(dir: String) -> List(String) {
  let _ = simplifile.create_directory_all(dir)
  simplifile.read_directory(dir)
  |> result.unwrap([])
  |> list.filter(fn(id) {
    simplifile.is_directory(dir <> "/" <> id) |> result.unwrap(False)
  })
  |> list.sort(string.compare)
}

pub fn load(
  dir: String,
  id: String,
  default_ttl: Int,
) -> Result(Loaded, String) {
  let read = fn(name) { read_json(file(dir, id, name), name, _) }
  case simplifile.is_file(file(dir, id, "tombstone.json")) {
    Ok(True) ->
      read("tombstone.json")(tombstone_decoder()) |> result.map(Purged)
    _ -> {
      use #(state, legacy) <- result.try(read_json(
        file(dir, id, "state.json"),
        "state.json",
        state_decoder(default_ttl),
      ))
      let lines = case simplifile.read(file(dir, id, "log.jsonl")) {
        Ok(text) -> string.split(text, "\n") |> list.filter(fn(l) { l != "" })
        Error(_) -> []
      }
      use messages <- result.try(
        list.try_map(lines, fn(line) {
          json.parse(line, message_decoder())
          |> result.map_error(fn(e) { "log.jsonl: " <> string.inspect(e) })
        }),
      )
      Ok(Live(state, messages, legacy))
    }
  }
}

fn read_json(
  path: String,
  name: String,
  decoder: Decoder(a),
) -> Result(a, String) {
  use text <- result.try(
    simplifile.read(path) |> result.map_error(simplifile.describe_error),
  )
  json.parse(text, decoder)
  |> result.map_error(fn(e) { name <> ": " <> string.inspect(e) })
}

/// Written whole to a temporary file, then renamed over the old one: a crash never leaves half.
pub fn save_state(dir: String, state: State) -> Nil {
  let _ = simplifile.create_directory_all(dir <> "/" <> state.id)
  let path = file(dir, state.id, "state.json")
  let _ = simplifile.write(path <> ".tmp", json.to_string(state_json(state)))
  let _ = simplifile.rename(path <> ".tmp", path)
  Nil
}

pub fn append(dir: String, id: String, message: Message) -> Nil {
  let line = json.to_string(message_json(message)) <> "\n"
  let _ = simplifile.append(file(dir, id, "log.jsonl"), line)
  Nil
}

pub fn purge(dir: String, id: String, tombstone: Tombstone) -> Nil {
  let _ =
    simplifile.write(
      file(dir, id, "tombstone.json"),
      json.to_string(tombstone_json(tombstone)),
    )
  let _ = simplifile.delete_file(file(dir, id, "log.jsonl"))
  let _ = simplifile.delete_file(file(dir, id, "state.json"))
  Nil
}

pub fn remove(dir: String, id: String) -> Nil {
  let _ = simplifile.delete(dir <> "/" <> id)
  Nil
}

pub fn exists(dir: String, id: String) -> Bool {
  simplifile.is_directory(dir <> "/" <> id) |> result.unwrap(False)
}
