# Contributing

Thanks for your interest in Talend_ADMIN! Contributions are welcome — code,
documentation, bug reports and feature ideas alike. By participating you agree
to the [Code of Conduct](CODE_OF_CONDUCT.md).

## Ground rules

- Keep changes focused and small; one concern per pull request.
- No secrets, internal hostnames, IPs or organisation-specific names in commits.
  This project ships only generic placeholders.
- Match the existing style: small single-purpose containers, configuration via
  environment variables, no Kubernetes in the default stack.

## Development setup

```bash
cp .env.example .env
docker compose up -d --build
docker compose logs -f <service>
```

A full reset (deletes all data volumes): `docker compose down -v`.

## Checks (same as CI)

CI runs four checks on every PR — run them locally before pushing:

```bash
# 1. Compose validation
cp -n .env.example .env && docker compose config -q

# 2. Dockerfile lint
docker run --rm -i hadolint/hadolint hadolint \
  --ignore DL3008 --ignore DL3018 --failure-threshold warning - < <(cat */Dockerfile)
# (or: brew install hadolint && hadolint --ignore DL3008 --ignore DL3018 */Dockerfile)

# 3. Shell scripts
shellcheck --severity=warning $(git ls-files '*.sh')

# 4. YAML / Rundeck job definitions
python3 -c "import yaml,glob; [yaml.safe_load(open(p)) for p in glob.glob('**/*.y*ml', recursive=True)]"
```

If you change the runner launcher (`talend-runner/run-talend-job.sh`), verify
the image still builds and the launcher behaves:

```bash
docker build ./talend-runner
```

## Pull requests

1. Fork and branch from `main`.
2. Follow the [PR template](.github/PULL_REQUEST_TEMPLATE.md): describe the
   change and how you tested it.
3. Use conventional commit messages (`feat:`, `fix:`, `docs:`, `ci:`, ...).
4. Update the documentation and `CHANGELOG.md` (under **Unreleased**) for any
   user-visible change.
5. Ensure CI is green.

## Reporting issues

Use the [issue forms](https://github.com/Mbaroudi/Talend_ADMIN/issues/new/choose)
with steps to reproduce, expected vs. actual behaviour, and relevant
`docker compose logs` output (redact any secrets). Security problems go through
[private vulnerability reporting](SECURITY.md) instead.

## Good first contributions

- Items on the [README roadmap](README.md#roadmap)
- Documentation gaps you hit while getting started
- Additional webhook providers, runner examples, Grafana dashboards

## License

By contributing you agree your contributions are licensed under the
[MIT License](LICENSE).
