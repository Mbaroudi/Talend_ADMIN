#!/usr/bin/env python3
"""Git webhook handler — triggers a Talend build+run in Rundeck on push.

Supports GitHub, GitLab and Azure DevOps. On a relevant push it triggers the
configured Rundeck job (Build and Deploy Talend Job) via the Rundeck API,
passing the repository URL, branch and job name as options.
"""
import hashlib
import hmac
import os
import re

import requests
from flask import Flask, jsonify, request
from loguru import logger
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

app = Flask(__name__)

WEBHOOK_SECRET = os.getenv("WEBHOOK_SECRET", "change-me-webhook-secret")
RUNDECK_URL = os.getenv("RUNDECK_URL", "http://rundeck:4440")
RUNDECK_API = f"{RUNDECK_URL}/api/41"
RUNDECK_ADMIN_USER = os.getenv("RUNDECK_ADMIN_USER", "admin")
RUNDECK_ADMIN_PASSWORD = os.getenv("RUNDECK_ADMIN_PASSWORD", "admin")
RUNDECK_PROJECT = os.getenv("RUNDECK_PROJECT", "talend")
RUNDECK_TRIGGER_JOB = os.getenv("RUNDECK_TRIGGER_JOB", "Build and Deploy Talend Job")

ALLOWED_BRANCHES = {"main", "master", "develop"}
BRANCH_PATTERNS = [r"^release/.*", r"^feature/.*", r"^hotfix/.*"]

webhook_requests = Counter("tac_webhook_requests_total", "Webhook requests", ["provider", "event", "status"])
build_triggers = Counter("tac_build_triggers_total", "Build triggers", ["repository", "branch", "status"])
processing_duration = Histogram("tac_webhook_processing_seconds", "Webhook processing duration")


# --------------------------------------------------------------------------- #
# Rundeck client (session-cookie auth, no static token required)
# --------------------------------------------------------------------------- #
class RundeckClient:
    def __init__(self):
        self.base = RUNDECK_URL
        self.api = RUNDECK_API

    def _session(self):
        s = requests.Session()
        s.get(f"{self.base}/user/login", timeout=10)
        s.post(
            f"{self.base}/j_security_check",
            data={"j_username": RUNDECK_ADMIN_USER, "j_password": RUNDECK_ADMIN_PASSWORD},
            timeout=10,
            allow_redirects=True,
        )
        return s

    def _find_job_id(self, session, name):
        resp = session.get(
            f"{self.api}/project/{RUNDECK_PROJECT}/jobs",
            headers={"Accept": "application/json"},
            timeout=15,
        )
        resp.raise_for_status()
        for job in resp.json():
            if job.get("name") == name:
                return job.get("id")
        return None

    def run_job(self, name, options):
        session = self._session()
        job_id = self._find_job_id(session, name)
        if not job_id:
            raise RuntimeError(f"Rundeck job '{name}' not found in project '{RUNDECK_PROJECT}'")
        resp = session.post(
            f"{self.api}/job/{job_id}/run",
            headers={"Accept": "application/json", "Content-Type": "application/json"},
            json={"options": options},
            timeout=30,
        )
        resp.raise_for_status()
        return resp.json()


rundeck = RundeckClient()


# --------------------------------------------------------------------------- #
# Signature verification
# --------------------------------------------------------------------------- #
def verify_signature(payload, signature, provider):
    if provider == "gitlab":
        return signature == WEBHOOK_SECRET
    if not signature:
        return False
    digest = hmac.new(WEBHOOK_SECRET.encode(), payload, hashlib.sha256).hexdigest()
    if provider == "github":
        return hmac.compare_digest(signature, f"sha256={digest}")
    if provider == "azure-devops":
        return hmac.compare_digest(signature.replace("sha256=", ""), digest)
    return False


def extract_repo_info(payload, provider):
    try:
        if provider == "github":
            return {
                "name": payload["repository"]["name"],
                "full_name": payload["repository"]["full_name"],
                "clone_url": payload["repository"]["clone_url"],
                "branch": payload.get("ref", "").replace("refs/heads/", ""),
                "commit_sha": payload.get("after", ""),
                "author": payload.get("head_commit", {}).get("author", {}).get("name", ""),
                "modified_files": _files(payload.get("commits", [])),
            }
        if provider == "gitlab":
            return {
                "name": payload["project"]["name"],
                "full_name": payload["project"]["path_with_namespace"],
                "clone_url": payload["project"]["http_url"],
                "branch": payload.get("ref", "").replace("refs/heads/", ""),
                "commit_sha": payload.get("after", ""),
                "author": (payload.get("commits") or [{}])[0].get("author", {}).get("name", ""),
                "modified_files": _files(payload.get("commits", [])),
            }
        if provider == "azure-devops":
            resource = payload.get("resource", {})
            repo = resource.get("repository", {})
            refs = resource.get("refUpdates", [{}])
            commits = resource.get("commits", [])
            return {
                "name": repo.get("name", ""),
                "full_name": repo.get("name", ""),
                "clone_url": repo.get("remoteUrl", ""),
                "branch": (refs[0].get("name", "") if refs else "").replace("refs/heads/", ""),
                "commit_sha": (refs[0].get("newObjectId", "") if refs else ""),
                "author": (commits[0].get("author", {}).get("name", "") if commits else ""),
                "modified_files": [c.get("comment", "") for c in commits],
            }
    except (KeyError, IndexError, TypeError) as exc:
        logger.error(f"Failed to extract repo info: {exc}")
    return None


