#!/usr/bin/env python3
"""Talend CI builder — minimal synchronous HTTP build API.

POST /build {"git_url", "job_name", "branch"} clones the repo, runs the Maven
build and publishes the runnable artifact under /artifacts/<job_name>/.
"""
import datetime
import os
import subprocess
import threading
import uuid
from collections import deque

from flask import Flask, jsonify, request
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

app = Flask(__name__)

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "scripts", "build-talend-job.sh")
BUILD_TIMEOUT_SECONDS = 1800

BUILDS = deque(maxlen=50)
LOCK = threading.Lock()

builds_total = Counter("talend_builds_total", "Total Talend builds", ["status"])
build_duration = Histogram("talend_build_duration_seconds", "Talend build duration")


@app.get("/health")
def health():
    return jsonify(status="healthy", service="talend-builder", version="1.0.0")


@app.get("/metrics")
def metrics():
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}


@app.get("/builds")
def list_builds():
    with LOCK:
        return jsonify(builds=list(BUILDS), total=len(BUILDS))


@app.post("/build")
def build():
    data = request.get_json(silent=True) or {}
    git_url = data.get("git_url")
    job_name = data.get("job_name")
    branch = data.get("branch", "main")

    if not git_url or not job_name:
        return jsonify(error="git_url and job_name are required"), 400

    record = {
        "id": uuid.uuid4().hex[:12],
        "job_name": job_name,
        "git_url": git_url,
        "branch": branch,
        "started": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }

    try:
        with build_duration.time():
            proc = subprocess.run(
                [SCRIPT, git_url, branch, job_name],
                capture_output=True,
                text=True,
                timeout=BUILD_TIMEOUT_SECONDS,
            )
        ok = proc.returncode == 0
        record["status"] = "success" if ok else "failed"
        record["returncode"] = proc.returncode
        stdout_tail, stderr_tail = proc.stdout[-4000:], proc.stderr[-4000:]
    except subprocess.TimeoutExpired:
        ok = False
        record["status"] = "timeout"
        record["returncode"] = -1
        stdout_tail, stderr_tail = "", f"Build exceeded {BUILD_TIMEOUT_SECONDS}s"

    builds_total.labels(status=record["status"]).inc()
    with LOCK:
        BUILDS.appendleft(record)

    return jsonify({**record, "stdout_tail": stdout_tail, "stderr_tail": stderr_tail}), (200 if ok else 500)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
