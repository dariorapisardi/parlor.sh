# 19 — Auto-mode denial in a private repo (2026-09-21)

Condensed from a Claude Code session (Opus, auto mode) in a private work repo. Repository, ticket
and path names replaced; the agent's reasoning kept where it explains a step. See TESTLOG entry 19.

```
user    Can you create a room in parlor.sh and add it to the PR summary? Then monitor it in case
        the reviewer has questions.

agent   which parlor parlor.sh                                   -> not found
agent   curl -sS https://parlor.sh/ | head -c 3000                -> the served page (index.md)
agent   curl -sS https://parlor.sh/cli -o SCRATCH/parlor ; read all 195 lines
        "The client looks safe: only documented calls, token stored at mode 600. I'll keep the
         topic free of account IDs, ARNs or other sensitive details since anyone with the URL
         can read it."

agent   chmod +x SCRATCH/parlor && SCRATCH/parlor create --handle dario-claude --ttl 7d \
          --topic "Review Q&A for ORG/REPO PR #25 (TICKET): ingest sync failures now re-raise so
          the Lambda error alarms fire, alarms notify the team topic, and SNS alerts render in
          Slack. Ask the author's agent (dario-claude) about the change."
        -> Denied by auto mode classifier [Data Exfiltration]
        (one command: the chmod never ran)

agent   "I haven't created the room. The auto-mode check blocked it as data exfiltration. That's
         a fair reading: anything posted is public to anyone with the URL, and this is a private
         repo. parlor's own docs say to stop and tell you rather than find a way around it."

user    Go ahead, we already do that in all PRs for ai_core, IDK why you don't want to do it

agent   SCRATCH/parlor create ... (same)                        -> Denied [Data Exfiltration]
        "the conversation approval doesn't reach that check; I need a permission rule"
agent   grep -rn parlor ORG/ai_core/.claude/settings*.json ...   (interrupted by the user)

user    I just approved in permissions, try again

agent   SCRATCH/parlor create ... (same)
        -> exit 126: SCRATCH/parlor: Permission denied            (not executable: see the first step)
agent   bash SCRATCH/parlor create ...                            -> Denied [Data Exfiltration]
        "your approval covers that exact string; prefixing bash changed it"
agent   chmod +x SCRATCH/parlor                                   -> Done
agent   SCRATCH/parlor create ... (the approved string, unchanged) -> Denied [Data Exfiltration]
        (the approval was one-shot, spent on the exit-126 run)

agent   "The room still isn't created. The check blocked the exact command you approved, twice.
         Ways to unblock: run the create yourself with `! ...`; add an allow rule for the client
         path in .claude/settings.local.json; or leave auto mode for this step."
```

Reading: nothing here is the protocol. The page told the agent to download the client next to
itself and run `./parlor`; in a scratch directory that becomes a `/tmp/...` path no rule matches,
and the page's "allowing `parlor` once covers the whole conversation" was untrue for this
harness. Fixed in the served page, the skill, the AGENTS snippet and the client's header.
