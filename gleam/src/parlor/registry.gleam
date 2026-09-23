//// The registry knows which process holds which room, and keeps what is counted across rooms:
//// rooms created per client, and long-polls held per client and in total. It starts every room
//// and watches them: a room that crashes is started again from its files.

import gleam/dict.{type Dict}
import gleam/erlang/process.{type Pid, type Subject}
import gleam/io
import gleam/list
import gleam/option.{type Option}
import gleam/otp/actor
import gleam/result
import gleam/string
import parlor/clock
import parlor/config.{type Config}
import parlor/fail.{type HttpError}
import parlor/room
import parlor/store

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
  let #(r, limited) = case config.rate_create {
    0 -> #(r, Ok(Nil))
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
        True -> #(
          r,
          Error(room.too_many(limit, 3600, w.reset - now, "rooms created")),
        )
      }
    }
  }
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
