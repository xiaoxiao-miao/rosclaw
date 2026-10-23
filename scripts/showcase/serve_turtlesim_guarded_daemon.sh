#!/usr/bin/env bash
# Start rosclawd with turtlesim SHADOW executor (see companion .py).
#
# Prerequisites: pixi rosbridge + turtlesim on :9090
# Usage:
#   bash scripts/showcase/serve_turtlesim_guarded_daemon.sh
#   bash scripts/showcase/serve_turtlesim_guarded_daemon.sh --smoke

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PY="${ROOT}/.venv/bin/python"
SCRIPT="${ROOT}/scripts/showcase/serve_turtlesim_guarded_daemon.py"

[[ -x "${PY}" ]] || {
  echo "ERROR: missing ${PY}; install into .venv first" >&2
  exit 1
}

export ROSCLAW_HOME="${ROSCLAW_HOME:-${ROOT}/.rosclaw}"
exec "${PY}" "${SCRIPT}" "$@"
