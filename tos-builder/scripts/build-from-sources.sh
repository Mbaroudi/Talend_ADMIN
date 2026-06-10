#!/bin/bash
# Build a runnable Talend job from RAW Studio project sources.
#   build-from-sources.sh <git_url> <branch> <job_name>
#
# The repository must contain a Talend project (a `talend.project` file at the
# root or in a first-level directory) — i.e. what Talend Studio stores in its
# workspace and what teams version in Git.
#
# Pipeline: clone -> copy project into a fresh workspace -> headless Studio
# commandline (logonProject + buildJob = code generation) -> unpack the
# produced zip into /artifacts/<job>/ (same layout as the Maven builder).
#
# Libraries are resolved by Maven ON DEMAND into ${M2_DIR} (persistent
# volume): the first build downloads what the job actually needs, later
# builds reuse the cache.
set -euo pipefail

GIT_URL="${1:?git_url required}"
BRANCH="${2:-main}"
JOB_NAME="${3:?job_name required}"

TOS_HOME="${TOS_HOME:-/opt/tos}"
STUDIO="${TOS_HOME}/studio"
WORKSPACE_DIR="${WORKSPACE_DIR:-/build}"
OUTPUT_DIR="${OUTPUT_DIR:-/artifacts}"
HEAP="${TOS_BUILDER_HEAP:-2048m}"
# The Studio's own Maven repository (persisted in the tos_studio volume):
# seeded at first logon, then grown ON DEMAND by resolve_missing_jars().
M2_REPO="${STUDIO}/configuration/.m2/repository"
MVN_INDEX="${STUDIO}/configuration/MavenUriIndex.xml"
LIB_REPOS=(
  "https://repo1.maven.org/maven2"
  "https://talend-update.talend.com/nexus/content/repositories/libraries"
)

if [ ! -f "${TOS_HOME}/.ready" ]; then
  echo "ERROR: studio not provisioned yet (first-start download still running?)" >&2
  echo "       check: ${TOS_HOME}/prepare.log" >&2
  exit 3
fi

STAMP="$$-$(date +%s)"
CLONE="${WORKSPACE_DIR}/clone-${STAMP}"
WS="${WORKSPACE_DIR}/ws-${STAMP}"
OUT="${WORKSPACE_DIR}/out-${STAMP}"
cleanup() { rm -rf "${CLONE}" "${WS}" "${OUT}"; }
trap cleanup EXIT

echo "=== TOS build: ${JOB_NAME} from ${GIT_URL} (${BRANCH}) ==="
git clone --depth 1 --branch "${BRANCH}" "${GIT_URL}" "${CLONE}"

# Locate the Talend project (talend.project at root or one level down).
PROJECT_FILE="$(find "${CLONE}" -maxdepth 2 -name talend.project -not -path '*/.git/*' | head -1)"
if [ -z "${PROJECT_FILE}" ]; then
  echo "ERROR: no talend.project found — this repo does not contain raw Studio" >&2
  echo "       project sources. For Maven projects/exports use the Maven builder." >&2
  exit 4
fi
PROJECT_DIR="$(dirname "${PROJECT_FILE}")"

