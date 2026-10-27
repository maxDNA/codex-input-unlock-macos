#!/bin/bash
# codex-input-unlock for macOS
#
# macOS port of https://github.com/1zero224/codex-input-unlock (MIT).
# Cold-starts the official Codex Desktop app (/Applications/ChatGPT.app,
# bundle id com.openai.codex) with a CDP debug port, then lets
# cdp-supervisor.mjs inject conditional breakpoints that clear the local
# composer quota lock. Does NOT touch server-side quota.
#
# Usage:
#   ./codex-input-unlock.sh launch    # cold-start app with unlock (default)
#   ./codex-input-unlock.sh verify    # check supervisor / CDP / breakpoint state
#   ./codex-input-unlock.sh stop      # stop the supervisor daemon
#   ./codex-input-unlock.sh diagnose  # environment + state summary
set -euo pipefail

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_BUNDLE_ID="com.openai.codex"
SUPPORT_DIR="$HOME/Library/Application Support/CodexInputUnlock"
STATE_DIR="$SUPPORT_DIR/state"
LOG_DIR="$SUPPORT_DIR/logs"
PID_FILE="$STATE_DIR/supervisor.pid"
STARTUP_TIMEOUT="${STARTUP_TIMEOUT:-60}"

info() { echo "[codex-input-unlock] $*"; }
fail() { echo "[codex-input-unlock] ERROR: $*" >&2; exit 1; }

json_get() { # json_get <file> <key>  -> raw JSON value
  node -e '
    const [file, key] = process.argv.slice(1);
    try {
      const data = JSON.parse(require("fs").readFileSync(file, "utf8"));
      const value = data[key];
      process.stdout.write(value === undefined ? "" : (typeof value === "string" ? value : JSON.stringify(value)));
    } catch { process.exit(1); }
  ' "$1" "$2"
}

find_node() {
  if command -v node >/dev/null 2>&1; then command -v node; return; fi
  for candidate in /opt/homebrew/bin/node /usr/local/bin/node; do
    if [ -x "$candidate" ]; then echo "$candidate"; return; fi
  done
  fail "Node.js 22+ is required but was not found. Install it (brew install node) and retry."
}

find_app() {
  # Explicit override wins; then Spotlight locates the bundle by ID so
  # non-/Applications installs work; last resort is the default path.
  if [ -n "${CODEX_APP_PATH:-}" ]; then
    if [ -d "$CODEX_APP_PATH" ]; then
      echo "$CODEX_APP_PATH"
      return 0
    fi
    fail "CODEX_APP_PATH is set to '$CODEX_APP_PATH' but the directory does not exist."
  fi
  local found
  found="$(mdfind "kMDItemCFBundleIdentifier == '$APP_BUNDLE_ID'" 2>/dev/null | head -1 || true)"
  if [ -n "$found" ] && [ -d "$found" ]; then
    echo "$found"
    return 0
  fi
  if [ -d "/Applications/ChatGPT.app" ]; then
    echo "/Applications/ChatGPT.app"
    return 0
  fi
  return 1
}

get_free_port() {
  node -e 'const s=require("net").createServer();s.listen(0,"127.0.0.1",()=>{console.log(s.address().port);s.close()})'
}

running_app_pids() { pgrep -f "ChatGPT\.app/Contents/MacOS/ChatGPT" 2>/dev/null || true; }

running_supervisor_pid() {
  [ -f "$PID_FILE" ] || return 0
  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  [ -n "$pid" ] || return 0
  if kill -0 "$pid" 2>/dev/null && ps -p "$pid" -o command= | grep -q "cdp-supervisor.mjs"; then
    echo "$pid"
  fi
}

latest_status_file() {
  ls -t "$STATE_DIR"/runtime-status-*.json 2>/dev/null | head -1 || true
}

