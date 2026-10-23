#!/usr/bin/env bash
# ROSClaw First Embodiment / Quick Start — uv isolated install + sim demo
#
# Mirrors README quick start using uv + a throwaway ROSCLAW_HOME.
# Installs from this local checkout (editable).
#
# Usage:
#   bash scripts/uv_firstboot_quickstart.sh
#   KEEP=1 bash scripts/uv_firstboot_quickstart.sh
#   ROSCLAW_QS_WORKSPACE=/tmp/my-rosclaw bash scripts/uv_firstboot_quickstart.sh
#   PYTHON_VERSION=3.12 bash scripts/uv_firstboot_quickstart.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_VERSION="${PYTHON_VERSION:-3.11}"
KEEP="${KEEP:-1}"

if [[ -n "${ROSCLAW_QS_WORKSPACE:-}" ]]; then
  WORKSPACE="${ROSCLAW_QS_WORKSPACE}"
  mkdir -p "${WORKSPACE}"
else
  WORKSPACE="$(mktemp -d /tmp/rosclaw-uv-qs.XXXXXX)"
fi

VENV="${WORKSPACE}/venv"
HOME_DIR="${WORKSPACE}/home"

command -v uv >/dev/null 2>&1 || {
  echo "ERROR: uv not found on PATH." >&2
  echo "Install: curl -LsSf https://astral.sh/uv/install.sh | sh" >&2
  exit 2
}

on_error() {
  local code=$?
  echo "" >&2
  echo "FAILED (exit ${code}). Inspect:" >&2
  echo "  workspace=${WORKSPACE}" >&2
  echo "  ROSCLAW_HOME=${HOME_DIR}" >&2
  echo "  CLI=${VENV}/bin/rosclaw" >&2
  exit "${code}"
}
trap on_error ERR

echo "════════════════════════════════════════════════════════"
echo " ROSClaw Quick Start (uv)"
echo "════════════════════════════════════════════════════════"
echo " repo:      ${ROOT}"
echo " workspace: ${WORKSPACE}"
echo " python:    ${PYTHON_VERSION}"
echo " uv:        $(uv --version)"
echo ""

mkdir -p "${HOME_DIR}"

echo "▶ [1/5] Create venv and install rosclaw (editable, local checkout)"
uv venv --python "${PYTHON_VERSION}" "${VENV}"
uv pip install --python "${VENV}/bin/python" -e "${ROOT}"

CLI="${VENV}/bin/rosclaw"
export ROSCLAW_HOME="${HOME_DIR}"
export PATH="${VENV}/bin:${PATH}"

echo "   $($CLI --version)"

echo ""
echo "▶ [2/5] firstboot --yes --profile offline --no-telemetry"
"${CLI}" firstboot --yes --workspace "${ROSCLAW_HOME}" --profile offline --no-telemetry

echo ""
echo "▶ [3/5] doctor --level verified"
set +e
"${CLI}" doctor --level verified
DOCTOR_RC=$?
set -e
if [[ "${DOCTOR_RC}" -ne 0 ]]; then
  echo "WARN: doctor --level verified exited ${DOCTOR_RC} (continuing to demo)"
fi

echo ""
echo "▶ [4/5] demo run ur5e-reach"
"${CLI}" demo run ur5e-reach --json | tee "${WORKSPACE}/ur5e-reach.json"

echo ""
echo "▶ [5/5] explain latest"
"${CLI}" explain latest --json | tee "${WORKSPACE}/explain-latest.json"

echo ""
echo "════════════════════════════════════════════════════════"
echo " SUCCESS"
echo "════════════════════════════════════════════════════════"
echo " ROSCLAW_HOME=${ROSCLAW_HOME}"
echo " CLI=${CLI}"
echo " receipts: ${WORKSPACE}/ur5e-reach.json"
echo " explain:  ${WORKSPACE}/explain-latest.json"
echo ""
echo " Re-use:"
echo "   export ROSCLAW_HOME=${ROSCLAW_HOME}"
echo "   export PATH=${VENV}/bin:\$PATH"
echo "   rosclaw demo list"
echo "   rosclaw doctor --level verified"

if [[ "${KEEP}" != "1" ]]; then
  echo ""
  echo " KEEP=0 set — removing workspace ${WORKSPACE}"
  rm -rf "${WORKSPACE}"
fi
