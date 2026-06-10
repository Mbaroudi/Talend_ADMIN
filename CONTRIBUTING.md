# Contributing

Thanks for your interest in Talend_ADMIN! Contributions are welcome.

## Ground rules

- Keep changes focused and small; one concern per pull request.
- No secrets, internal hostnames, IPs or organisation-specific names in commits.
  This project ships only generic placeholders.
- Match the existing style: small single-purpose containers, configuration via
  environment variables, no Kubernetes in the default stack.

## Development

```bash
cp .env.example .env
docker compose up -d --build
docker compose logs -f <service>
```

Validate the compose file before opening a PR:

```bash
docker compose config -q
```

## Pull requests

1. Fork and branch from `main`.
2. Describe the change and how you tested it.
3. Ensure `docker compose config -q` passes and the stack starts cleanly.

## Reporting issues

Open a GitHub issue with steps to reproduce, expected vs. actual behaviour, and
relevant `docker compose logs` output (redact any secrets).

## License

By contributing you agree your contributions are licensed under the
[MIT License](LICENSE).