action_launch() {
  local node_bin
  node_bin="$(find_node)"
  local node_version
  node_version="$("$node_bin" -p 'process.versions.node')"
  if [ "${node_version%%.*}" -lt 22 ]; then
    fail "Node.js 22+ required, found $node_version"
  fi
  local app_path
  if ! app_path="$(find_app)"; then
    fail "Codex Desktop not found. Install it, or set CODEX_APP_PATH to its .app path."
  fi
  local app_binary="$app_path/Contents/MacOS/ChatGPT"
  [ -x "$app_binary" ] || fail "Found $app_path but its executable is missing or not runnable."

  local app_pids supervisor_pid
  app_pids="$(running_app_pids | tr '\n' ' ')"
  [ -z "${app_pids// /}" ] || fail "Codex Desktop is still running (pid $app_pids). Quit it completely (menu bar icon included), then launch again. Nothing was closed automatically."
  supervisor_pid="$(running_supervisor_pid || true)"
  [ -z "$supervisor_pid" ] || fail "Supervisor from a previous session is still running (pid $supervisor_pid). Run '$0 stop' first."

  mkdir -p "$STATE_DIR" "$LOG_DIR"
  local port stamp status_file
  port="$(get_free_port)"
  stamp="$(date +%Y%m%d-%H%M%S)"
  status_file="$STATE_DIR/runtime-status-$stamp.json"

  info "Starting CDP supervisor on port $port..."
  nohup "$node_bin" "$INSTALL_DIR/cdp-supervisor.mjs" \
    --port "$port" \
    --gate "$INSTALL_DIR/quota-gate.cjs" \
    --status "$status_file" \
    --startup-timeout "$STARTUP_TIMEOUT" \
    > "$LOG_DIR/supervisor-$stamp.stdout.log" \
    2> "$LOG_DIR/supervisor-$stamp.stderr.log" &
  local supervisor_pid_new=$!
  echo "$supervisor_pid_new" > "$PID_FILE"

  info "Cold-starting Codex Desktop with debug flags..."
  open -a "$app_path" --args \
    --remote-debugging-address=127.0.0.1 \
    --remote-debugging-port="$port" \
    --remote-allow-origins="http://127.0.0.1:$port"

  local deadline=$((SECONDS + STARTUP_TIMEOUT))
  while (( SECONDS < deadline )); do
    if ! kill -0 "$supervisor_pid_new" 2>/dev/null; then
      fail "Supervisor exited early. See $LOG_DIR/supervisor-$stamp.stderr.log"
    fi
    local state
    state="$(json_get "$status_file" state 2>/dev/null || true)"
    case "$state" in
      ready)
        info "READY. Input unlock is active (app pid(s): $(running_app_pids | tr '\n' ' '), supervisor pid: $supervisor_pid_new, CDP port: $port)."
        info "Status: $status_file"
        return 0
        ;;
      failed)
        fail "Supervisor failed: $(json_get "$status_file" error)"
        ;;
    esac
    sleep 1
  done
  fail "Unlock did not become ready within ${STARTUP_TIMEOUT}s. Check $status_file and $LOG_DIR/supervisor-$stamp.stderr.log"
}

action_verify() {
  local supervisor_pid status_file
  supervisor_pid="$(running_supervisor_pid || true)"
  status_file="$(latest_status_file)"
  local ok=false
  if [ -n "$supervisor_pid" ] && [ -n "$status_file" ]; then
    local state port
    state="$(json_get "$status_file" state 2>/dev/null || true)"
    port="$(json_get "$status_file" port 2>/dev/null || true)"
    local cdp=false
    if [ -n "$port" ] && curl -s --max-time 2 "http://127.0.0.1:$port/json" | grep -q '"app://'; then
      cdp=true
    fi
    if [ "$state" = "ready" ] && [ "$cdp" = "true" ]; then ok=true; fi
    info "supervisor: pid=$supervisor_pid state=$state port=$port cdp_app_target=$cdp"
    info "gateStats: $(json_get "$status_file" gateStats 2>/dev/null || echo '{}')"
  else
    info "supervisor: not running"
  fi
  info "app running: $( [ -n "$(running_app_pids)" ] && echo yes || echo no )"
  if [ "$ok" = "true" ]; then info "VERIFY: OK — unlock is active."; else info "VERIFY: NOT ready (cold-start via '$0 launch' required)."; return 1; fi
}

action_stop() {
  local supervisor_pid
  supervisor_pid="$(running_supervisor_pid || true)"
  if [ -n "$supervisor_pid" ]; then
    kill "$supervisor_pid" && info "Stopped supervisor (pid $supervisor_pid)."
  else
    info "No running supervisor found."
  fi
  rm -f "$PID_FILE"
}

action_diagnose() {
  local node_bin
  node_bin="$(find_node)"
  info "node: $("$node_bin" -p 'process.versions.node') at $node_bin"
  local app_path
  if app_path="$(find_app)"; then
    info "app: $app_path ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist" 2>/dev/null || echo '?'))"
  else
    info "app: NOT FOUND (searched Spotlight by bundle ID and /Applications/ChatGPT.app)"
  fi
  info "app running pids: $(running_app_pids | tr '\n' ' ')"
  info "supervisor: $(running_supervisor_pid || echo 'not running')"
  info "latest status: $(latest_status_file || echo none)"
  [ -f "$HOME/.codex/config.toml" ] && info "codex config: $HOME/.codex/config.toml present" || info "codex config: $HOME/.codex/config.toml missing (configure your third-party provider first)"
}

case "${1:-launch}" in
  launch)   action_launch ;;
  verify)   action_verify ;;
  stop)     action_stop ;;
  diagnose) action_diagnose ;;
  *) fail "Unknown action: $1 (use launch|verify|stop|diagnose)" ;;
esac
