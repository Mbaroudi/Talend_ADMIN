# Architecture

Talend_ADMIN is a set of small, single-purpose containers wired together with
Docker Compose. Orchestration is delegated to **Rundeck** rather than Airflow,
because the TAC role is fundamentally *job administration* (schedule, trigger,
monitor, RBAC) — exactly what Rundeck does.

## Components

| Component        | Image / build            | Role |
|------------------|--------------------------|------|
| `postgres`       | `postgres:15-alpine`     | Metadata for the platform **and** Rundeck (two databases). |
| `minio`          | `minio/minio`            | S3-compatible artifact & log storage. |
| `nexus`          | `sonatype/nexus3`        | Maven/raw artifact repository. |
| `rundeck`        | `rundeck/rundeck`        | Orchestrator: scheduling, runbooks, ACL, API, UI. |
| `rundeck-bootstrap` | `./rundeck`           | One-shot: provisions the `talend` project, runner node, jobs, ACL. |
| `talend-runner`  | `./talend-runner`        | SSH + JRE execution node Rundeck dispatches job runs to. |
| `talend-builder` | `./builder`              | HTTP build API: git clone → Maven → artifact. |
| `webhook-handler`| `./webhook-handler`      | Git push → trigger the Rundeck build job via API. |
| `tac-platform`   | `./platform`             | Flask portal with links and live service status. |
| `prometheus`     | `prom/prometheus`        | Metrics + alert evaluation. |
| `alertmanager`   | `prom/alertmanager`      | Alert routing / notifications. |
| `grafana`        | `grafana/grafana`        | Dashboards (Prometheus datasource provisioned). |
| `node-exporter`  | `prom/node-exporter`     | Host metrics. |

## Execution model

Rundeck does not run Talend jobs in its own container. Instead:

1. The **builder** compiles a Talend job and writes the runnable artifact to the
   shared `artifacts` volume (`/artifacts/<job>/`), optionally uploading to MinIO.
2. The **runner** mounts the same `artifacts` volume and exposes SSH.
3. A **Rundeck job** targets the `talend-runner` node and runs
   `<job>_run.sh` (or `java -jar <job>.jar`) over SSH.

This mirrors how a real TAC dispatches execution to JobServers/agents, and keeps
the orchestrator decoupled from the Java runtime.

## SSH key provisioning

No private key is committed. On first boot the runner generates an RSA key pair
into the shared `ssh_keys` volume and authorises the public key for the `talend`
user. Rundeck mounts that volume read-only and uses the private key (via its Java
SSH client) to connect. Rotate by deleting the `ssh_keys` volume.

## Authentication to Rundeck

The bootstrap job and the webhook handler authenticate to Rundeck with the admin
credentials (form login → session cookie) and call the REST API — no static API
token has to be pre-seeded. `rundeck/etc/realm.properties` is the source of truth
for the admin password and must match `RUNDECK_ADMIN_PASSWORD` in `.env`.

## Networking

All services share the `tac-net` bridge network and address each other by
service name. Only the UIs and the webhook endpoint are published to the host.
