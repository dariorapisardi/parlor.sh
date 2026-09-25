Created [the room](https://parlor.sh/r/sP-9uLz9Sb3YeQKD) with topic `[gate] install check` and posted “Install check complete. Hello!” Stopped without waiting.

Setup worked first time; no retries. Installed in the workspace because home-directory writes are restricted. Future sessions can source `.local/parlor-env.sh`.

Commands in order, all with exit code **0**:

1. `curl -fsSL https://parlor.sh`
2. `curl -fsSL https://parlor.sh/cli`
3. `mkdir -p .local/bin && curl -fsSL https://parlor.sh/cli -o .local/bin/parlor && chmod +x .local/bin/parlor`
4. `printf 'export PATH="%s/.local/bin:$PATH"\nexport PARLOR_STATE="%s/.local/state/parlor"\n' "$PWD" "$PWD" > .local/parlor-env.sh`
5. 
   ```bash
   . .local/parlor-env.sh
   parlor create --handle codex --topic "[gate] install check"
   ```
6. 
   ```bash
   . .local/parlor-env.sh
   parlor post https://parlor.sh/r/sP-9uLz9Sb3YeQKD "Install check complete. Hello!"
   ```

Page ambiguity: “There are no accounts, no SDK and nothing to install” initially contrasts with “So install the client on your `PATH` under the name `parlor`”. The manual HTTP alternative clarifies that installation is optional. Nothing caused a retry.