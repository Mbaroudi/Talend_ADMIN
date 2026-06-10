# Usage

## 1. Start the stack

```bash
cp .env.example .env   # edit secrets
docker compose up -d --build
```

Wait for `rundeck-bootstrap` to finish (`docker compose logs rundeck-bootstrap`).
It creates the `talend` project, the runner node and the job templates.

## 2. Expected Talend project layout

The builder compiles a **Maven-based Talend job export**. Your Git repository
should contain a Maven project (a `pom.xml`) that produces either:

- a Talend *Build Job* `.zip` under `target/` containing
  `<Job>/<Job>_run.sh`, `lib/` and the job jar (preferred), or
- a runnable `.jar` under `target/`.

This is what Talend Studio's **Build Job → Maven** export produces, and what the
Talend CI/Maven plugin generates in CI.

## 3. Build & run a job

### From the Rundeck UI
1. Open http://localhost:4440 and log in as `admin`.
2. Project **talend** → **Jobs** → **Build and Deploy Talend Job**.
3. Run with:
   - `GIT_URL` = your repo URL
   - `GIT_BRANCH` = `main`
   - `JOB_NAME` = the job to build/run
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
Use the **Run Talend Job** template with `JOB_NAME` (and optional `CONTEXT`,
`JOB_ARGS`). It looks the artifact up under `/artifacts/<JOB_NAME>/`.

## 4. Build via the builder API (without Rundeck)

```bash
docker compose exec talend-builder \
  curl -s -X POST http://localhost:8080/build \
  -H 'Content-Type: application/json' \
  -d '{"git_url":"https://...","branch":"main","job_name":"MyJob"}'
```

Build history: `GET http://talend-builder:8080/builds` (in-cluster).

## 5. Schedule a job

Enable the **Scheduled Talend Pipeline** job in Rundeck (schedule is disabled by
default), or add a schedule to any job from the UI.

## 6. Trigger from Git

Configure a webhook (see the README table) with `WEBHOOK_SECRET`. Pushes that
touch Talend files on an allowed branch trigger the build-and-deploy job.
