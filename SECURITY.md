# Security Policy

## Supported Versions

PiDesktop is in early development; only the latest `main` is supported.

| Version | Supported |
| ------- | --------- |
| main    | ✅        |

## Reporting a Vulnerability

**Please do not open a public issue for security problems.**

Report privately via GitHub's [Security Advisories](https://github.com/aice109/pi-desktop/security/advisories/new)
("Report a vulnerability"), or email **aice109@outlook.com**.

Include:
- A description of the issue and its impact
- Steps to reproduce
- Affected version/commit
- Any suggested fix (optional)

We aim to acknowledge reports within a few days and will keep you updated on the
remediation timeline. Please give us reasonable time to address the issue before
public disclosure.

## Scope

Areas of particular interest:
- Handling of agent credentials, tokens, and API keys
- Local file/workspace access boundaries
- Process/IPC handling between the app and the pi agent
- Any place user data could leak (logs, telemetry, crash reports)

## Our Commitments

- We will not log or persist secrets.
- We will credit reporters who wish to be acknowledged.
