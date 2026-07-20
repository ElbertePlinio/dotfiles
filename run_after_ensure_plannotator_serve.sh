#!/bin/sh

port=${PLANNOTATOR_PORT:-19432}
case "$port" in
  ''|*[!0-9]*|??????*)
    printf 'warning: invalid PLANNOTATOR_PORT %s; Plannotator Serve was not configured\n' "$port" >&2
    exit 0
    ;;
esac
if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
  printf 'warning: invalid PLANNOTATOR_PORT %s; Plannotator Serve was not configured\n' "$port" >&2
  exit 0
fi

if ! command -v tailscale >/dev/null 2>&1; then
  printf '%s\n' 'warning: tailscale is not installed; Plannotator Serve was not configured' >&2
  exit 0
fi

status_json=$(tailscale status --json 2>/dev/null) || {
  printf '%s\n' 'warning: tailscale status is unavailable; Plannotator Serve was not configured' >&2
  exit 0
}

backend_state=$(printf '%s' "$status_json" | node -e '
  let input = "";
  process.stdin.on("data", chunk => input += chunk);
  process.stdin.on("end", () => {
    try { process.stdout.write(JSON.parse(input).BackendState || ""); } catch {}
  });
' 2>/dev/null) || backend_state=

if [ "$backend_state" != Running ]; then
  printf '%s\n' 'warning: tailscale is not running; Plannotator Serve was not configured' >&2
  exit 0
fi

tailscale serve --bg --yes --https="$port" "http://127.0.0.1:$port"
