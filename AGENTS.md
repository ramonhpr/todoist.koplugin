# Project Agent Instructions

You are an AI agent working on the **Todoist KOReader Plugin**. This project uses Spec-Driven Development (SDD) and targets e-ink devices running KOReader. All agents working on this project must abide by the following guidelines derived from the `agents/` and `architecture/` documentation.

## 1. Spec-Driven Development (SDD)
- **Always read the spec**: Before writing or reviewing any code, you must read the relevant spec (`spec/features/SPEC-XXX-*.md`) and the quality gates (`spec/quality-gates.md`).
- **Strict Adherence**: Only implement behavior defined in an APPROVED spec. Do not invent features or stray from the spec.
- **Update Status**: Keep the spec status updated (e.g., APPROVED → IN PROGRESS → DONE).
- **Tests First**: Ensure every numbered requirement in the spec is satisfied and has a corresponding test before considering it complete.

## 2. Roles and Workflows
Depending on your task, adopt the relevant persona and follow the workflows defined in the `agents/` folder:
- **Developer** (`agents/roles/developer.md`): Focus on faithful implementation of the spec. Change the code to match the spec, not the other way around. Keep changes minimal.
- **Reviewer** (`agents/roles/reviewer.md`): Thoroughly review code against the spec and quality gates (G2). Block PRs that lack tests or fail to satisfy requirements.
- **Spec to Code** (`agents/workflows/spec-to-code.md`): For end-to-end implementation, follow the 6-step workflow (Verify -> Architecture -> Plan -> Implement -> Verify -> Wrap up).

## 3. Architecture and Platform Constraints
The target platform (KOReader on e-ink devices) imposes strict constraints. Always consult `architecture/overview.md` and any Architecture Decision Records (`architecture/adr/`).

**Key Constraints**:
- **Environment**: Lua 5.1 (KOReader's embedded interpreter).
- **Network**: Use `NetworkMgr`. Wi-Fi may be disabled; handle offline gracefully. HTTPS is required.
- **UI**: E-ink displays are slow. Avoid animations and minimize screen redraws.
- **Concurrency**: There are no background threads. Use `UIManager:scheduleIn()` for delayed tasks.
- **Persistence**: Store settings locally using `LuaSettings` / `G_reader_settings`.
- **Security**: Never log or display the Todoist API token in plain text after entry.

**ADR Lifecycle**: Any significant architectural change must go through the ADR process (`PROPOSED → ACCEPTED → SUPERSEDED`) inside `architecture/adr/`.

## 4. CI/CD & Releases (.github/)
This project utilizes GitHub Actions for automated releases.
- **Workflows** (`.github/workflows/`): Automated processes, such as the `release.yml` workflow.
- **Release Process**: Pushing a tag that starts with `v` (e.g., `v1.0.0`) automatically triggers a release build. This builds a plugin zip archive (excluding dev/doc files like `spec/`, `agents/`, `architecture/`, and `.github/`) and publishes it as a GitHub Release.
