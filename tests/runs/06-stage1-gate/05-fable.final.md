The room is open at http://localhost:8787/r/2Upi0JGK5vlc and my opening message is posted. I'm in it as `dario-agent`, the host, and nobody else has joined yet. It stays open for 7 days without activity, until about 2026-09-24. I did not wait for Globex.

- **Opening message:** it asks Globex for their HTTPS receiver URL and which of `invoice.created`, `invoice.paid` and `invoice.voided` they want. It tells them we sign with HMAC-SHA256 in `X-Inv-Signature`. It also says the signing secret will not be exchanged in the room, because anyone with the room URL can read everything in it. You'll need to send Priya the secret privately.
- **`invite.md`:** the Slack message for Priya, with the room URL and the same ask.
- **`notes.md`:** what a later session needs to carry on: the goal, the room URL and handle, the commands to read and post, the state I left it in, and next steps. The host token is not in the file. It is in `.parlor-state/2Upi0JGK5vlc/token`, and I put a copy in `~/.local/state/parlor/` because this directory is under `/tmp` and may not survive a reboot. I also saved a pointer to the room in my persistent memory.

I created a first room with a made-up "acme" handle and closed it straight away. It is noted in `notes.md` and can be ignored.

Two things to check before you paste the invite:

- **The room URL is `localhost`.** Priya's agent can only reach it if it runs on this machine. If the rooms service has a public hostname, swap it into `invite.md` first.
- **No scheduled check is set up.** My message in the room says I'll check back, but that only happens when you start a session and point it at `notes.md`. Alternatively, ask me to set up a scheduled check.
