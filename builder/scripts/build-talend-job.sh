#!/bin/bash
# Build a Talend Maven project and publish the runnable artifact.
#   build-talend-job.sh <git_url> <branch> <job_name>
#
# Supports two layouts produced by Talend "Build Job":
#   - a .zip archive containing <Job>/<Job>_run.sh + lib/ + jar  (preferred)
#   - a plain executable .jar
set -euo pipefail

GIT_URL="${1:?git_url required}"
BRANCH="${2:-main}"
JOB_NAME="${3:?job_name required}"

WORKSPACE_DIR="${WORKSPACE_DIR:-/tmp/build}"
OUTPUT_DIR="${OUTPUT_DIR:-/artifacts}"
WORK="${WORKSPACE_DIR}/${JOB_NAME}"
DEST="${OUTPUT_DIR}/${JOB_NAME}"

echo "=== Building ${JOB_NAME} from ${GIT_URL} (${BRANCH}) ==="
rm -rf "$WORK"; mkdir -p "$WORK"
git clone --depth 1 --branch "$BRANCH" "$GIT_URL" "$WORK"

cd "$WORK"
if [ -f pom.xml ]; then
  echo "--- Maven package ---"
  mvn -B -ntp clean package -DskipTests
else
  echo "No pom.xml at repo root; scanning for a prebuilt archive ..."
fi

mkdir -p "$DEST"
rm -rf "${DEST:?}/"* 2>/dev/null || true

ARCHIVE="$(find . -path '*/target/*.zip' -not -path '*/.git/*' | head -1 || true)"
[ -z "$ARCHIVE" ] && ARCHIVE="$(find . -name '*.zip' -not -path '*/.git/*' | head -1 || true)"

if [ -n "$ARCHIVE" ]; then
  echo "--- Unpacking archive: $ARCHIVE ---"
  TMP="$(mktemp -d)"
  unzip -q "$ARCHIVE" -d "$TMP"
  top_count="$(find "$TMP" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"
  inner="$(find "$TMP" -mindepth 1 -maxdepth 1 -type d | head -1)"
  if [ "$top_count" = "1" ] && [ -n "$inner" ]; then
    cp -r "$inner"/. "$DEST"/
  else
    cp -r "$TMP"/. "$DEST"/
  fi
  rm -rf "$TMP"
  chmod +x "$DEST"/*_run.sh 2>/dev/null || true
else
  JAR="$(find . -path '*/target/*.jar' -not -name '*-sources.jar' -not -name '*-javadoc.jar' | head -1 || true)"
  if [ -n "$JAR" ]; then
    echo "--- Collecting jar: $JAR ---"
    cp "$JAR" "${DEST}/${JOB_NAME}.jar"
  else
    echo "ERROR: no .zip or .jar artifact was produced" >&2
    exit 2
  fi
fi

# The runner executes jobs as an unprivileged SSH user, and Talend jobs may
# write stats/logs next to their launcher: open up the artifact tree.
chmod -R a+rwX "$DEST" 2>/dev/null || true

# Optional: publish the artifact to MinIO.
if [ -n "${MINIO_ENDPOINT:-}" ] && command -v mc >/dev/null 2>&1; then
  if mc alias set tac "$MINIO_ENDPOINT" "${MINIO_ROOT_USER:-}" "${MINIO_ROOT_PASSWORD:-}" >/dev/null 2>&1; then
    mc cp --recursive "$DEST" "tac/${MINIO_BUCKET_JOBS:-talend-jobs}/" >/dev/null 2>&1 \
      && echo "Published to MinIO bucket: ${MINIO_BUCKET_JOBS:-talend-jobs}/${JOB_NAME}"
  fi
fi

echo "=== Artifact ready: ${DEST} ==="
