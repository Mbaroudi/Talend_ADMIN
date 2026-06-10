# Security Policy

## Scope

Talend_ADMIN is a **self-hosted starter template**. It ships with placeholder
credentials and no TLS; hardening for your environment is your responsibility:

- Change **every** secret in `.env` (and `rundeck/etc/realm.properties`).
- Put the stack behind a reverse proxy with TLS before exposing anything
  beyond localhost.
- Restrict who can reach the webhook handler (:8088) and the Rundeck API.

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Use [GitHub private vulnerability reporting](https://github.com/Mbaroudi/Talend_ADMIN/security/advisories/new)
("Report a vulnerability" on the Security tab). Include:

- A description of the issue and its impact.
- Steps to reproduce (or a proof of concept).
- Affected component (compose service, script, job definition...).

You can expect an acknowledgement within **7 days**. Once fixed, the report
and the fix are disclosed in the release notes.

## Supported versions

Only the latest release / `main` branch receives security fixes.
