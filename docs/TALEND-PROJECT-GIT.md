# Managing a Talend project in Git

How to version Talend Studio sources so that a `git push` ends in a built,
runnable job — without dragging the Studio's temporary files along.

## 1. One-time setup

Talend Open Studio stores a project as a plain folder inside its workspace
(`<workspace>/<PROJECT_NAME>/`). That folder **is** your source tree:

```bash
cd <workspace>/MY_PROJECT
git init -b main
curl -fsSL -o .gitignore \
  https://raw.githubusercontent.com/Mbaroudi/Talend_ADMIN/main/examples/talend-project/.gitignore
git add -A && git commit -m "feat: initial Talend project import"
git remote add origin <your-repo-url>
git push -u origin main
```

> Two equally valid layouts: the project at the **repo root** (above,
> recommended) or as a single sub-directory of the repo. The TOS builder
> detects `talend.project` in both cases.

## 2. What gets versioned, what never should

Version what you author; ignore what the Studio regenerates:

| Commit | Never commit | Why |
|--------|--------------|-----|
| `talend.project` | `poms/` | Maven structure, fully rebuilt at every logon/build |
| `process/` (jobs `.item`/`.properties`) | `.Java/`, `.JETEmitters/` | code-generation working projects |
| `context/`, `metadata/` | `.metadata/` | Eclipse workspace internals |
| `code/routines/` | `.project`, `.classpath` | Eclipse descriptors, recreated on import |
| `.settings/` (project settings) | `migration.log`, `lastGenerated.log`, `temp/` | logs & scratch |

The ready-made [`.gitignore`](../examples/talend-project/.gitignore) covers
all of it. Optional: also ignore `*.screenshot` (binary, regenerated on save,
only used for generated documentation) to keep diffs clean.

## 3. Day-to-day workflow

1. Edit and **save** your jobs in the Studio.
2. Commit from the project folder — the `.gitignore` keeps the noise out:
   ```bash
   git add -A && git commit -m "feat: add daily sales aggregation job" && git push
   ```
3. The push hits the [webhook handler](../README.md#cicd-from-git), which
   triggers **Build and Deploy Talend Job** in Rundeck (`BUILDER=tos` via
   `DEFAULT_BUILDER` builds straight from these sources).

Manual trigger (UI or API) works the same — `GIT_URL` + `JOB_NAME`.

## 4. Conventions that keep things sane

- **One project per repository.** The builder logs on one project per build;
  webhooks use the repo name as default `JOB_NAME` (customize in
  `webhook-handler/webhook_handler.py`).
- **Environments are contexts, not branches.** Create `Default`/`Test`/
  `Production` context groups in the Studio and pick at run time with the
  `CONTEXT` / `CONTEXT_PARAMS` options. Branches are for code lifecycle
  (`main`, `develop`, `feature/*` — the webhook's allowed-branch list).
- **Don't hand-edit `.item`/`.properties` files.** They are EMF/XMI documents;
  let the Studio write them.
- **Avoid two people editing the same job in parallel.** XMI files merge
  poorly; treat a job like a binary asset (coordinate, or split flows into
  smaller jobs/joblets).
- **Bump job versions in the Studio** (0.1 → 0.2) for traceability; the
  builder always builds the latest version unless told otherwise.

## 5. Migrating an existing project

Older Studio export (`.zip` of a project) or another workspace:

1. In a fresh Studio workspace: **Import existing project**.
2. Open it once (migrations tasks run, `talend.project` is updated).
3. Then do the [one-time setup](#1-one-time-setup) on the resulting folder.

The TOS builder replays the same migration tasks headlessly at logon, so
projects created with Studio 7.x/8.x build fine.
