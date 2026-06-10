<!-- Thanks for contributing! Keep PRs focused: one concern per pull request. -->

## What

<!-- What does this PR change, and why? Link related issues: Fixes #123 -->

## How was it tested

<!-- e.g. `docker compose up -d --build` + ran "Run Talend Job" with CONTEXT=Test -->

- [ ] `docker compose config -q` passes
- [ ] The stack starts cleanly (`docker compose up -d --build`)
- [ ] CI checks pass (hadolint, shellcheck, YAML/job validation)

## Checklist

- [ ] No secrets, internal hostnames or organisation-specific names
- [ ] Documentation updated if behaviour or configuration changed
- [ ] `CHANGELOG.md` updated under **Unreleased** (user-visible changes)
