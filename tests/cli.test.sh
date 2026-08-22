#!/usr/bin/env bash
# Exercises the CLI paths that must not need the network — and the one that
# must survive not having it. Runs against a throwaway XDG_STATE_HOME, so it
# never touches the real token or outbox.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI="$HERE/../bin/omarchy-capacities"

sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

export XDG_STATE_HOME="$sandbox/state"
export XDG_CONFIG_HOME="$sandbox/config"
export CAPACITIES_TOKEN="cap-api-test-token"
# Port 9 is discard: connections are refused immediately, which is the
# "no network" case without a nine-second wait for a timeout.
export CAPACITIES_API="https://127.0.0.1:9"
export PATH="$sandbox/bin:$PATH"   # no omarchy-notification-send here

pass=0 fail=0
check() {
  if [[ $2 == "$3" ]]; then
    pass=$((pass + 1)); echo "  ok   $1"
  else
    fail=$((fail + 1)); echo "  FAIL $1: expected [$3], got [$2]"
  fi
}

# A capture that cannot be sent is kept, not lost, and does not report failure
# to the shell that fired it.
out="$("$CLI" capture "queued thought" 2>/dev/null)"; code=$?
check "offline capture exits 0" "$code" "0"
check "offline capture queues one" "$("$CLI" status | python3 -c 'import json,sys;print(json.load(sys.stdin)["queued"])')" "1"

# Draining into the same closed door keeps it queued rather than dropping it.
"$CLI" drain >/dev/null 2>&1
check "drain keeps it while offline" "$("$CLI" status | python3 -c 'import json,sys;print(json.load(sys.stdin)["queued"])')" "1"

# Empty captures are not worth a queue entry.
"$CLI" capture "   " >/dev/null 2>&1
check "blank capture queues nothing" "$("$CLI" status | python3 -c 'import json,sys;print(json.load(sys.stdin)["queued"])')" "1"

# A search with no network is an error the shell can show, not a crash.
"$CLI" search anything >/dev/null 2>&1
check "offline search exits 2" "$?" "2"

# Logging out forgets the stored token.
"$CLI" login --token "cap-api-stored" >/dev/null 2>&1
check "token file is 0600" "$(stat -c '%a' "$XDG_STATE_HOME/omarchy/capacities/token" 2>/dev/null)" "600"
"$CLI" logout >/dev/null 2>&1
check "logout removes the token file" "$([[ -e $XDG_STATE_HOME/omarchy/capacities/token ]] && echo yes || echo no)" "no"


# --- uninstall -----------------------------------------------------------
# Everything setup writes outside the plugin lives in a marked block or is a
# symlink it made. Removal has to take exactly those and nothing beside them.
fake="$sandbox/home"
mkdir -p "$fake/.config/omarchy/extensions" "$fake/.config/hypr" "$fake/.local/bin"
cat > "$fake/.config/omarchy/extensions/omarchy-menu.jsonc" <<'MENU'
{
  "trigger.keep-me": { "label": "Not ours" },
  // >>> capacities menu >>>
  "trigger.capacities": { "label": "Capacities" },
  // <<< capacities menu <<<
  "trigger.also-keep": { "label": "Also not ours" }
}
MENU
cat > "$fake/.config/hypr/bindings.lua" <<'BINDS'
o.bind("SUPER + T", "Terminal", "ghostty")
-- >>> capacities >>>
o.bind("SUPER + M", "Capture", "x")
-- <<< capacities <<<
o.bind("SUPER + Q", "Close", "z")
BINDS
ln -s "$CLI" "$fake/.local/bin/omarchy-capacities"
printf '#!/bin/sh\n' > "$fake/.local/bin/capacities-bind-key"   # someone else's file

HOME="$fake" XDG_CONFIG_HOME="$fake/.config" XDG_STATE_HOME="$fake/.local/state" \
  "$HERE/../bin/capacities-uninstall" --yes >/dev/null 2>&1

check "menu keeps what was not ours" \
  "$(grep -ci 'not ours' "$fake/.config/omarchy/extensions/omarchy-menu.jsonc")" "2"
check "menu loses our block" \
  "$(grep -c 'trigger.capacities' "$fake/.config/omarchy/extensions/omarchy-menu.jsonc")" "0"
check "bindings keep what was not ours" \
  "$(grep -c 'SUPER + T\|SUPER + Q' "$fake/.config/hypr/bindings.lua")" "2"
check "bindings lose our block" \
  "$(grep -c 'SUPER + M' "$fake/.config/hypr/bindings.lua")" "0"
check "our symlink is removed" \
  "$([[ -e $fake/.local/bin/omarchy-capacities ]] && echo yes || echo no)" "no"
check "a file that is not ours survives" \
  "$([[ -f $fake/.local/bin/capacities-bind-key ]] && echo yes || echo no)" "yes"

# --- hostile endpoint ----------------------------------------------------
# The shell runs this client, so an unbounded read is the shell's memory. A
# server that answers with more than the cap must be refused rather than
# buffered, and refusing must not look like success.
python3 - "$sandbox" <<'PY' &
import http.server, socketserver, sys, threading
class Flood(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        chunk = b"x" * (1024 * 1024)
        try:
            self.wfile.write(b'{"padding":"')
            for _ in range(12):          # 12 MB, past the 8 MB cap
                self.wfile.write(chunk)
            self.wfile.write(b'"}')
        except BrokenPipeError:
            pass                          # the client hung up: that is the point
    def log_message(self, *a): pass
class Quiet(socketserver.TCPServer):
    allow_reuse_address = True
    # The client hanging up mid-flood is the result under test, not a fault.
    def handle_error(self, request, client_address): pass
with Quiet(("127.0.0.1", 8731), Flood) as httpd:
    open(sys.argv[1] + "/server.ready", "w").close()
    httpd.serve_forever()
PY
server_pid=$!
for _ in $(seq 1 50); do [[ -e $sandbox/server.ready ]] && break; sleep 0.1; done

flood_out="$(CAPACITIES_API=http://127.0.0.1:8731 "$CLI" space --refresh 2>&1)"; flood_code=$?
kill "$server_pid" 2>/dev/null || true

check "an oversized response is refused" "$flood_code" "2"
check "and says so rather than half-parsing" \
  "$(printf '%s' "$flood_out" | grep -qi 'more than' && echo said || echo silent)" "said"

# Display strings are bounded before they reach the shell's text layout.
long_title="$(python3 -c "print('A' * 5000)")"
clamped="$(python3 - "$HERE/../bin/omarchy-capacities" "$long_title" <<'PY'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("cap", sys.argv[1])
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("cap", loader))
loader.exec_module(m)
print(len(m.clamp(sys.argv[2])))
PY
)"
check "a 5000-character title is clamped" "$clamped" "400"

echo
echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
