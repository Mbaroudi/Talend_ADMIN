# Configuration reference

All runtime configuration lives in `.env` (copied from `.env.example`).
A few behaviours are configured through mounted files, listed at the end.

## Environment variables

### PostgreSQL

| Variable | Default | Description |
|----------|---------|-------------|
| `POSTGRES_USER` | `tac` | Superuser for the shared PostgreSQL instance. Also used by Rundeck to connect to its own database. |
| `POSTGRES_PASSWORD` | `change-me-postgres` | Password for `POSTGRES_USER`. |
| `POSTGRES_DB` | `tac` | Platform metadata database. |
| `RUNDECK_DB_NAME` | `rundeck` | Second database, created automatically by `storage/postgres-init.sh` on first boot. |

### MinIO (artifact storage)

| Variable | Default | Description |
|----------|---------|-------------|
| `MINIO_ROOT_USER` | `tacadmin` | MinIO root account (console + S3 API). |
| `MINIO_ROOT_PASSWORD` | `change-me-minio` | MinIO root password (min. 8 characters). |
| `MINIO_BUCKET_JOBS` | `talend-jobs` | Bucket the builder uploads compiled artifacts to. Created by `minio-init`. |
| `MINIO_BUCKET_LOGS` | `talend-logs` | Bucket reserved for job log shipping. Created by `minio-init`. |

### Rundeck (orchestrator)

| Variable | Default | Description |
|----------|---------|-------------|
| `RUNDECK_ADMIN_USER` | `admin` | Admin login. Used by the bootstrap container and the webhook handler to call the Rundeck API. |
| `RUNDECK_ADMIN_PASSWORD` | `change-me-rundeck` | Admin password. **Must match the `admin` line in `rundeck/etc/realm.properties`** — Rundeck reads the file, everything else reads the variable. |
| `RUNDECK_GRAILS_URL` | `http://localhost:4440` | External URL Rundeck uses to build links (UI redirects, emails). Match your published host/port or reverse-proxy URL. |

### TAC Platform (Flask portal)

| Variable | Default | Description |
|----------|---------|-------------|
| `TAC_PLATFORM_SECRET_KEY` | `change-me-flask-secret` | Flask session signing key. |
| `RUNDECK_PUBLIC_URL` | `http://localhost:4440` | Link target for the Rundeck tile. |
| `MINIO_CONSOLE_PUBLIC_URL` | `http://localhost:9001` | Link target for the MinIO tile. |
| `NEXUS_PUBLIC_URL` | `http://localhost:8081` | Link target for the Nexus tile. |
| `GRAFANA_PUBLIC_URL` | `http://localhost:3000` | Link target for the Grafana tile. |
| `PROMETHEUS_PUBLIC_URL` | `http://localhost:9090` | Link target for the Prometheus tile. |

The `*_PUBLIC_URL` variables are what a **browser** can reach (host ports or
your reverse-proxy hostnames) — not the internal Docker service names.

### TOS CI-builder (headless Studio)

| Variable | Default | Description |
|----------|---------|-------------|
| `TOS_DOWNLOAD_URL` | archive.org mirror of `TOS_DI-…-V8.0.1.zip` | Where the last open-source Talend Studio release is fetched from, once, into the `tos_studio` volume. Point it at an internal mirror for air-gapped setups. |
| `TOS_BUILDER_HEAP` | `2048m` | JVM heap for headless code generation/build (`-Xmx`). |

### Webhook handler

| Variable | Default | Description |
|----------|---------|-------------|
| `WEBHOOK_SECRET` | `change-me-webhook-secret` | Shared secret verifying webhook signatures (GitHub HMAC, GitLab token, Azure DevOps signature). |
| `RUNDECK_PROJECT` | `talend` | Rundeck project containing the job to trigger. |
| `RUNDECK_TRIGGER_JOB` | `Build and Deploy Talend Job` | Name of the Rundeck job triggered on push. |
| `DEFAULT_BUILDER` | `maven` | Builder used for webhook-triggered builds: `maven` (Maven project/export in the repo) or `tos` (raw Studio sources). |

### Grafana

| Variable | Default | Description |
|----------|---------|-------------|
| `GRAFANA_ADMIN_USER` | `admin` | Grafana admin login. |
| `GRAFANA_ADMIN_PASSWORD` | `change-me-grafana` | Grafana admin password. |

### Talend runner

| Variable | Default | Description |
|----------|---------|-------------|
| `TALEND_RUNNER_USER` | `talend` | SSH user Rundeck connects as on runner nodes. |

## Per-execution options (Rundeck job options)

These are not `.env` variables — they are set per run in the Rundeck UI/API
and consumed by the `run-talend-job` launcher on the runner:

| Option | Maps to | Example |
|--------|---------|---------|
| `BUILDER` | which builder compiles the repo (build job only) | `maven`, `tos` |
| `CONTEXT` | `--context=X` | `Production` |
| `CONTEXT_PARAMS` | repeated `--context_param key=value` | `db_host=pg;batch_size=500` |
| `JVM_OPTS` | JVM flags of the job process (rewrites the hardcoded `-Xms/-Xmx` of Talend `_run.sh` launchers) | `-Xms512M -Xmx4G` |
| `JOB_ARGS` | raw arguments appended verbatim | `--stat_port=8888` |
| `RUNNER_TAG` | Rundeck node filter `tags: <value>` | `default`, `heavy` |

See [USAGE.md](USAGE.md#3b-execution-options-context-params-jvm-runner).

## Configuration files

| File | Mounted into | Purpose |
|------|--------------|---------|
| `rundeck/etc/realm.properties` | `rundeck` | Rundeck users/passwords/roles (Jetty realm). Source of truth for the admin password. |
| `rundeck/etc/talend-resources.yaml` | `rundeck` | Node inventory: runner nodes, SSH settings, capability tags. Add runners here. |
| `rundeck/acl/operator.aclpolicy` | imported by bootstrap | Example ACL for a non-admin operator role. |
| `rundeck/projects/talend/jobs/talend-jobs.yaml` | imported by bootstrap | The three job templates (fixed UUIDs, idempotent re-import). |
| `storage/postgres-init.sh` | `postgres` (initdb) | Creates the Rundeck database on first boot. |
| `storage/minio-init.sh` | `minio-init` | Creates the artifact/log buckets. |
| `monitoring/prometheus/prometheus.yml` | `prometheus` | Scrape configuration. |
| `monitoring/prometheus/alert_rules.yml` | `prometheus` | Alerting rules (service down, disk, CPU). |
| `monitoring/alertmanager/alertmanager.yml` | `alertmanager` | Alert routing — plug your Slack/email receivers here. |
| `monitoring/grafana/provisioning/` | `grafana` | Datasource + dashboard auto-provisioning. |

## Changing the admin password (checklist)

1. Edit `RUNDECK_ADMIN_PASSWORD` in `.env`.
2. Edit the `admin:` line in `rundeck/etc/realm.properties` to the same value.
3. `docker compose up -d --force-recreate rundeck rundeck-bootstrap webhook-handler`
