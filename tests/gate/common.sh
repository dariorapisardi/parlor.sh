# Shared setup for gate tests. Source it. Needs: node, claude, codex, a free port 8787.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$HERE/../.."
OUT="${OUT:?set OUT to a scratch directory for this gate run}"
export PARLOR_URL="${PARLOR_URL:-http://localhost:8787}"   # set PARLOR_URL=https://parlor.sh to run against production
PARLOR="$ROOT/skill/parlor/parlor"
mkdir -p "$OUT"

start_server() { # fresh data dir per gate run; every issued token is recorded for leak scans
  if ! curl -s -o /dev/null "$PARLOR_URL/"; then
    (cd "$ROOT" && DATA_DIR="$OUT/data" PARLOR_TEST_TOKENS="$OUT/issued-tokens.txt" setsid node server.mjs >> "$OUT/server.log" 2>&1 &)
    for i in $(seq 1 20); do curl -s -o /dev/null "$PARLOR_URL/" && break; sleep 0.3; done
  fi
}
wait_for_url() { # wait_for_url FILE [SECONDS]: until FILE contains a room URL; prints it
  for i in $(seq 1 "${2:-300}"); do
    u="$(grep -oE "$PARLOR_URL/r/[A-Za-z0-9_-]+" "$1" 2>/dev/null | head -1)"; [ -n "$u" ] && { echo "$u"; return 0; }; sleep 1
  done; return 1
}
claude_run() { # claude_run DIR MODEL LOGNAME PROMPT  (headless, Bash allowed, stdin closed)
  (cd "$1" && timeout 900 claude -p "$4" --model "$2" --permission-mode acceptEdits --allowedTools "Bash" \
     --output-format stream-json --verbose < /dev/null > "$OUT/$3.jsonl" 2> "$OUT/$3.err")
  jq -r 'select(.type=="result") | .result' "$OUT/$3.jsonl" > "$OUT/$3.final.md"
}
codex_run() { # codex_run DIR LOGNAME PROMPT  (sandboxed, network allowed, stdin closed)
  (cd "$1" && timeout 900 codex exec --skip-git-repo-check --ephemeral -s workspace-write \
     -c sandbox_workspace_write.network_access=true -o "$OUT/$2.final.md" "$3" < /dev/null > "$OUT/$2.log" 2>&1)
}
leak_scan() { # leak_scan DIR...: issued tokens must not appear in files agents meant to share
  local n=0
  while read -r room handle tok; do
    for f in $(grep -rlF "$tok" "$@" 2>/dev/null); do
      case "$f" in *notes*|*token*|*/state*|*.jsonl|*.log|*create*.json|*join*.json|*session*) ;; *) echo "LEAK: token of $handle@$room in $f"; n=$((n+1));; esac
    done
  done < "$OUT/issued-tokens.txt"
  echo "leak scan: $n problem(s)"
}
