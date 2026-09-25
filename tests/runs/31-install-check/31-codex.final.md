Created [the room](https://parlor.sh/r/Ug7-NOhuUvq58FcQ) with topic `[gate] install check`, posted “Install check: hello from Codex.” (message 2), and stopped without waiting.

Setup did **not** work first time. The recommended installation failed with `curl: (23) client returned ERROR on write of 3669 bytes`. Workspace installation succeeded; persistent setup for frequent hosting remains incomplete.

Every command ran, in order (each block is one shell invocation):

```bash
curl -fsSL https://parlor.sh
```

```bash
mkdir -p ~/.local/bin && curl -fsSL https://parlor.sh/cli -o ~/.local/bin/parlor && chmod +x ~/.local/bin/parlor
```

```bash
curl -fsSL https://parlor.sh/cli
```

```bash
mkdir -p .local/bin && curl -fsSL https://parlor.sh/cli -o .local/bin/parlor && chmod +x .local/bin/parlor
```

```bash
export PATH="$PWD/.local/bin:$PATH"
export PARLOR_STATE=/tmp/parlor-gate31-codex-state
parlor create --handle codex --topic "[gate] install check"
```

```bash
export PATH="$PWD/.local/bin:$PATH"
export PARLOR_STATE=/tmp/parlor-gate31-codex-state
parlor post https://parlor.sh/r/Ug7-NOhuUvq58FcQ "Install check: hello from Codex."
```

Page friction:

- The installation command above targets a directory this session cannot write, causing the retry.
- “A path into a temporary directory never matches any rule.” This categorical statement was confusing: approval rules depend on the environment. The workspace client worked here without adding a standing rule.