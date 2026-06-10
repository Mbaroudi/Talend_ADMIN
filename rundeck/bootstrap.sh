#!/bin/bash
# =============================================================================
# Provision Rundeck for Talend orchestration:
#   1. authenticate as admin (session cookie)
#   2. create the `talend` project with a file node source (the runner)
#   3. import the Talend job templates
#   4. apply the operator ACL
# Idempotent: safe to re-run (uses dupeOption=update / upsert semantics).
# =============================================================================
set -euo pipefail

RUNDECK_URL="${RUNDECK_URL:-http://rundeck:4440}"
API="${RUNDECK_URL}/api/41"
COOKIE="$(mktemp)"
PROJECT="talend"

log() { echo "[bootstrap] $*"; }

# --- 1. Wait for Rundeck and log in -----------------------------------------
log "Waiting for Rundeck at ${RUNDECK_URL} ..."
for i in $(seq 1 60); do
  if curl -sf -o /dev/null "${RUNDECK_URL}/"; then break; fi
  sleep 5
  [ "$i" = "60" ] && { log "Rundeck never became ready"; exit 1; }
done

log "Authenticating as ${RUNDECK_ADMIN_USER} ..."
curl -sf -c "$COOKIE" -o /dev/null "${RUNDECK_URL}/user/login"
# No -L: the session cookie is set on the 302 response itself, and the
# redirect target is RUNDECK_GRAILS_URL (the PUBLIC url, e.g. localhost:4440)
# which is not reachable from inside this container.
curl -sf -c "$COOKIE" -b "$COOKIE" -o /dev/null \
  --data-urlencode "j_username=${RUNDECK_ADMIN_USER}" \
  --data-urlencode "j_password=${RUNDECK_ADMIN_PASSWORD}" \
  "${RUNDECK_URL}/j_security_check"

api() {  # api METHOD PATH [curl args...]
  local method="$1" path="$2"; shift 2
  curl -sS -b "$COOKIE" -H 'Accept: application/json' \
    -X "$method" "${API}${path}" "$@"
}

# --- 2. Create the project (ignore "already exists") ------------------------
log "Creating project '${PROJECT}' ..."
api POST "/projects" -H 'Content-Type: application/json' -d @- <<JSON || true
{
  "name": "${PROJECT}",
  "config": {
    "project.description": "Talend job orchestration",
    "resources.source.1.type": "file",
    "resources.source.1.config.file": "/home/rundeck/server/config/talend-resources.yaml",
    "resources.source.1.config.includeServerNode": "false",
    "resources.source.1.config.generateFileAutomatically": "false",
    "resources.source.1.config.requireFileExists": "true",
    "project.ssh-authentication": "privateKey",
    "project.ssh-keypath": "/keys/id_rsa"
  }
}
JSON

# --- 3. Import job templates ------------------------------------------------
log "Importing Talend job templates ..."
api POST "/project/${PROJECT}/jobs/import?fileformat=yaml&dupeOption=update&uuidOption=preserve" \
  -H 'Content-Type: application/yaml' \
  --data-binary @/jobs/talend-jobs.yaml | jq -r '.succeeded[]?.name // empty' || true

# --- 4. Apply operator ACL --------------------------------------------------
log "Applying operator ACL ..."
api POST "/project/${PROJECT}/acl/operator.aclpolicy" \
  -H 'Content-Type: application/yaml' \
  --data-binary @/acl/operator.aclpolicy -o /dev/null \
  || api PUT "/project/${PROJECT}/acl/operator.aclpolicy" \
       -H 'Content-Type: application/yaml' \
       --data-binary @/acl/operator.aclpolicy -o /dev/null || true

log "Done. Project '${PROJECT}' is provisioned."
rm -f "$COOKIE"
