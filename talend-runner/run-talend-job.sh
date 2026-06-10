#!/bin/bash
# Unified Talend job launcher, installed as /usr/local/bin/run-talend-job.
# All Rundeck job templates call this instead of duplicating lookup logic.
#
#   run-talend-job <JOB_NAME>
#
# Behaviour is driven by environment variables (set by the Rundeck job from
# its options):
#
#   TALEND_CONTEXT         Talend context to run with            (default: Default)
#   TALEND_CONTEXT_PARAMS  key=value pairs, separated by newlines or ';',
#                          passed as repeated --context_param flags
#   TALEND_JVM_OPTS        JVM options, e.g. "-Xms512M -Xmx4G -Duser.timezone=UTC"
#   TALEND_JOB_ARGS        extra raw arguments appended verbatim
#
# Artifact lookup order under /artifacts:
#   1. <JOB>/<JOB>_run.sh or <JOB>/<JOB>/<JOB>_run.sh
#      (Talend "Build Job" exports — the zip may nest the launcher one level
#       below jobInfo.properties + lib/)
#   2. <JOB>/<JOB>.jar      (runnable jar)
#   3. <JOB>.jar            (flat jar)
#
# JVM options: Talend-generated *_run.sh launchers hardcode their java flags
# (`java -Xms256M -Xmx1024M -cp ...`), so we rewrite that line when
# TALEND_JVM_OPTS is set. JAVA_TOOL_OPTIONS is also exported as a fallback so
# agent/GC flags reach any nested JVM the script may spawn.
set -euo pipefail

JOB="${1:?usage: run-talend-job <JOB_NAME>}"
CTX="${TALEND_CONTEXT:-Default}"
BASE="/artifacts/${JOB}"

# --- assemble Talend arguments -----------------------------------------------
ARGS=("--context=${CTX}")

if [ -n "${TALEND_CONTEXT_PARAMS:-}" ]; then
  while IFS= read -r kv; do
    kv="${kv#"${kv%%[![:space:]]*}"}"   # ltrim
    kv="${kv%"${kv##*[![:space:]]}"}"   # rtrim
    [ -n "$kv" ] || continue
    if [[ "$kv" != *"="* ]]; then
      echo "[run-talend-job] WARN: ignoring malformed context param '$kv' (expected key=value)" >&2
      continue
    fi
    ARGS+=("--context_param" "$kv")
  done < <(printf '%s\n' "${TALEND_CONTEXT_PARAMS}" | tr ';' '\n')
fi

if [ -n "${TALEND_JOB_ARGS:-}" ]; then
  # Intentional word splitting: JOB_ARGS is a raw argument string.
  # shellcheck disable=SC2206
  ARGS+=(${TALEND_JOB_ARGS})
fi

echo "[run-talend-job] job=${JOB} context=${CTX} jvm_opts='${TALEND_JVM_OPTS:-}' args: ${ARGS[*]}"

# --- launch -------------------------------------------------------------------
if [ -n "${TALEND_JVM_OPTS:-}" ]; then
  export JAVA_TOOL_OPTIONS="${TALEND_JVM_OPTS}"
fi

# The launcher may sit directly in BASE or one level down (Talend zips often
# wrap it as <JOB>/<JOB>_run.sh next to a top-level lib/ + jobInfo.properties).
RUN_SCRIPT=""
for candidate in "${BASE}/${JOB}_run.sh" "${BASE}/${JOB}/${JOB}_run.sh"; do
  if [ -f "${candidate}" ]; then RUN_SCRIPT="${candidate}"; break; fi
done
if [ -z "${RUN_SCRIPT}" ]; then
  RUN_SCRIPT="$(find "${BASE}" -maxdepth 2 -name '*_run.sh' 2>/dev/null | head -1 || true)"
fi

if [ -n "${RUN_SCRIPT}" ]; then
  RUN_DIR="$(dirname "${RUN_SCRIPT}")"
  chmod +x "${RUN_SCRIPT}" 2>/dev/null || true
  if [ -n "${TALEND_JVM_OPTS:-}" ]; then
    # Replace the hardcoded -X* flags of the Talend launcher with the
    # requested ones (command-line -Xmx wins over JAVA_TOOL_OPTIONS, so the
    # script defaults must be removed, not just overridden).
    # Run the patched content via `bash -c` with $0 set to the ORIGINAL
    # script path: Talend launchers do `cd $(dirname $0)` and use relative
    # classpaths (.:../lib/*), and the artifact directory may be read-only
    # for the SSH user, so no patched copy is written anywhere.
    PATCHED_CONTENT="$(sed -E "s|^(java[[:space:]]+)(-X[^[:space:]]+[[:space:]]+)*|\1${TALEND_JVM_OPTS} |" \
      "${RUN_SCRIPT}")"
    cd "${RUN_DIR}"
    exec bash -c "${PATCHED_CONTENT}" "${RUN_SCRIPT}" "${ARGS[@]}"
  fi
  cd "${RUN_DIR}"
  exec "${RUN_SCRIPT}" "${ARGS[@]}"
elif [ -f "${BASE}/${JOB}.jar" ]; then
  # shellcheck disable=SC2086
  exec java ${TALEND_JVM_OPTS:-} -jar "${BASE}/${JOB}.jar" "${ARGS[@]}"
elif [ -f "/artifacts/${JOB}.jar" ]; then
  # shellcheck disable=SC2086
  exec java ${TALEND_JVM_OPTS:-} -jar "/artifacts/${JOB}.jar" "${ARGS[@]}"
else
  echo "[run-talend-job] ERROR: no artifact for '${JOB}' under /artifacts" >&2
  ls -la /artifacts >&2 || true
  exit 2
fi
