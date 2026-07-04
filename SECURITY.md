# Security Policy

Flannel is a local-first macOS app. Treat provider credentials, local chat exports, workspace snapshots, and tool outputs as private user data.

## Reporting A Vulnerability

Please do not paste secrets, private transcripts, API keys, or exploit details into a public issue.

If GitHub private vulnerability reporting is available for this repository, use that channel first. Otherwise, open a public issue with a brief non-sensitive summary and a maintainer can coordinate a safer disclosure path.

## Secret Handling

- Provider and connector credentials should be stored in macOS Keychain at runtime.
- Do not commit `.env`, Keychain exports, service-account JSON, signing certificates, provisioning profiles, local workspace snapshots, chat exports, app databases, or build artifacts.
- Workspace backup imports intentionally clear provider and tool secret references before reactivation on a new Mac.
- If a credential is committed accidentally, rotate it immediately. Removing it from the latest commit is not enough once the repository has been pushed.

## Supported Branch

Security fixes target the default branch, `main`.
