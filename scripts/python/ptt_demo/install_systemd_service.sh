#!/usr/bin/env bash
set -euo pipefail

# Install and enable systemd service for PTT demo API.
# Run as root: sudo ./install_systemd_service.sh [options]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="ptt-demo-api.service"
SERVICE_SRC="$SCRIPT_DIR/ptt-demo-api.service"
ENV_EXAMPLE="$SCRIPT_DIR/ptt-demo-api.env.example"

UNIT_DEST="/etc/systemd/system/$SERVICE_NAME"
ENV_DEST="/etc/default/ptt-demo-api"

SERVICE_USER="root"
SERVICE_GROUP="root"
WORKDIR_DEFAULT="$SCRIPT_DIR"
WORKDIR="$WORKDIR_DEFAULT"
ENABLE_NOW=1

usage() {
  cat <<'EOF'
Usage: install_systemd_service.sh [options]

Options:
  --user <name>          Service user (default: root)
  --group <name>         Service group (default: root)
  --workdir <path>       ptt_demo directory path (default: script dir)
  --no-enable            Install only; do not enable/start service
  -h, --help             Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)
      SERVICE_USER="$2"
      shift 2
      ;;
    --group)
      SERVICE_GROUP="$2"
      shift 2
      ;;
    --workdir)
      WORKDIR="$2"
      shift 2
      ;;
    --no-enable)
      ENABLE_NOW=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: Please run as root (sudo)." >&2
  exit 1
fi

if [[ ! -f "$SERVICE_SRC" ]]; then
  echo "ERROR: Missing service template: $SERVICE_SRC" >&2
  exit 1
fi

if [[ ! -d "$WORKDIR" ]]; then
  echo "ERROR: Workdir does not exist: $WORKDIR" >&2
  exit 1
fi

if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
  echo "ERROR: Service user does not exist: $SERVICE_USER" >&2
  exit 1
fi

if ! getent group "$SERVICE_GROUP" >/dev/null 2>&1; then
  echo "ERROR: Service group does not exist: $SERVICE_GROUP" >&2
  exit 1
fi

if [[ ! -x "$WORKDIR/.venv/bin/python" ]]; then
  echo "ERROR: Python venv not ready: $WORKDIR/.venv/bin/python" >&2
  echo "Run run_demo_linux.sh once to bootstrap venv and dependencies." >&2
  exit 1
fi

tmp_unit="$(mktemp)"
cp "$SERVICE_SRC" "$tmp_unit"

sed -i "s|^User=.*$|User=$SERVICE_USER|" "$tmp_unit"
sed -i "s|^Group=.*$|Group=$SERVICE_GROUP|" "$tmp_unit"
sed -i "s|^WorkingDirectory=.*$|WorkingDirectory=$WORKDIR|" "$tmp_unit"
sed -i "s|^ExecStart=.*$|ExecStart=$WORKDIR/.venv/bin/python -m uvicorn ptt_demo_service:app --host \\\${API_HOST} --port \\\${API_PORT}|" "$tmp_unit"
sed -i "s|^ProtectHome=.*$|ProtectHome=false|" "$tmp_unit"

install -m 0644 "$tmp_unit" "$UNIT_DEST"
rm -f "$tmp_unit"

if [[ ! -f "$ENV_DEST" ]]; then
  install -m 0644 "$ENV_EXAMPLE" "$ENV_DEST"
  echo "Created env file: $ENV_DEST"
else
  echo "Env file already exists, keeping: $ENV_DEST"
fi

systemctl daemon-reload

if [[ "$ENABLE_NOW" -eq 1 ]]; then
  systemctl enable --now "$SERVICE_NAME"
  systemctl status "$SERVICE_NAME" --no-pager -l || true
else
  echo "Service installed but not enabled."
  echo "Run: systemctl enable --now $SERVICE_NAME"
fi

echo "Done."
