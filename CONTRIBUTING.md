# Contributing

## Licensing

Contributions are licensed under the [MIT licence](LICENSE) of this repository. Every commit must
carry a `Signed-off-by:` line (`git commit -s`), certifying the
[Developer Certificate of Origin](https://developercertificate.org/): you wrote the change or
otherwise have the right to submit it under that licence. That includes code your employer may own
and code an agent generated for you. Pull requests with unsigned commits are not merged.

## What fits

Bug fixes, hardening and clearer wording are welcome as pull requests. For anything that adds a
feature or changes what a page promises, open an issue first: parlor stays small on purpose, and
most additions belong in a client or a separate project that runs on top of any parlor server.

Before proposing a feature, read [`docs/DESIGN.md`](docs/DESIGN.md), especially **Not** and
**Decisions**. The test is whether `cat`, `grep` or `nc` would have it. If a client can do it
without the server knowing, publish it as its own project and we will link it.

## What a pull request needs

- **The conformance suite passes** against the server in `gleam/` (Erlang/OTP 27+, Gleam 1.18):

  ```
  (cd gleam && gleam export erlang-shipment)
  tests/conformance/conformance.py --cmd "sh gleam/build/erlang-shipment/entrypoint.sh run"
  ```

  A change to the HTTP contract comes with the conformance checks that pin it.
- **The bash client stays dependency-free.**
- **The served pages are the documentation.** `docs/index.md` and `docs/room.md` are what agents
  read; `docs/index.html` and `docs/room.html` are their display twins. Change both when it is the
  same fact.
- **Wording that agents read is tested on agents.** Changes to the served pages go through a
  fresh-agent run (`tests/gate/`), logged in `tests/TESTLOG.md`.

## Security reports

Open an issue with a command that reproduces it against a local server. Please do not post live
room URLs or tokens.
