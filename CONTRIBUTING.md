# Contributing Guide

Thanks for your interest in contributing! This project aims to make running the ARO Client on Windows as simple and reliable as possible.

## Ways to contribute
- Bug reports and reproduction steps
- Feature proposals (please explain the use case and expected UX)
- Documentation improvements (clarity, troubleshooting, screenshots)
- Pull requests (small, focused, with tests where applicable)

## Development setup
- Windows 10/11 with PowerShell 5.1+ (PowerShell 7 is also fine)
- Hyper-V (Pro/Enterprise) and/or Oracle VirtualBox
- Run scripts in an elevated PowerShell when needed

## Scripts style
- Language: English only (no Cyrillic in code or logs)
- Keep scripts idempotent and safe by default
- Prefer approved verbs for PowerShell functions (e.g., `Get-`, `Set-`, `Test-`)
- Avoid blocking/wait loops; provide clear progress logging instead
- Log to `logs/setup-*.log` via transcript when orchestrator runs

## Pull requests
1. Fork the repository and create a branch from `main`.
2. Follow the style rules above and run PSScriptAnalyzer (CI will also run).
3. Update documentation in `docs/` and `README.md` if behavior changes.
4. Add a line to `CHANGELOG.md` under `Unreleased`.
5. Open a PR with a clear title and description (template will help).

## Issue reports
- Use the templates provided.
- Include OS version, hypervisor used (Hyper-V/VBox), steps to reproduce, logs from `logs/`.
- If relevant, include screenshots or the last 50 lines of console output.

## License
By contributing, you agree that your contributions will be licensed under the MIT License.