def _files(commits):
    files = []
    for commit in commits:
        files.extend(commit.get("added", []))
        files.extend(commit.get("modified", []))
    return list(set(files))


def should_trigger_build(repo):
    branch = repo.get("branch", "")
    if branch not in ALLOWED_BRANCHES and not any(re.match(p, branch) for p in BRANCH_PATTERNS):
        return False, f"Branch '{branch}' is not configured for builds"
    talend_files = [
        f for f in repo.get("modified_files", [])
        if f.endswith((".item", ".properties")) or "routines/" in f or "contexts/" in f
    ]
    if not talend_files:
        return False, "No Talend files changed"
    return True, f"{len(talend_files)} Talend file(s) changed"


# --------------------------------------------------------------------------- #
# Core handling
# --------------------------------------------------------------------------- #
def handle_push(provider, payload, event_type):
    repo = extract_repo_info(payload, provider)
    if not repo:
        webhook_requests.labels(provider, event_type, "error").inc()
        return jsonify(error="Failed to extract repository info"), 400

    should_build, reason = should_trigger_build(repo)
    if not should_build:
        webhook_requests.labels(provider, event_type, "skipped").inc()
        return jsonify(message="Build skipped", reason=reason, repository=repo["full_name"]), 200

    options = {
        "GIT_URL": repo["clone_url"],
        "GIT_BRANCH": repo["branch"],
        "JOB_NAME": repo["name"],  # convention: one job per repo; customize as needed
    }
    try:
        result = rundeck.run_job(RUNDECK_TRIGGER_JOB, options)
    except Exception as exc:  # noqa: BLE001 - surface any Rundeck failure to caller
        webhook_requests.labels(provider, event_type, "error").inc()
        logger.error(f"Rundeck trigger failed: {exc}")
        return jsonify(error="Failed to trigger Rundeck job", detail=str(exc)), 502

    webhook_requests.labels(provider, event_type, "success").inc()
    build_triggers.labels(repo["name"], repo["branch"], "triggered").inc()
    execution = (result or {}).get("permalink") or (result or {}).get("id")
    logger.success(f"Triggered build for {repo['full_name']}@{repo['branch']} -> {execution}")
    return jsonify(
        message="Build triggered",
        repository=repo["full_name"],
        branch=repo["branch"],
        reason=reason,
        rundeck_execution=execution,
    ), 200


# --------------------------------------------------------------------------- #
# Routes
# --------------------------------------------------------------------------- #
@app.get("/health")
def health():
    return jsonify(status="healthy", service="webhook-handler", version="1.0.0")


@app.get("/metrics")
def metrics():
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}


@app.get("/")
def index():
    return jsonify(
        service="Talend webhook handler",
        endpoints=["/webhook/github", "/webhook/gitlab", "/webhook/azure-devops", "/health", "/metrics"],
        rundeck_job=f"{RUNDECK_PROJECT}/{RUNDECK_TRIGGER_JOB}",
    )


@app.post("/webhook/github")
@processing_duration.time()
def github_webhook():
    if not verify_signature(request.data, request.headers.get("X-Hub-Signature-256"), "github"):
        webhook_requests.labels("github", "unknown", "unauthorized").inc()
        return jsonify(error="Unauthorized"), 401
    event_type = request.headers.get("X-GitHub-Event", "unknown")
    if event_type != "push":
        webhook_requests.labels("github", event_type, "ignored").inc()
        return jsonify(message=f"Event {event_type} ignored"), 200
    return handle_push("github", request.get_json(silent=True) or {}, event_type)


@app.post("/webhook/gitlab")
@processing_duration.time()
def gitlab_webhook():
    if not verify_signature(request.data, request.headers.get("X-Gitlab-Token"), "gitlab"):
        webhook_requests.labels("gitlab", "unknown", "unauthorized").inc()
        return jsonify(error="Unauthorized"), 401
    payload = request.get_json(silent=True) or {}
    event_type = payload.get("object_kind", "unknown")
    if event_type != "push":
        webhook_requests.labels("gitlab", event_type, "ignored").inc()
        return jsonify(message=f"Event {event_type} ignored"), 200
    return handle_push("gitlab", payload, event_type)


@app.post("/webhook/azure-devops")
@processing_duration.time()
def azure_webhook():
    signature = request.headers.get("X-Hub-Signature-256") or request.headers.get("Signature")
    if not verify_signature(request.data, signature, "azure-devops"):
        webhook_requests.labels("azure-devops", "unknown", "unauthorized").inc()
        return jsonify(error="Unauthorized"), 401
    payload = request.get_json(silent=True) or {}
    event_type = payload.get("eventType", "unknown")
    if event_type != "git.push":
        webhook_requests.labels("azure-devops", event_type, "ignored").inc()
        return jsonify(message=f"Event {event_type} ignored"), 200
    return handle_push("azure-devops", payload, event_type)


if __name__ == "__main__":
    logger.info("Starting Talend webhook handler on :8080")
    app.run(host="0.0.0.0", port=8080)
