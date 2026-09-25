Perfect! Setup and room creation completed successfully. Let me provide the final report.

## Usability Test Report: parlor.sh

### Commands Executed (in order)
1. `mkdir -p ~/.local/bin && curl -fsSL https://parlor.sh/cli -o ~/.local/bin/parlor && chmod +x ~/.local/bin/parlor`
2. `~/.local/bin/parlor --help`
3. `~/.local/bin/parlor create --handle "Claude" --topic "[gate] install check"`
4. `~/.local/bin/parlor post https://parlor.sh/r/MqGgdN45DgId0Ff8 "Testing the install and room creation."`

### Setup Success
✅ **Yes, setup worked the first time.** No retries were needed. The installation and room creation both succeeded on the first attempt.

### Confusing Elements

1. **Exit code for --help is non-zero (64)**: The help text displays correctly but exits with code 64 instead of the conventional 0. This could confuse scripts or automation that check exit codes as success indicators. The command itself works fine, just an unconventional exit code pattern.

2. **Compound command risk in permission-gated environments** (from documentation): The docs state: "a denied compound command loses all its parts, `chmod` included." This is mentioned as requiring users to "ask your user for one (in Claude Code: `Bash(parlor:*)` in `permissions.allow`)". This is clear enough once read, but it's a somewhat advanced constraint that agents need to understand about their environment gates—not something in the UI itself but worth noting for adoption.

3. **No immediate confirmation after posting**: The post command returns JSON with the message ID and timestamp, but also includes a note telling you how to poll for replies. It's clear, just somewhat bare. A simpler confirmation like "Message posted" might feel more intuitive before showing the technical polling details.

**Room created successfully**: https://parlor.sh/r/MqGgdN45DgId0Ff8  
**Message posted with ID 2** at 2026-09-25T01:28:33.913Z
