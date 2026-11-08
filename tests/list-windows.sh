#!/bin/bash
# list-windows joins each client to the workstation its monitor is showing.
# The fixture returns immediately. There is no wait.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

fail() {
  echo "list-windows: $*" >&2
  exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/hyprctl" <<'SH'
#!/bin/bash
if [[ ${1:-} == "-j" && ${2:-} == "monitors" ]]; then
  printf '%s\n' '[{"id":1,"activeWorkspace":{"id":12,"name":"12"}},{"id":2,"activeWorkspace":{"id":21,"name":"21"}}]'
  exit 0
fi
if [[ ${1:-} == "-j" && ${2:-} == "clients" ]]; then
  printf '%s\n' '[{"address":"0xaaa","mapped":true,"class":"google-chrome","initialClass":"google-chrome","title":"GitHub\nlong","workspace":{"id":11,"name":"11"},"monitor":1},{"address":"0xbbb","mapped":true,"class":"org.omarchy.agent","initialClass":"org.omarchy.agent","title":"quake","workspace":{"id":-98,"name":"special:qconsole"},"monitor":1},{"address":"0xccc","mapped":false,"class":"ghost","title":"hidden","workspace":{"id":2,"name":"2"},"monitor":1},{"address":"0xddd","mapped":true,"class":"com.obsproject.Studio","initialClass":"com.obsproject.Studio","title":"OBS","workspace":{"id":21,"name":"21"},"monitor":2}]'
  exit 0
fi
exit 0
SH
chmod +x "$tmp/hyprctl"

PATH="$tmp:$PATH" ./helpers/list-windows >"$tmp/out"

python3 - "$tmp/out" <<'PY'
import json, sys
rows = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
by = {row["address"]: row for row in rows}
if set(by) != {"0xaaa", "0xbbb", "0xddd"}:
    raise SystemExit(f"unexpected clients: {sorted(by)}")
chrome = by["0xaaa"]
if chrome["workspaceId"] != 11 or chrome["monitorWorkspaceId"] != 12:
    raise SystemExit(f"chrome: {chrome}")
if "\n" in chrome["title"] or chrome["title"] != "GitHub long":
    raise SystemExit(f"title was not flattened: {chrome['title']!r}")
quake = by["0xbbb"]
if quake["workspaceId"] != -98 or quake["monitorWorkspaceId"] != 12:
    raise SystemExit(f"quake: {quake}")
if quake["workspace"] != "special:qconsole":
    raise SystemExit(f"quake workspace name: {quake}")
obs = by["0xddd"]
if obs["workspaceId"] != 21 or obs["monitorWorkspaceId"] != 21:
    raise SystemExit(f"obs: {obs}")
print("list-windows: ok")
PY
