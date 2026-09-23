# Prior art and neighbours

Living list. Last checked 2026-09-16, from public pages and READMEs only; nothing here
was tried hands-on yet. "Guest needs" = what the *other* side must have before it can talk.

| Service | What it is | Guest needs | Rooms | Can the operator read messages? | Notes |
|---|---|---|---|---|---|
| [Tincan (gotincan.com)](https://gotincan.com/) · [plugin repo](https://github.com/tincan-ai/tincan-plugin) | Hosted rooms + channels for coding agents, history search, files, private "scrapbook" per agent | MCP server / plugin / CLI bridge | Persistent | **Optional E2EE workspaces**: "Keys stay on the device running your agent. Tincan stores encrypted messages and files without the keys to read them." Standard workspaces: encryption at rest only. Operator still sees channel names, membership, timing, sizes | Free tier without signup (100 msgs/day), Google login for more. Repo created 2026-09-10 |
| [tincan (sethgholson.com)](https://tincan.sethgholson.com/) | "Two cans and a string, for AI agents": ephemeral room between agent sessions on different machines | A `tincan` CLI is referenced; HTTP POST/GET + WebSocket | Ephemeral, TTL 1 h default / 8 h max, 8 peers, 500 msgs | Nothing said about encryption: assume yes | Closest to ours in spirit. **Credential lives in the URL fragment** ("the part after # is the credential"). Agent-facing prompt warns: `from` is self-reported, don't relay what your human didn't authorize |
| [rockerritesh/tincan](https://github.com/rockerritesh/tincan) | "A private line between your agent and your friend's agent" | Clone + npm install + MCP registration, invite code | Persistent append-only log | **Yes, by design**: "The broker stores plaintext and can read it; the threat model is other agents and a leaked URL, not the machine you own." | Self-hosted broker behind a Cloudflare tunnel. Ed25519 identity per agent, signed requests, out-of-band fingerprint check (`verify_peer`) |
| [Agent Room](https://www.agent-room.com/mcp) · [repo](https://github.com/ebin198351-akl/agent-room) | Rooms for Claude Code, Cursor, Codex, Gemini: tags like [DECISION]/[TODO], task board, presence; mentions PR handoff | MCP one-liner + 9-character room code, no accounts | 24 h TTL; export makes a permanent report | Nothing said about encryption: assume yes (Vercel + Upstash Redis) | MIT, self-hostable |
| [agent-broadcast-mcp](https://github.com/andrzejdus/agent-broadcast-mcp) | One global broadcast room, nick in the URL, no accounts | MCP | Single shared room | Not checked | |
| [council-hub](https://github.com/iksnerd/council-hub) | Self-hosted MCP server: shared rooms, persistent transcripts, semantic search, "done" signal | MCP | Persistent | Self-hosted | Same-owner fleets rather than cross-org |
| [agent-roundtable](https://github.com/ylove/agent-roundtable) | MCP server to convene meetings between personas on different model providers | MCP | Per meeting | Not checked | Orchestrates models, not independent parties |
| [agentchattr](https://github.com/bcurts/agentchattr) | Local chat where coding agents tag each other and the human | Local install | Local | Local only | Not cross-machine |
| `c0ze/tincan` | "A message passing utility for coding agents" | Not checked | Not checked | Not checked | Pushed 2026-09-08 |

Protocol-level neighbours (not products to join): A2A (Linux Foundation; long-lived addressable agent services),
MCP (agent-to-tool), mcp_agent_mail / AgentMail (mailboxes, mostly single-owner), Claude Code SendMessage
(same account only). Ephemeral-pipe ancestors: magic-wormhole, patchbay.pub, ntfy, tmate.

## Where ours differs (to be verified hands-on)

- Guest needs nothing: the URL describes itself and `curl` is enough. Every product above except
  possibly sethgholson's needs an MCP server, plugin or CLI on the guest side.
- Built for meeting *another party's* agent once, not for coordinating your own fleet.
- Trust stance: the room certifies handle continuity only; identity is the participants' business.
- Tested with naive agents across vendors (see tests/TESTLOG.md).

## Privacy landscape

Gotincan.com and parlor's optional two-party overlay offer end-to-end encryption through client
software. Nobody offers E2EE to a zero-install guest: cryptography needs trusted code on both
endpoints. rockerritesh/tincan narrows operator trust by self-hosting; the rest do not mention it.
