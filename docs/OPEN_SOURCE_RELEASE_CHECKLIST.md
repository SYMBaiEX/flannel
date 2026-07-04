# Open Source Release Checklist

Use this checklist before pushing public release work for Flannel.

## Repository State

- Confirm the remote repository is public and points at the expected owner.
- Confirm the default branch is `main`.
- Keep release work committed in small, reviewable slices.
- Avoid committing local screenshots, chat transcripts, exported workspaces, indexes, or runtime databases unless they are intentionally sanitized fixtures.

## Secret Hygiene

- Provider, connector, and tool credentials belong in macOS Keychain at runtime, never in source files.
- Do not commit `.env` files, service-account JSON, signing certificates, provisioning profiles, app archives, exported workspaces, or chat exports.
- If a credential is accidentally committed and pushed, rotate it immediately even if a later commit removes it.
- Run a working-tree grep for common token shapes and a history-aware scanner before each public push.

## Recommended Validation

Run these checks from the repository root:

```sh
git status --short --branch
git diff --check
gitleaks detect --source . --redact
gitleaks dir . --redact
xcodebuild -quiet -project flannel.xcodeproj -scheme flannel -destination 'platform=macOS,arch=arm64' build-for-testing
```

For targeted release fixes, also run the closest affected test class.

## Public Metadata

- Keep `README.md` current about implemented features versus remaining work.
- Keep `SECURITY.md` explicit about private reports and credential rotation.
- Keep `LICENSE` present and accurate.
- Keep `.gitignore` biased toward excluding local user data and secret-bearing artifacts.
