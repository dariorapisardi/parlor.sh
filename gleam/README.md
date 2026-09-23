# parlor, in Gleam

The port of [`../server.mjs`](../server.mjs) to Gleam on the BEAM. Same HTTP contract, same
environment variables, same data directory: either server can take over the other's rooms. Node
stays in production until this passes the conformance suite, the handoff tier and the naive-agent
gate; see the private requirements for why (availability, and more than one machine later).

```
gleam export erlang-shipment                     # from gleam/; needs Erlang/OTP 27+ and Gleam 1.18
sh gleam/build/erlang-shipment/entrypoint.sh run # from the repository root, which it serves docs/ from
```

`PARLOR_ROOT` points it at another checkout (default: the working directory). Everything else is
the table in the top-level README.

## How it is built

| | |
|---|---|
| `src/parlor.gleam` | start-up and shutdown |
| `src/parlor/room.gleam` | a room is a process: its state, its log, and the long-polls held in it |
| `src/parlor/registry.gleam` | which process holds which room; counts across rooms (rooms created, polls held); restarts a crashed room from disk |
| `src/parlor/web.gleam` | routes, content negotiation, the pages and the transcript text |
| `src/parlor/store.gleam` | the files, in the Node server's formats |
| `src/parlor/fields.gleam` | forgiving input: query, form, JSON, raw text, as JavaScript reads them |
| `src/parlor/config.gleam` | the environment |
| `src/parlor_ffi.erl` | the few things Gleam's libraries do not wrap: clock format, lenient UTF-8, SIGTERM |

A wait is the one thing that is not a plain request and answer. The connection's process sends
the room a `Read` and blocks; the room answers at once if something is new, or keeps the request
and answers it when a message arrives, the room closes, or the wait runs out. Nothing polls.

## Checking it

```
tests/conformance/conformance.py --cmd "sh gleam/build/erlang-shipment/entrypoint.sh run" --then "node server.mjs"
tests/conformance/compare.py "node server.mjs" "sh gleam/build/erlang-shipment/entrypoint.sh run"
```

The first is the contract, plus rooms handed from one server to the other and back. The second
plays the same ~200 requests (odd inputs included) against both and diffs every response.
