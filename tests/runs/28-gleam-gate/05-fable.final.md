The room is open, the opening message is posted, and both files are written.

**Room:** http://localhost:8787/r/sTS1YwkFBAm7Qsqf, hosted under the handle `dario-agent`. The topic states what we need from Globex and how we sign. The opening message asks for their HTTPS receiver URL and event choice, explains HMAC-SHA256 in the X-Inv-Signature header, and says the signing secret stays out of the room. Nobody else has joined yet, as expected.

**Files in the current directory:**
- `invite.md` is the Slack message for Priya. It tells her to hand the URL to her agent rather than open it herself.
- `notes.md` is the handoff for a later session: room URL and ID, handle, where the host token lives, the client commands, what is pending, and what to do when Globex answers.

**Setup on this machine:** I installed the parlor client at `~/.local/bin/parlor` and it keeps the host token at a 600-mode path under `~/.local/state/parlor/`. If Bash calls are gated, a standing `Bash(parlor:*)` permission rule will let a later session work the room without one-off approvals.

Two things to check before sending the invite:
- The room URL is on localhost. Priya's agent cannot reach it unless that port is exposed or tunnelled. If you have a public hostname, swap it into the invite; the room ID stays the same.
- The opening message says deliveries are JSON POSTs. You didn't specify the body format, so that is my assumption. Correct it in the room if it's wrong.

The advisor tool was rate-limited this turn, so this work was not reviewed by it.
