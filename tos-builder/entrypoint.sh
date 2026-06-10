#!/bin/bash
# Start the build API immediately; provision the Studio in the background.
# /health exposes studio_ready so callers can tell the two states apart.
set -euo pipefail

mkdir -p "${TOS_HOME}" "${WORKSPACE_DIR}" "${OUTPUT_DIR}" "${CUSTOM_LIBS_DIR}"

if [ ! -f "${TOS_HOME}/.ready" ]; then
  echo "[tos-builder] Studio not provisioned yet — downloading in the background ..."
  (./scripts/prepare-studio.sh >> "${TOS_HOME}/prepare.log" 2>&1 || \
     echo "[tos-builder] ERROR: studio provisioning failed, see ${TOS_HOME}/prepare.log") &
fi

exec python build_server.py
