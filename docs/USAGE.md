# Usage

## 1. Start the stack

```bash
cp .env.example .env   # edit secrets
docker compose up -d --build
```

Wait for `rundeck-bootstrap` to finish (`docker compose logs rundeck-bootstrap`).
It creates the `talend` project, the runner node and the job templates.

## 2. Two builders, two repository layouts

Talend_ADMIN ships **two builders**; pick per build with the `BUILDER` option
(default for webhook-triggered builds: `DEFAULT_BUILDER` in `.env`).

### `BUILDER=tos` — raw Studio project sources (recommended)

The **TOS CI-builder** is a headless Talend Open Studio 8.0.1 (last
open-source release, Apache 2.0) driven entirely from the command line — the
open-source equivalent of the commercial *Talend CI Builder*. It performs the
full **code generation** (`.item` → Java) and packaging.

Your Git repository simply contains what Studio stores in its workspace —
the project folder, versioned as-is:

```
my-repo/
├── talend.project          # project descriptor (name read from technicalLabel)
├── process/                # jobs (.item + .properties)
├── context/
├── metadata/
└── code/routines/
```

No export step, no pom.xml to maintain: push your project, the builder
generates and packages the job.

Notes:

- The Studio (~830 MB) is downloaded **once** at first start into the
  `tos_studio` Docker volume (`TOS_DOWNLOAD_URL`). The image itself stays
  small, no GUI/X11 libraries are installed.
- Job libraries are resolved **on demand**: when the code generator reports a
  missing jar, the builder looks up its Maven coordinates in the Studio's own
  index and fetches it from Maven Central (fallback: Talend's library mirror)
  into the Studio m2, then retries. First build downloads what the job
  actually needs; later builds reuse the cache (persisted in the volume).

### `BUILDER=maven` — Maven project / Studio export

The Maven builder compiles a repo that contains a `pom.xml` producing either:

- a Talend *Build Job* `.zip` under `target/` containing
  `<Job>/<Job>_run.sh`, `lib/` and the job jar (preferred), or
- a runnable `.jar` under `target/`.

This is what Talend Studio's **Build Job → Maven** export produces. Use it
when you version build artifacts/exports rather than raw sources.

## 3. Build & run a job

### From the Rundeck UI
1. Open http://localhost:4440 and log in as `admin`.
2. Project **talend** → **Jobs** → **Build and Deploy Talend Job**.
3. Run with:
   - `GIT_URL` = your repo URL
   - `GIT_BRANCH` = `main`
   - `JOB_NAME` = the job to build/run
   - `BUILDER` = `tos` (raw Studio sources) or `maven` (Maven project/export)
   - `CONTEXT` = `Default`

The job clones, compiles via the builder, then executes the artifact on the
runner. Logs stream in the Rundeck execution view.

### From the API
```bash
curl -u admin:$RUNDECK_ADMIN_PASSWORD \
  -H 'Content-Type: application/json' \
  -X POST "http://localhost:4440/api/41/job/<job-id>/run" \
  -d '{"options":{"GIT_URL":"https://...","GIT_BRANCH":"main","JOB_NAME":"MyJob"}}'
```

### Run a pre-built job directly
Use the **Run Talend Job** template with `JOB_NAME`. It looks the artifact up
under `/artifacts/<JOB_NAME>/`.

## 3b. Execution options (context, params, JVM, runner)

Every job template exposes the same execution options, handled on the runner
by the unified `run-talend-job` launcher:

| Option           | Effect                                                            | Example                          |
|------------------|-------------------------------------------------------------------|----------------------------------|
| `CONTEXT`        | Talend context (`--context=X`)                                    | `Production`                     |
| `CONTEXT_PARAMS` | `key=value` pairs (separated by `;` or newlines), each passed as `--context_param` | `db_host=pg;batch_size=500`      |
| `JVM_OPTS`       | JVM flags for the job process                                     | `-Xms512M -Xmx4G -Duser.timezone=UTC` |
| `JOB_ARGS`       | Extra raw arguments appended verbatim                             | `--stat_port=8888`               |
| `RUNNER_TAG`     | Which runner node(s) to dispatch to (Rundeck node filter by tag)  | `default`, `heavy`               |

Notes:

- **JVM options really apply** even with Talend "Build Job" exports: the
  generated `<Job>_run.sh` hardcodes its own `-Xms/-Xmx`, so the launcher
  rewrites those flags with your `JVM_OPTS` (and also exports
  `JAVA_TOOL_OPTIONS` for nested JVMs).
- **Values containing spaces** work in `CONTEXT_PARAMS` as long as pairs are
  separated by `;` (e.g. `label=Hello World;env=prod`).

### Choosing a runner

Runners are SSH nodes declared in `rundeck/etc/talend-resources.yaml`, each
with capability tags. Jobs select them with `RUNNER_TAG` (default: `default`).
To add a second runner (e.g. a high-memory node targeted with
`RUNNER_TAG=heavy`), uncomment the `talend-runner-xl` examples in
`docker-compose.yml` and `talend-resources.yaml`, then restart Rundeck.

## 4. Build via the builder APIs (without Rundeck)

Both builders expose the same API (`/build`, `/builds`, `/health`, `/metrics`):

```bash
# Maven builder
docker compose exec talend-builder \
  curl -s -X POST http://localhost:8080/build \
  -H 'Content-Type: application/json' \
  -d '{"git_url":"https://...","branch":"main","job_name":"MyJob"}'

# TOS CI-builder (raw Studio sources; first call may 503 while the one-time
# Studio download is still running — check "studio_ready" on /health)
docker compose exec tos-builder \
  curl -s -X POST http://localhost:8080/build \
  -H 'Content-Type: application/json' \
  -d '{"git_url":"https://...","branch":"main","job_name":"MyJob"}'
```

## 5. Schedule a job

Enable the **Scheduled Talend Pipeline** job in Rundeck (schedule is disabled by
default), or add a schedule to any job from the UI.

## 6. Trigger from Git

Configure a webhook (see the README table) with `WEBHOOK_SECRET`. Pushes that
touch Talend files on an allowed branch trigger the build-and-deploy job.
