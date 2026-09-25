//// The registry knows which process holds which room, and keeps what is counted across rooms:
//// rooms created per client, and long-polls held per client and in total. It starts every room
//// and watches them: a room that crashes is started again from its files. It also holds the
//// aliases, since what an alias needs to know is whether its room still exists.

import gleam/bit_array
import gleam/crypto
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Pid, type Subject}
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import gleam/string
import parlor/alias.{type Alias}
import parlor/clock
import parlor/config.{type Config}
import parlor/fail.{type HttpError}
import parlor/room
import parlor/store
import simplifile

pub type Msg {
  Lookup(id: String, reply: Subject(Option(Subject(room.Msg))))
  /// Before a create reads its body: RATE_CREATE, then MAX_ROOMS.
  MayCreate(client: String, reply: Subject(Result(Nil, HttpError)))
  Create(
    topic: String,
    ttl: Int,
    host: String,
    reply: Subject(Result(#(String, room.Joined), HttpError)),
  )
  /// A new alias for `room` (an id); answers the alias id and its token.
  AliasCreate(
    client: String,
    room: String,
    reply: Subject(Result(#(String, String), HttpError)),
  )
  /// Where an alias points, and whether that room still exists.
  AliasGet(id: String, reply: Subject(Option(#(String, Bool))))
  AliasSet(
    id: String,
    token: Option(String),
    room: String,
    reply: Subject(Result(Nil, HttpError)),
  )
  AliasDelete(
    id: String,
    token: Option(String),
    reply: Subject(Result(Nil, HttpError)),
  )
  TryHold(client: String, reply: Subject(Bool))
  Release(client: String)
  LoadAll(reply: Subject(Int))
  Sweep
  Drain(reply: Subject(Nil))
  Exited(process.ExitMessage)
}

type Window {
  Window(count: Int, reset: Int)
}

type Registry {
  Registry(
    config: Config,
    self: Subject(Msg),
    rooms: Dict(String, Subject(room.Msg)),
    pids: Dict(Pid, String),
    windows: Dict(String, Window),
    waiting: Dict(String, Int),
    waiting_total: Int,
    aliases: Dict(String, Alias),
  )
}

pub fn start(config: Config) -> Result(Subject(Msg), actor.StartError) {
  actor.new_with_initialiser(5000, fn(self) {
    process.trap_exits(True)
    let selector =
      process.new_selector()
      |> process.select(self)
      |> process.select_trapped_exits(Exited)
    Registry(
      config:,
      self:,
      rooms: dict.new(),
      pids: dict.new(),
      windows: dict.new(),
      waiting: dict.new(),
      waiting_total: 0,
      aliases: dict.new(),
    )
    |> actor.initialised
    |> actor.selecting(selector)
    |> actor.returning(self)
    |> Ok
  })
  |> actor.on_message(handle)
  |> actor.start
  |> result.map(fn(started) { started.data })
}

fn deps(r: Registry) -> room.Deps {
  let registry = r.self
  room.Deps(
    config: r.config,
    try_hold: fn(client) { actor.call(registry, 5000, TryHold(client, _)) },
    release: fn(client) { process.send(registry, Release(client)) },
  )
}

fn handle(r: Registry, msg: Msg) -> actor.Next(Registry, Msg) {
  case msg {
    Lookup(id, reply) -> {
      process.send(reply, dict.get(r.rooms, id) |> option.from_result)
      actor.continue(r)
    }

    MayCreate(client, reply) -> {
      let #(r, result) = may_create(r, client)
      process.send(reply, result)
      actor.continue(r)
    }

    AliasCreate(client, room, reply) -> {
      // A room that does not exist is refused before it counts against RATE_CREATE.
      let #(r, allowed) = case target_exists(r, room) {
        Error(e) -> #(r, Error(e))
        Ok(Nil) -> rate_create(r, client, "aliases created")
      }
      let full =
        r.config.max_aliases > 0 && dict.size(r.aliases) >= r.config.max_aliases
      let result = case allowed, full {
        Error(e), _ -> Error(e)
        Ok(_), True ->
          Error(fail.new(
            503,
            "no room for more aliases",
            "This server is at its alias limit. Try later.",
          ))
        Ok(_), False -> Ok(Nil)
      }
      case result {
        Error(e) -> {
          process.send(reply, Error(e))
          actor.continue(r)
        }
        Ok(Nil) -> {
          let id = new_alias_id(r)
          let token = room.rand(24)
          let now = clock.now()
          let a =
            alias.Alias(
              id:,
              room:,
              token_hash: room.sha256(token),
              created_at: now,
              updated_at: now,
              ttl: r.config.ttl,
              orphaned_at: None,
            )
          alias.save(r.config.data_dir, a)
          record_test_token(r.config, id, token)
          process.send(reply, Ok(#(id, token)))
          actor.continue(Registry(..r, aliases: dict.insert(r.aliases, id, a)))
        }
      }
    }

    AliasGet(id, reply) -> {
      process.send(
        reply,
        dict.get(r.aliases, id)
          |> option.from_result
          |> option.map(fn(a) { #(a.room, dict.has_key(r.rooms, a.room)) }),
      )
      actor.continue(r)
    }

    AliasSet(id, token, room, reply) -> {
      let result = {
        use a <- result.try(alias_owned(r, id, token))
        use Nil <- result.try(target_exists(r, room))
        Ok(alias.Alias(..a, room:, updated_at: clock.now(), orphaned_at: None))
      }
      case result {
        Error(e) -> {
          process.send(reply, Error(e))
          actor.continue(r)
        }
        Ok(a) -> {
          alias.save(r.config.data_dir, a)
          process.send(reply, Ok(Nil))
          actor.continue(Registry(..r, aliases: dict.insert(r.aliases, id, a)))
        }
      }
    }

    AliasDelete(id, token, reply) ->
      case alias_owned(r, id, token) {
        Error(e) -> {
          process.send(reply, Error(e))
          actor.continue(r)
        }
        Ok(_) -> {
          alias.remove(r.config.data_dir, id)
          process.send(reply, Ok(Nil))
          actor.continue(Registry(..r, aliases: dict.delete(r.aliases, id)))
        }
      }

    Create(topic, ttl, host, reply) -> {
      // 96 bits: unlisted rooms must be unguessable, and a longer URL costs nothing.
      let id = new_id(r)
      case room.create(deps(r), id, topic, ttl, host) {
        Ok(#(subject, pid, me)) -> {
          process.send(reply, Ok(#(id, me)))
          actor.continue(add(r, id, subject, pid))
        }
        Error(e) -> {
          process.send(reply, Error(fail.bare(500, "internal error")))
          io.println_error(
            "could not start room " <> id <> ": " <> string.inspect(e),
          )
          actor.continue(r)
        }
      }
    }

    TryHold(client, reply) -> {
      let mine = dict.get(r.waiting, client) |> result.unwrap(0)
      let config = r.config
      let over =
        { config.max_waiters > 0 && r.waiting_total >= config.max_waiters }
        || mine >= config.max_waiters_per_client
      process.send(reply, !over)
      case over {
        True -> actor.continue(r)
        False ->
          actor.continue(
            Registry(
              ..r,
              waiting: dict.insert(r.waiting, client, mine + 1),
              waiting_total: r.waiting_total + 1,
            ),
          )
      }
    }

    Release(client) -> {
      let mine = dict.get(r.waiting, client) |> result.unwrap(0)
      actor.continue(
        Registry(
          ..r,
          waiting: dict.insert(r.waiting, client, mine - 1),
          waiting_total: r.waiting_total - 1,
        ),
      )
    }

    LoadAll(reply) -> {
      let r =
        list.fold(store.list(r.config.data_dir), r, fn(r, id) { load(r, id) })
      let #(aliases, errors) = alias.load_all(r.config.data_dir)
      list.each(errors, fn(e) {
        io.println_error("skipping unreadable alias " <> e)
      })
      let r =
        Registry(
          ..r,
          aliases: list.fold(aliases, dict.new(), fn(d, a) {
            dict.insert(d, a.id, a)
          }),
        )
      process.send(reply, dict.size(r.rooms))
      actor.continue(r)
    }

    Sweep -> {
      let now = clock.now_ms()
      let r =
        Registry(
          ..r,
          windows: dict.filter(r.windows, fn(_, w) { now <= w.reset }),
          waiting: dict.filter(r.waiting, fn(_, n) { n > 0 }),
        )
      let r = sweep_aliases(r, now)
      dict.each(r.rooms, fn(_, subject) { process.send(subject, room.Sweep) })
      process.send_after(r.self, r.config.sweep_every * 1000, Sweep)
      actor.continue(r)
    }

    Drain(reply) -> {
      dict.each(r.rooms, fn(_, subject) { process.send(subject, room.Drain) })
      process.send(reply, Nil)
      actor.continue(r)
    }

    Exited(process.ExitMessage(pid, reason)) ->
      case dict.get(r.pids, pid) {
        // A room that failed to start (already reported), or no room at all.
        Error(_) -> actor.continue(r)
        Ok(id) -> {
          let r =
            Registry(
              ..r,
              rooms: dict.delete(r.rooms, id),
              pids: dict.delete(r.pids, pid),
            )
          case reason {
            process.Normal -> actor.continue(r)
            _ -> {
              // A crash loses only what was in the room's memory and not yet on disk.
              io.println_error(
                "room "
                <> id
                <> " crashed, restarting from disk: "
                <> string.inspect(reason),
              )
              case store.exists(r.config.data_dir, id) {
                True -> actor.continue(load(r, id))
                False -> actor.continue(r)
              }
            }
          }
        }
      }
  }
}

fn may_create(
  r: Registry,
  client: String,
) -> #(Registry, Result(Nil, HttpError)) {
  let config = r.config
  let #(r, limited) = rate_create(r, client, "rooms created")
  let full = config.max_rooms > 0 && dict.size(r.rooms) >= config.max_rooms
  case limited, full {
    Error(e), _ -> #(r, Error(e))
    Ok(_), True -> #(
      r,
      Error(fail.new(
        503,
        "no room for more rooms",
        "This server is at its room limit. Try later.",
      )),
    )
    Ok(_), False -> #(r, Ok(Nil))
  }
}

// RATE_CREATE counts rooms and aliases together: both are things a client makes the server keep.
fn rate_create(
  r: Registry,
  client: String,
  what: String,
) -> #(Registry, Result(Nil, HttpError)) {
  let exempt = list.contains(r.config.rate_create_exempt, client)
  case r.config.rate_create {
    0 -> #(r, Ok(Nil))
    _ if exempt -> #(r, Ok(Nil))
    limit -> {
      let now = clock.now_ms()
      let w = case dict.get(r.windows, client) {
        Ok(w) if now <= w.reset -> w
        _ -> Window(count: 0, reset: now + 3_600_000)
      }
      let w = Window(..w, count: w.count + 1)
      let r = Registry(..r, windows: dict.insert(r.windows, client, w))
      case w.count > limit {
        False -> #(r, Ok(Nil))
        True -> #(r, Error(room.too_many(limit, 3600, w.reset - now, what)))
      }
    }
  }
}

// An alias only ever points at a room this server holds: never at a URL, so never elsewhere.
fn target_exists(r: Registry, room: String) -> Result(Nil, HttpError) {
  case dict.has_key(r.rooms, room) {
    True -> Ok(Nil)
    False ->
      Error(fail.new(
        400,
        "no such room on this server",
        "Send `room` as the URL of a room that exists here (POST / creates one). An alias points only at rooms of the server it is on.",
      ))
  }
}

fn alias_owned(
  r: Registry,
  id: String,
  token: Option(String),
) -> Result(Alias, HttpError) {
  use a <- result.try(
    dict.get(r.aliases, id)
    |> result.replace_error(fail.bare(404, "no such alias")),
  )
  let given = case token {
    Some(t) -> bit_array.from_string(room.sha256(t))
    None -> <<>>
  }
  case crypto.secure_compare(bit_array.from_string(a.token_hash), given) {
    True -> Ok(a)
    False ->
      Error(fail.new(
        401,
        case token {
          Some(_) -> "unknown token for this alias"
          None -> "missing Authorization: Bearer TOKEN header"
        },
        "Only the token returned when the alias was created can change it. A lost alias token cannot be recovered: make a new alias.",
      ))
  }
}

// An alias whose room is gone is marked, and deleted its TTL after that: one clock.
fn sweep_aliases(r: Registry, now_ms: Int) -> Registry {
  let aliases =
    dict.fold(r.aliases, r.aliases, fn(acc, id, a) {
      case dict.has_key(r.rooms, a.room), a.orphaned_at {
        True, None -> acc
        True, Some(_) -> {
          let a = alias.Alias(..a, orphaned_at: None)
          alias.save(r.config.data_dir, a)
          dict.insert(acc, id, a)
        }
        False, None -> {
          let a = alias.Alias(..a, orphaned_at: Some(clock.now()))
          alias.save(r.config.data_dir, a)
          dict.insert(acc, id, a)
        }
        False, Some(since) -> {
          let since = clock.parse_iso(since) |> result.unwrap(0)
          case now_ms >= since + a.ttl * 1000 {
            False -> acc
            True -> {
              alias.remove(r.config.data_dir, id)
              dict.delete(acc, id)
            }
          }
        }
      }
    })
  Registry(..r, aliases:)
}

fn record_test_token(config: Config, id: String, token: String) -> Nil {
  case config.test_tokens {
    "" -> Nil
    file -> {
      let _ = simplifile.append(file, id <> " alias " <> token <> "\n")
      Nil
    }
  }
}

fn new_alias_id(r: Registry) -> String {
  let id = room.rand(12)
  case dict.has_key(r.aliases, id) || dict.has_key(r.rooms, id) {
    True -> new_alias_id(r)
    False -> id
  }
}

fn load(r: Registry, id: String) -> Registry {
  case room.load(deps(r), id) {
    Ok(#(subject, pid, Nil)) -> add(r, id, subject, pid)
    Error(e) -> {
      io.println_error("skipping unreadable room " <> id <> ": " <> describe(e))
      r
    }
  }
}

fn describe(e: actor.StartError) -> String {
  case e {
    actor.InitFailed(reason) -> reason
    other -> string.inspect(other)
  }
}

fn add(
  r: Registry,
  id: String,
  subject: Subject(room.Msg),
  pid: Pid,
) -> Registry {
  Registry(
    ..r,
    rooms: dict.insert(r.rooms, id, subject),
    pids: dict.insert(r.pids, pid, id),
  )
}

fn new_id(r: Registry) -> String {
  let id = room.rand(12)
  case dict.has_key(r.rooms, id) {
    True -> new_id(r)
    False -> id
  }
}
