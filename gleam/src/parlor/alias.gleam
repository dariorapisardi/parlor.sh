//// Aliases: a stable URL that points at one room of this server and can be pointed at another.
//// Whoever holds the alias token moves it; nobody else can. The registry keeps them all in memory
//// (they are a few hundred bytes each) and on disk, one file per alias:
////
////   DATA_DIR/aliases/<alias id>.json   target room, token hash, TTL, when the target went away
////
//// One clock, as for rooms: an alias lives while its room exists, and is deleted its TTL after
//// the room is gone unless it is pointed at another room first. Nobody has to keep it alive.

import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import simplifile

pub type Alias {
  Alias(
    id: String,
    room: String,
    token_hash: String,
    created_at: String,
    updated_at: String,
    ttl: Int,
    /// When the sweep first found the target room gone; None while it exists.
    orphaned_at: Option(String),
  )
}

/// The directory under DATA_DIR. Never a room id: those are 16 characters from rand().
pub const dir_name = "aliases"

fn dir(data_dir: String) -> String {
  data_dir <> "/" <> dir_name
}

fn to_json(a: Alias) -> String {
  json.object([
    #("id", json.string(a.id)),
    #("room", json.string(a.room)),
    #("token_hash", json.string(a.token_hash)),
    #("created_at", json.string(a.created_at)),
    #("updated_at", json.string(a.updated_at)),
    #("ttl", json.int(a.ttl)),
    #("orphaned_at", json.nullable(a.orphaned_at, json.string)),
  ])
  |> json.to_string
}

fn decoder() -> decode.Decoder(Alias) {
  use id <- decode.field("id", decode.string)
  use room <- decode.field("room", decode.string)
  use token_hash <- decode.field("token_hash", decode.string)
  use created_at <- decode.field("created_at", decode.string)
  use updated_at <- decode.field("updated_at", decode.string)
  use ttl <- decode.field("ttl", decode.int)
  use orphaned_at <- decode.field("orphaned_at", decode.optional(decode.string))
  decode.success(Alias(
    id:,
    room:,
    token_hash:,
    created_at:,
    updated_at:,
    ttl:,
    orphaned_at:,
  ))
}

/// Every alias on disk; an unreadable file is reported and skipped.
pub fn load_all(data_dir: String) -> #(List(Alias), List(String)) {
  simplifile.read_directory(dir(data_dir))
  |> result.unwrap([])
  |> list.filter(string.ends_with(_, ".json"))
  |> list.sort(string.compare)
  |> list.fold(#([], []), fn(acc, name) {
    let path = dir(data_dir) <> "/" <> name
    let parsed =
      simplifile.read(path)
      |> result.map_error(simplifile.describe_error)
      |> result.try(fn(text) {
        json.parse(text, decoder())
        |> result.map_error(string.inspect)
      })
    case parsed {
      Ok(a) -> #([a, ..acc.0], acc.1)
      Error(e) -> #(acc.0, [name <> ": " <> e, ..acc.1])
    }
  })
}

/// Written whole to a temporary file, then renamed over the old one.
pub fn save(data_dir: String, a: Alias) -> Nil {
  let _ = simplifile.create_directory_all(dir(data_dir))
  let path = dir(data_dir) <> "/" <> a.id <> ".json"
  let _ = simplifile.write(path <> ".tmp", to_json(a))
  let _ = simplifile.rename(path <> ".tmp", path)
  Nil
}

pub fn remove(data_dir: String, id: String) -> Nil {
  let _ = simplifile.delete(dir(data_dir) <> "/" <> id <> ".json")
  Nil
}

/// The room id in what an agent sends as `room`: the room URL (any page of it), a path, or the
/// bare id. Only the id is kept; whether it is a room of this server is the registry's question.
pub fn room_id(given: String) -> String {
  let given = string.trim(given)
  let after = case string.split(given, "/r/") |> list.last {
    Ok(rest) -> rest
    Error(_) -> given
  }
  case string.split(after, "/") {
    [id, ..] -> id
    [] -> after
  }
  |> string.split("?")
  |> list.first
  |> result.unwrap("")
  |> string.split("#")
  |> list.first
  |> result.unwrap("")
}