# Project name = technicalLabel (fallback: label) from talend.project.
PROJECT_NAME="$(grep -o 'technicalLabel="[^"]*"' "${PROJECT_FILE}" | head -1 | cut -d'"' -f2)"
[ -z "${PROJECT_NAME}" ] && PROJECT_NAME="$(grep -o ' label="[^"]*"' "${PROJECT_FILE}" | head -1 | cut -d'"' -f2)"
if [ -z "${PROJECT_NAME}" ]; then
  echo "ERROR: could not read the project name from talend.project" >&2
  exit 4
fi
echo "--- project: ${PROJECT_NAME} (${PROJECT_DIR#"${CLONE}"/}) ---"

mkdir -p "${WS}" "${OUT}"
cp -r "${PROJECT_DIR}" "${WS}/${PROJECT_NAME}"

LAUNCHER="$(find "${STUDIO}/plugins" -maxdepth 1 -name 'org.eclipse.equinox.launcher_*.jar' | head -1)"

# Resolve "Missing jars:" reported by the code generator. Each jar name is
# looked up in the Studio's own MavenUriIndex.xml (jar -> mvn:g/a/v/type),
# then fetched ON DEMAND from Maven Central (or Talend's library mirror)
# into the Studio m2 — no bulk pre-download, downloaded once, cached in the
# volume. Returns 0 if at least one new jar was installed (=> retry build).
resolve_missing_jars() {
  local log="$1" jar uri g a v gpath dest repo installed=1
  mapfile -t jars < <(grep -hoE '[Mm]issing jars?:[^ ]+\.jar[^ ]*' "$log" \
    | sed -E 's/^[Mm]issing jars?://' | tr ',' '\n' | sed 's/[^A-Za-z0-9._-]//g' | sort -u)
  for jar in "${jars[@]}"; do
    [ -n "$jar" ] || continue
    uri="$(grep -o "key=\"${jar}\" value=\"mvn:[^\"]*\"" "${MVN_INDEX}" 2>/dev/null \
      | sed -E 's/.*value="mvn:([^"]*)".*/\1/' | head -1)"
    if [ -z "$uri" ]; then
      echo "[on-demand] WARN: no maven mapping for ${jar} in MavenUriIndex.xml"
      continue
    fi
    IFS=/ read -r g a v _ <<< "$uri"
    gpath="${g//.//}"
    dest="${M2_REPO}/${gpath}/${a}/${v}/${a}-${v}.jar"
    [ -f "$dest" ] && continue
    mkdir -p "$(dirname "$dest")"
    for repo in "${LIB_REPOS[@]}"; do
      if curl -fsSL --retry 2 -o "$dest" "${repo}/${gpath}/${a}/${v}/${a}-${v}.jar"; then
        echo "[on-demand] installed ${jar} (mvn:${uri}) from ${repo}"
        installed=0
        break
      fi
      rm -f "$dest"
    done
    [ -f "$dest" ] || echo "[on-demand] WARN: could not resolve ${jar} (mvn:${uri})"
  done
  return "$installed"
}

run_headless_build() {
  # Plain JVM through the equinox launcher: no native Studio binary, no
  # GTK/X11. Our org.talendadmin.cibuilder application (compiled against the
  # Studio at provisioning time) drives logon + code generation + build.
  java "-Xmx${HEAP}" \
    -Dfile.encoding=UTF-8 \
    --add-opens java.base/java.lang=ALL-UNNAMED \
    --add-opens java.base/java.util=ALL-UNNAMED \
    -cp "${LAUNCHER}" org.eclipse.equinox.launcher.Main \
    -nosplash --launcher.suppressErrors \
    -application org.talendadmin.cibuilder.app \
    -data "${WS}" -consoleLog \
    -project "${PROJECT_NAME}" -job "${JOB_NAME}" -destination "${OUT}/${JOB_NAME}.zip"
}

echo "--- headless code generation + build (heap ${HEAP}) ---"
BUILD_LOG="${WORKSPACE_DIR}/build-${STAMP}.log"
attempt=1
while true; do
  rc=0
  run_headless_build 2>&1 | tee "${BUILD_LOG}" || rc=$?
  [ "$rc" -eq 0 ] && break
  if [ "$attempt" -ge 3 ]; then
    echo "ERROR: build failed after ${attempt} attempts" >&2
    exit "$rc"
  fi
  if resolve_missing_jars "${BUILD_LOG}"; then
    attempt=$((attempt + 1))
    echo "--- retrying build (attempt ${attempt}) after on-demand library install ---"
    # a fresh workspace avoids stale eclipse metadata from the failed run
    rm -rf "${WS}/.metadata"
    continue
  fi
  exit "$rc"
done
rm -f "${BUILD_LOG}"

ARCHIVE="$(find "${OUT}" -name '*.zip' | head -1 || true)"
if [ -z "${ARCHIVE}" ]; then
  echo "ERROR: commandline finished but produced no archive in ${OUT}" >&2
  echo "       (does job '${JOB_NAME}' exist in project '${PROJECT_NAME}'?)" >&2
  exit 5
fi

DEST="${OUTPUT_DIR}/${JOB_NAME}"
echo "--- unpacking $(basename "${ARCHIVE}") -> ${DEST} ---"
mkdir -p "${DEST}"
rm -rf "${DEST:?}/"* 2>/dev/null || true
TMP="$(mktemp -d)"
unzip -q "${ARCHIVE}" -d "${TMP}"
top_count="$(find "${TMP}" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"
inner="$(find "${TMP}" -mindepth 1 -maxdepth 1 -type d | head -1)"
if [ "${top_count}" = "1" ] && [ -n "${inner}" ]; then
  cp -r "${inner}"/. "${DEST}"/
else
  cp -r "${TMP}"/. "${DEST}"/
fi
rm -rf "${TMP}"
chmod +x "${DEST}"/*_run.sh "${DEST}"/**/*_run.sh 2>/dev/null || true

echo "=== Artifact ready: ${DEST} ==="
