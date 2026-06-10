# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- **TOS CI-builder**: build runnable Talend jobs from **raw Studio project
  sources** (`talend.project` + `.item`) — the open-source equivalent of the
  commercial Talend CI Builder. Talend never open-sourced its CommandLine
  plugin, so the builder compiles its own small headless Eclipse application
  (`org.talendadmin.cibuilder`) against the Studio's Apache-2.0 plugins at
  provisioning time, then drives logon → code generation → build → zip
  through a plain JVM: no GUI, no GTK/X11 libraries. The Studio 8.0.1
  (~830 MB, last open-source release) is downloaded once into the
  `tos_studio` volume; job libraries are resolved on demand from Maven
  Central into the Studio m2 (cached in the same volume).
- `BUILDER` option (`maven` | `tos`) on the **Build and Deploy Talend Job**
  template, and `DEFAULT_BUILDER` env for webhook-triggered builds.
- Manual library provisioning for jars Maven cannot resolve (proprietary
  drivers, internal SDKs): `POST /libs` upload endpoint and the
  `tos_custom_libs` volume (`/custom-libs`), installed into the Studio m2
  with the Studio's jar→Maven mapping and consulted before any remote
  download.
- Git guide for Talend projects (`docs/TALEND-PROJECT-GIT.md`) and a
  ready-made `.gitignore` (`examples/talend-project/`) excluding everything
  the Studio regenerates (`poms/`, `.Java/`, `.JETEmitters/`, `.metadata/`,
  Eclipse descriptors, logs, `temp/`).

- Working demo project (`examples/talend-project/demo/`): project `DEMO`
  with a single-tJava `HelloWorld` job (contexts `Default`/`Production`,
  `greeting` context parameter). Validated end-to-end: signed push webhook →
  Rundeck → TOS build from raw sources → SSH run, plus `CONTEXT` switching
  and `CONTEXT_PARAMS` overrides — all executions SUCCEEDED.

### Fixed

Found by running the full push→build→deploy chain end-to-end (webhook →
Rundeck → TOS build → SSH run):

- Rundeck authentication followed the post-login redirect to
  `RUNDECK_GRAILS_URL` (a public URL unreachable from inside containers) —
  the bootstrap and the webhook handler now keep the session cookie from the
  302 itself.
- `run-talend-job` could not find launchers nested one level inside the
  artifact (`<JOB>/<JOB>/<JOB>_run.sh`, the layout Talend zips produce).
- The JVM-options patching wrote the patched launcher to `/tmp`, breaking
  the relative classpath of Talend `_run.sh` scripts (`cd $(dirname $0)`);
  it now runs the patched content in-place via `bash -c` with `$0` set to
  the original script — no file written at all.
- `java` was not on the PATH of Rundeck's SSH sessions on runner nodes
  (Docker ENV is not inherited over SSH) — now symlinked into
  `/usr/local/bin`.
- Artifacts written by the builders (root) were not writable by the runner's
  SSH user; both builders now `chmod -R a+rwX` the artifact tree.
- Accented characters in context parameters and job output were mangled:
  SSH sessions had no UTF-8 locale and the job JVM no `-Dfile.encoding`;
  `run-talend-job` now forces `C.UTF-8` + `-Dfile.encoding=UTF-8`.

## [0.1.0] - 2026-06-10

Initial public release.

### Added

- Full Docker Compose stack: Rundeck (orchestrator), Talend builder
  (git → Maven → artifact), SSH runner nodes, webhook handler
  (GitHub/GitLab/Azure DevOps), Flask portal, MinIO, Nexus, PostgreSQL and a
  Prometheus / Grafana / Alertmanager monitoring stack.
- Three pre-provisioned Rundeck job templates: **Run Talend Job**,
  **Build and Deploy Talend Job**, **Scheduled Talend Pipeline**.
- Talend-aware execution options on every template: `CONTEXT`,
  `CONTEXT_PARAMS` (`--context_param` pairs), `JVM_OPTS`, `JOB_ARGS` and
  `RUNNER_TAG` (runner selection by node tag).
- Unified `run-talend-job` launcher on runner nodes: artifact lookup, context
  handling, JVM flag rewriting for Talend `_run.sh` exports, exit-code
  propagation.
- Idempotent provisioning (fixed job UUIDs), runtime-generated SSH keys, no
  committed secrets.
- CI: hadolint, shellcheck, compose validation, Rundeck job definition checks.
- Documentation: architecture, usage, configuration reference,
  troubleshooting; issue templates and contribution guidelines.

[Unreleased]: https://github.com/Mbaroudi/Talend_ADMIN/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Mbaroudi/Talend_ADMIN/releases/tag/v0.1.0
