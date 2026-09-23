//// parlor: rooms where agents talk to each other. The contract is tests/conformance/; why it is
//// the way it is: docs/DESIGN.md. It began as a port of a Node server (server.mjs, in git history
//// until 2026-09-23), whose data directory, variables and pages it keeps unchanged.

import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/otp/actor
import gleam/string
import mist
import parlor/config
import parlor/registry
import parlor/web

pub fn main() -> Nil {
  let config = config.from_env()
  let docs = case web.load_docs(config) {
    Ok(docs) -> docs
    Error(e) -> {
      io.println_error(
        "cannot read the pages in " <> config.root <> "/docs: " <> e,
      )
      halt(1)
      panic
    }
  }
  web.store_docs(docs)
  let assert Ok(rooms) = registry.start(config)
  let loaded = actor.call(rooms, 600_000, registry.LoadAll)
  // Deletes what expired while we were down, then again every SWEEP_EVERY seconds.
  process.send(rooms, registry.Sweep)

  let local =
    string.starts_with(config.host, "127.")
    || config.host == "::1"
    || config.host == "localhost"
  case config.public_url, local {
    "", False ->
      io.println_error(
        "PUBLIC_URL is not set: links will be built from each request's Host header. Set PUBLIC_URL for any deployment others can reach.",
      )
    _, _ -> Nil
  }

  let assert Ok(_) =
    mist.new(web.handler(web.Web(config:, registry: rooms)))
    |> mist.bind(config.host)
    |> mist.port(config.port)
    |> mist.after_start(fn(port, _, _) {
      small_receive_buffers(port)
      io.println(
        "parlor listening on :"
        <> int.to_string(port)
        <> ", "
        <> int.to_string(loaded)
        <> " rooms loaded from "
        <> config.data_dir,
      )
    })
    |> mist.start

  // On shutdown, answer every held long-poll (an empty read) before exiting, so a restart looks
  // like a quiet poll to clients instead of a proxy error. We keep listening through the grace
  // window, and draining answers each arrival at once: a closed port would refuse it.
  on_sigterm(fn() {
    process.spawn_unlinked(fn() {
      set_draining()
      actor.call(rooms, 5000, registry.Drain)
      process.sleep(config.drain_grace_ms)
      halt(0)
    })
    Nil
  })
  process.sleep_forever()
}

@external(erlang, "parlor_ffi", "on_sigterm")
fn on_sigterm(handler: fn() -> Nil) -> Nil

@external(erlang, "parlor_ffi", "set_draining")
fn set_draining() -> Nil

@external(erlang, "parlor_ffi", "small_receive_buffers")
fn small_receive_buffers(port: Int) -> Nil

@external(erlang, "parlor_ffi", "halt")
fn halt(code: Int) -> Nil
