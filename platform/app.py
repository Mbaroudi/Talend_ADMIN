#!/usr/bin/env python3
"""Talend_ADMIN — unified portal.

A small Flask app that lists the platform services, shows a live status
indicator for each, and links out to their UIs (Rundeck, MinIO, Nexus,
Grafana, Prometheus). Orchestration is handled by Rundeck.
"""
import os
from datetime import datetime, timezone

import requests
from flask import Flask, jsonify, render_template

app = Flask(__name__)
app.config["SECRET_KEY"] = os.getenv("TAC_PLATFORM_SECRET_KEY", "change-me")

# Public URLs are what the browser links to; internal URLs are used in-cluster
# for the health probes.
RUNDECK_PUBLIC = os.getenv("RUNDECK_PUBLIC_URL", "http://localhost:4440")
MINIO_CONSOLE_PUBLIC = os.getenv("MINIO_CONSOLE_PUBLIC_URL", "http://localhost:9001")
NEXUS_PUBLIC = os.getenv("NEXUS_PUBLIC_URL", "http://localhost:8081")
GRAFANA_PUBLIC = os.getenv("GRAFANA_PUBLIC_URL", "http://localhost:3000")
PROMETHEUS_PUBLIC = os.getenv("PROMETHEUS_PUBLIC_URL", "http://localhost:9090")
WEBHOOK_PUBLIC = os.getenv("WEBHOOK_PUBLIC_URL", "http://localhost:8088")
RUNDECK_INTERNAL = os.getenv("RUNDECK_INTERNAL_URL", "http://rundeck:4440")

# id -> (display, description, category, public_url, health_url|None)
SERVICES = {
    "rundeck": {
        "name": "Rundeck Orchestrator",
        "description": "Schedule, trigger and monitor Talend job execution.",
        "icon": "fa-diagram-project",
        "category": "orchestration",
        "url": RUNDECK_PUBLIC,
        "health_url": f"{RUNDECK_INTERNAL}/",
    },
    "builder": {
        "name": "Talend Builder",
        "description": "Compiles Talend jobs from Git into runnable artifacts.",
        "icon": "fa-hammer",
        "category": "ci-cd",
        "url": None,
        "health_url": "http://talend-builder:8080/health",
    },
    "webhook": {
        "name": "Webhook Handler",
        "description": "Turns Git pushes into Rundeck-driven builds.",
        "icon": "fa-code-branch",
        "category": "ci-cd",
        "url": WEBHOOK_PUBLIC,
        "health_url": "http://webhook-handler:8080/health",
    },
    "minio": {
        "name": "MinIO Storage",
        "description": "S3-compatible artifact and log storage.",
        "icon": "fa-database",
        "category": "storage",
        "url": MINIO_CONSOLE_PUBLIC,
        "health_url": "http://minio:9000/minio/health/live",
    },
    "nexus": {
        "name": "Nexus Repository",
        "description": "Maven/raw repository for compiled jobs.",
        "icon": "fa-box-archive",
        "category": "storage",
        "url": NEXUS_PUBLIC,
        "health_url": "http://nexus:8081/",
    },
    "prometheus": {
        "name": "Prometheus",
        "description": "Metrics collection and alert evaluation.",
        "icon": "fa-chart-line",
        "category": "monitoring",
        "url": PROMETHEUS_PUBLIC,
        "health_url": "http://prometheus:9090/-/healthy",
    },
    "grafana": {
        "name": "Grafana",
        "description": "Dashboards for platform and job metrics.",
        "icon": "fa-chart-area",
        "category": "monitoring",
        "url": GRAFANA_PUBLIC,
        "health_url": "http://grafana:3000/api/health",
    },
    "alertmanager": {
        "name": "Alertmanager",
        "description": "Alert routing and notifications.",
        "icon": "fa-bell",
        "category": "monitoring",
        "url": os.getenv("ALERTMANAGER_PUBLIC_URL", "http://localhost:9093"),
        "health_url": "http://alertmanager:9093/-/healthy",
    },
}

CATEGORIES = {
    "orchestration": "Orchestration",
    "ci-cd": "CI / CD",
    "storage": "Storage & Artifacts",
    "monitoring": "Monitoring & Observability",
}


def probe(health_url):
    if not health_url:
        return "unknown"
    try:
        resp = requests.get(health_url, timeout=2)
        return "active" if resp.status_code < 500 else "inactive"
    except requests.RequestException:
        return "inactive"


@app.route("/")
def index():
    services = {sid: {**s, "status": probe(s["health_url"])} for sid, s in SERVICES.items()}
    return render_template("index.html", services=services, categories=CATEGORIES)


@app.route("/api/services/status")
def services_status():
    return jsonify({
        sid: {"name": s["name"], "status": probe(s["health_url"]), "url": s["url"]}
        for sid, s in SERVICES.items()
    })


@app.route("/health")
def health():
    return jsonify(
        status="healthy",
        service="tac-platform",
        version="1.0.0",
        timestamp=datetime.now(timezone.utc).isoformat(),
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8089)
