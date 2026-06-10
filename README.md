# Talend_ADMIN

**An open-source alternative to Talend Administration Center (TAC).**
Build, schedule, trigger and monitor Talend jobs — orchestrated by **Rundeck**,
running entirely on **Docker** (no Kubernetes required).

> Talend is a trademark of Talend / Qlik. This is an independent,
> community-maintained project and is not affiliated with Talend.

---

## Why

Talend Administration Center is a commercial product. Talend_ADMIN replaces its
core job-administration role with proven open-source building blocks:

- **Rundeck** as the orchestrator — scheduling (cron), manual run, RBAC/ACL, a
  web UI, a REST API and notifications. This is the actual job of a TAC.
- A **Talend builder** that compiles jobs from Git into runnable artifacts.
- A **Git webhook handler** that turns a push into a build + run.
- **MinIO** + **Nexus** for artifact storage, **PostgreSQL** for metadata,
  and a **Prometheus / Grafana / Alertmanager** monitoring stack.

## Architecture

```
                ┌────────────────────────────┐
   Browser ───► │  TAC Platform (Flask :8089) │  unified portal / status
                └────────────┬───────────────┘
                             │ links to
        ┌────────────────────┼─────────────────────────────┐
        ▼                    ▼                              ▼
 ┌──────────────┐     ┌──────────────┐              ┌───────────────┐
 │   Rundeck    │     │    MinIO     │              │    Grafana    │
 │  :4440 (UI)  │     │ :9000/:9001  │              │     :3000     │
 │ orchestrator │     │  artifacts   │              │  dashboards   │
 └──────┬───────┘     └──────────────┘              └──────┬────────┘
        │ SSH (key)                                        │ scrape
        ▼                                                  ▼
 ┌──────────────┐     ┌──────────────┐   build   ┌───────────────────┐
 │ talend-runner│◄────│ talend-builder│──────────►│    Prometheus     │
 │  JRE + jobs  │     │  git → maven  │  artifacts│   + Alertmanager   │
 └──────────────┘     └──────▲───────┘  (shared   └───────────────────┘
        ▲                    │ volume)
        │ run job (API)      │ POST /build
 ┌──────┴───────┐     ┌──────┴───────┐
 │   Rundeck    │◄────│   webhook    │◄──── Git push (GitHub/GitLab/Azure DevOps)
 │     job      │     │   handler    │
 └──────────────┘     └──────────────┘
```

The compiled artifact lands in a Docker volume shared by the builder and the
runner, so a job built by the builder is immediately runnable by Rundeck.

## Quick start

```bash
git clone https://github.com/Mbaroudi/Talend_ADMIN.git
cd Talend_ADMIN

cp .env.example .env
#   IMPORTANT: edit .env and change every secret.
#   Keep RUNDECK_ADMIN_PASSWORD in sync with rundeck/etc/realm.properties.

docker compose up -d --build
```

First start pulls images and compiles the builder/runner images (a few
minutes). The `rundeck-bootstrap` container provisions the `talend` project,
the runner node and the job templates, then exits.

Open the portal: **http://localhost:8089**

## Services & ports

| Service          | URL                       | Default credentials            |
|------------------|---------------------------|--------------------------------|
| TAC Platform     | http://localhost:8089     | —                              |
| Rundeck          | http://localhost:4440     | `admin` / `RUNDECK_ADMIN_PASSWORD` |
| MinIO Console    | http://localhost:9001     | `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` |
| Nexus            | http://localhost:8081     | `admin` / (see `nexus-data/admin.password`) |
| Grafana          | http://localhost:3000     | `admin` / `GRAFANA_ADMIN_PASSWORD` |
| Prometheus       | http://localhost:9090     | —                              |
| Alertmanager     | http://localhost:9093     | —                              |
| Webhook handler  | http://localhost:8088     | —                              |

All credentials are placeholders in `.env.example`. **Change them.**

## Orchestrating Talend jobs

Three job templates are pre-loaded into the Rundeck `talend` project:

- **Run Talend Job** — run an already-built job.
- **Build and Deploy Talend Job** — clone from Git, compile, then run.
- **Scheduled Talend Pipeline** — example nightly job (schedule disabled by
  default; enable it in the UI).

Every template exposes Talend-aware execution options:

| Option           | Purpose                                                  |
|------------------|----------------------------------------------------------|
| `CONTEXT`        | Talend context (`--context=X`)                           |
| `CONTEXT_PARAMS` | `key=value` pairs passed as `--context_param`            |
| `JVM_OPTS`       | JVM flags (`-Xms/-Xmx`, GC, `-D...`) for the job process |
| `JOB_ARGS`       | Extra raw arguments                                      |
| `RUNNER_TAG`     | Which runner node(s) to dispatch to, by tag              |

Jobs execute over SSH on runner nodes selected by tag (scale out by adding
runner services/nodes — see the commented `talend-runner-xl` examples) and look
up artifacts under `/artifacts/<JOB_NAME>/`. See
[`docs/USAGE.md`](docs/USAGE.md) for the expected Talend project layout and a
full walkthrough.

## CI/CD from Git

Point a repository webhook at the handler:

| Provider     | URL                                          | Secret header            |
|--------------|----------------------------------------------|--------------------------|
| GitHub       | `http://<host>:8088/webhook/github`          | `X-Hub-Signature-256`    |
| GitLab       | `http://<host>:8088/webhook/gitlab`          | `X-Gitlab-Token`         |
| Azure DevOps | `http://<host>:8088/webhook/azure-devops`    | `Signature`              |

Use `WEBHOOK_SECRET` from `.env` as the shared secret. On a push that touches
Talend files (`*.item`, `*.properties`, `routines/`, `contexts/`) on an allowed
branch, the handler triggers the **Build and Deploy Talend Job** in Rundeck.

## Configuration

All configuration is via `.env` (see `.env.example` for the full list).
No secrets are committed; the SSH key used between Rundeck and the runner is
generated at runtime into a Docker volume.

## Security notes

- This is a starter template: every default secret **must** be changed before
  any non-local use.
- The Rundeck admin password lives in `rundeck/etc/realm.properties` (the source
  of truth Rundeck reads at boot) and must match `RUNDECK_ADMIN_PASSWORD`.
- Put the stack behind a reverse proxy with TLS for anything beyond localhost.

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — components and data flow
- [`docs/USAGE.md`](docs/USAGE.md) — running and building Talend jobs
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — how to contribute

## License

[MIT](LICENSE).
