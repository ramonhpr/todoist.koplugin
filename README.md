# todoist.koplugin

A KOReader plugin that surfaces your Todoist tasks on your Kindle (and other e-ink readers),
with optional due-time notifications while you read.

## Features (v1)

| Feature | Spec | Status |
|---|---|---|
| Today's task list | [SPEC-001](spec/features/SPEC-001-todays-task-list.md) | IN PROGRESS |
| Due-time notifications | [SPEC-002](spec/features/SPEC-002-due-notifications.md) | IN PROGRESS |
| Settings screen | [SPEC-003](spec/features/SPEC-003-settings-screen.md) | IN PROGRESS |
| Complete a task | [SPEC-004](spec/features/SPEC-004-complete-task.md) | IN PROGRESS |

## Development Process

This project uses **Spec Driven Development (SDD)** with explicit quality gates.

```
spec/               Feature & contract specifications
agents/             AI agent roles and workflows
architecture/       Architecture Decision Records (ADRs) and system overview
```

Before writing any code, read:
1. [`spec/quality-gates.md`](spec/quality-gates.md) — the gate criteria every change must pass
2. [`architecture/overview.md`](architecture/overview.md) — how the plugin is structured
3. The relevant spec in [`spec/features/`](spec/features/)

## Architecture

See [`architecture/overview.md`](architecture/overview.md) for the full system diagram.

Key decisions:
- [ADR-001](architecture/adr/ADR-001-todoist-api-auth.md) — REST API v2 + personal token auth
- [ADR-002](architecture/adr/ADR-002-notification-mechanism.md) — UIManager scheduler for notifications
- [ADR-003](architecture/adr/ADR-003-task-cache-strategy.md) — disk cache with 15-min TTL
- [ADR-004](architecture/adr/ADR-004-write-operations.md) — optimistic update for write operations

## Installation

> Initial implementation complete. See source files below.

1. Copy `todoist.koplugin/` to your KOReader `plugins/` directory
2. Restart KOReader
3. Open **Tools → Todoist** and enter your [Todoist API token](https://app.todoist.com/app/settings/integrations/developer)

## Platform

- **Primary target:** Kindle (via KOReader)
- **Also supported:** Kobo, PocketBook
- **Runtime:** Lua 5.1 (KOReader's embedded interpreter)
