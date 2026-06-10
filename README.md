# Talend_ADMIN

[![CI](https://github.com/Mbaroudi/Talend_ADMIN/actions/workflows/ci.yml/badge.svg)](https://github.com/Mbaroudi/Talend_ADMIN/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Docker Compose](https://img.shields.io/badge/docker-compose-2496ED?logo=docker&logoColor=white)](docker-compose.yml)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

**An open-source alternative to Talend Administration Center (TAC).**
Build, schedule, trigger and monitor Talend jobs — orchestrated by **Rundeck**,
running entirely on **Docker** (no Kubernetes required).

> Talend is a trademark of Talend / Qlik. This is an independent,
> community-maintained project and is not affiliated with Talend.

---

- [Why](#why)
- [Architecture](#architecture)
- [Quick start](#quick-start)
- [Services & ports](#services--ports)
- [Orchestrating Talend jobs](#orchestrating-talend-jobs)
- [CI/CD from Git](#cicd-from-git)
- [Configuration](#configuration)
- [Security notes](#security-notes)
- [Documentation](#documentation)
- [Roadmap](#roadmap)
- [Contributing & community](#contributing--community)

## Why

Talend Administration Center is a commercial product. Talend_ADMIN replaces its
core job-administration role with proven open-source building blocks:

- **Rundeck** as the orchestrator — scheduling (cron), manual run, RBAC/ACL, a
  web UI, a REST API and notifications. This is the actual job of a TAC.
- A **Talend builder** that compiles jobs from Git into runnable artifacts.
- A **Git webhook handler** that turns a push into a build + run.
- **MinIO** + **Nexus** for artifact storage, **PostgreSQL** for metadata,
  and a **Prometheus / Grafana / Alertmanager** monitoring stack.

| TAC capability                | Talend_ADMIN equivalent                          |
|-------------------------------|--------------------------------------------------|
| Job Conductor (schedule, run) | Rundeck jobs + cron schedules                    |
| Execution servers (JobServer) | SSH runner nodes, selected by tag                |
| Execution contexts            | `CONTEXT` / `CONTEXT_PARAMS` job options         |
| JVM parameters per execution  | `JVM_OPTS` job option                            |
| **CI Builder** (build from sources) | **TOS CI-builder**: headless Talend Open Studio 8.0.1, full code generation from raw `.item` sources, no GUI |
| Publish from Studio/CI        | Git push → webhook → build → artifact            |
| Monitoring & history          | Rundeck execution log + Prometheus/Grafana       |
| Users / rights                | Rundeck RBAC (realm + ACL policies)              |

The TOS CI-builder is the missing piece most "open-source TAC" attempts skip:
it turns **raw Studio project sources** (what your team versions in Git) into
runnable artifacts — code generation included — using the last open-source
Studio release driven entirely from the command line. The Studio (~830 MB) is
fetched once into a Docker volume; job libraries are resolved by Maven on
demand. No license, no GUI, no manual export step.

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
Details: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Quick start

Prerequisites: Docker Engine 24+ (or Docker Desktop) with the Compose plugin.

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

All configuration is via `.env` — see
[`docs/CONFIGURATION.md`](docs/CONFIGURATION.md) for the full variable
reference and the per-service configuration files. No secrets are committed;
the SSH key used between Rundeck and the runner is generated at runtime into a
Docker volume.

## Security notes

- This is a starter template: every default secret **must** be changed before
  any non-local use.
- The Rundeck admin password lives in `rundeck/etc/realm.properties` (the source
  of truth Rundeck reads at boot) and must match `RUNDECK_ADMIN_PASSWORD`.
- Put the stack behind a reverse proxy with TLS for anything beyond localhost.
- To report a vulnerability, see [`SECURITY.md`](SECURITY.md).

## Documentation

| Document | Contents |
|----------|----------|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Components, execution model, SSH provisioning, networking |
| [`docs/USAGE.md`](docs/USAGE.md) | Building & running jobs, contexts, JVM options, runner selection, scheduling, webhooks |
| [`docs/CONFIGURATION.md`](docs/CONFIGURATION.md) | Every `.env` variable and configuration file explained |
| [`docs/TALEND-PROJECT-GIT.md`](docs/TALEND-PROJECT-GIT.md) | Versioning a Talend project in Git: layout, `.gitignore`, workflow |
| [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) | Common problems and how to diagnose them |
| [`examples/talend-project/`](examples/talend-project/README.md) | Raw Studio sources repository layout + ready-made `.gitignore` |
| [`examples/talend-jobs/`](examples/talend-jobs/README.md) | Maven project / Studio export repository layout |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | Development setup, checks, pull requests |
| [`CHANGELOG.md`](CHANGELOG.md) | Release history |

## Roadmap

Planned / open for contribution (see the
[issues](https://github.com/Mbaroudi/Talend_ADMIN/issues)):

- [ ] Rundeck job metrics exported to Prometheus (success rate, duration)
- [ ] Job log shipping to MinIO (`talend-logs` bucket)
- [ ] Optional LDAP authentication for Rundeck
- [ ] Helm chart for Kubernetes deployments
- [ ] Example Talend job repository (buildable end-to-end demo)
- [ ] Bitbucket webhook support

## Contributing & community

Contributions are welcome — read [`CONTRIBUTING.md`](CONTRIBUTING.md) and the
[`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md), then pick an issue or open one.

- **Bugs / features** → [GitHub issues](https://github.com/Mbaroudi/Talend_ADMIN/issues)
- **Questions / ideas** → [GitHub discussions](https://github.com/Mbaroudi/Talend_ADMIN/discussions)

If this project is useful to you, a ⭐ helps others find it.

## License

[MIT](LICENSE).
