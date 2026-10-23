#!/usr/bin/env bash
# ROSClaw × pixi ROS2 turtlesim joint check (same repo, dual env, no Docker).
#
# Prerequisites (two other terminals, same repo root):
#   pixi run rosbridge
#   pixi run turtlesim
#
# Usage (from this repo root):
#   bash scripts/showcase/ros2_turtlesim_demo.sh
#   SHOW_MOTION=1 bash scripts/showcase/ros2_turtlesim_demo.sh
#   ENDPOINT=ws://127.0.0.1:9090 bash scripts/showcase/ros2_turtlesim_demo.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI="${ROOT}/.venv/bin/rosclaw"
ENDPOINT="${ENDPOINT:-ws://127.0.0.1:9090}"
ROBOT_ID="${ROBOT_ID:-turtlesim}"
MANIFEST="${MANIFEST:-/tmp/turtlesim_manifest.json}"
PIXI_ROOT="${PIXI_ROOT:-${ROOT}}"
SHOW_MOTION="${SHOW_MOTION:-0}"
export ROSCLAW_HOME="${ROSCLAW_HOME:-${ROOT}/.rosclaw}"

SAFE_ARGS='{"linear":{"x":0.1,"y":0.0,"z":0.0},"angular":{"x":0.0,"y":0.0,"z":0.0},"duration":0.5}'
FAST_ARGS='{"linear":{"x":1.0,"y":0.0,"z":0.0},"angular":{"x":0.0,"y":0.0,"z":1.0},"duration":2.0}'

die() { echo "ERROR: $*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || die "jq is required"
[[ -x "${CLI}" ]] || die "missing ${CLI}; install into .venv first (see README.NEW.md)"

echo "════════════════════════════════════════════════════════"
echo " ROSClaw × pixi turtlesim showcase"
echo "════════════════════════════════════════════════════════"
echo " CLI=${CLI}"
echo " ROSCLAW_HOME=${ROSCLAW_HOME}"
echo " ENDPOINT=${ENDPOINT}"
echo ""

echo "▶ [1/5] ping"
PING="$("${CLI}" ros ping --endpoint "${ENDPOINT}" --json)"
echo "${PING}" | jq '{ok, message, error}'
echo "${PING}" | jq -e '.ok == true' >/dev/null || die "rosbridge not reachable at ${ENDPOINT}"

echo ""
echo "▶ [2/5] discover + compile"
"${CLI}" ros discover --robot-id "${ROBOT_ID}" --endpoint "${ENDPOINT}" --json \
  | jq '{ok, ros_version, distro, topic_count: (.topics|length), nodes}'
"${CLI}" ros compile --robot-id "${ROBOT_ID}" --endpoint "${ENDPOINT}" \
  --output "${MANIFEST}" --json \
  | jq '{ok, output_path, capability_count: (.manifest.capabilities|length)}'

# Prefer /turtle1/cmd_vel capability if present.
CAP="$(
  jq -r '
    .capabilities
    | map(select(.id|test("velocity_command")))
    | (map(select(.id|endswith(".turtle1"))) + .)
    | .[0].id // empty
  ' "${MANIFEST}"
)"
[[ -n "${CAP}" ]] || die "no velocity_command capability in ${MANIFEST}"
echo " Using capability_id=${CAP}"

echo ""
echo "▶ [3/5] validate SAFE (expect ALLOW)"
# CLI exits non-zero when decision is not ALLOW; capture regardless.
set +e
SAFE="$("${CLI}" ros validate-capability "${CAP}" \
  --endpoint "${ENDPOINT}" --robot-id "${ROBOT_ID}" --manifest "${MANIFEST}" \
  --args "${SAFE_ARGS}" --json)"
set -e
echo "${SAFE}" | jq '{ok, decision, reason, violated_constraints}'
echo "${SAFE}" | jq -e '.decision == "ALLOW"' >/dev/null || die "expected ALLOW for safe args"

echo ""
echo "▶ [4/5] validate FAST (expect BLOCK)"
set +e
FAST="$("${CLI}" ros validate-capability "${CAP}" \
  --endpoint "${ENDPOINT}" --robot-id "${ROBOT_ID}" --manifest "${MANIFEST}" \
  --args "${FAST_ARGS}" --json)"
set -e
echo "${FAST}" | jq '{ok, decision, reason, violated_constraints}'
echo "${FAST}" | jq -e '.decision == "BLOCK"' >/dev/null || die "expected BLOCK for fast args"

echo ""
echo "▶ [5/5] execute-capability note (fail-closed without rosclawd)"
set +e
EXEC="$("${CLI}" ros execute-capability "${CAP}" \
  --endpoint "${ENDPOINT}" --robot-id "${ROBOT_ID}" \
  --args "${SAFE_ARGS}" --json 2>/dev/null)"
set -e
echo "${EXEC}" | jq '{ok, status, errors}' 2>/dev/null || echo "${EXEC}"
echo " (Direct execute via CLI is expected to fail-closed; production uses rosclawd.)"

if [[ "${SHOW_MOTION}" == "1" ]]; then
  echo ""
  echo "▶ SHOW_MOTION=1 → pixi ros2 topic pub /turtle1/cmd_vel (demo viz only)"
  [[ -f "${PIXI_ROOT}/pixi.toml" ]] || die "pixi.toml not found under PIXI_ROOT=${PIXI_ROOT}"
  (
    cd "${PIXI_ROOT}"
    pixi run -e default bash -lc \
      'ros2 topic pub --once /turtle1/cmd_vel geometry_msgs/msg/Twist "{linear: {x: 0.5, y: 0.0, z: 0.0}, angular: {x: 0.0, y: 0.0, z: 0.0}}"'
  )
  echo " Check the turtlesim window or: pixi run bash -lc 'ros2 topic echo /turtle1/pose --once'"
fi

echo ""
echo "════════════════════════════════════════════════════════"
echo " SUCCESS"
echo "════════════════════════════════════════════════════════"
echo " See docs/guides/ROS2_TURTLESIM_SHOWCASE.md"
