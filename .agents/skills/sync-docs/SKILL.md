---
name: sync-docs
description: After any code change in the KO-Tasks for Todoist plugin, check whether the relevant spec file(s) and architecture docs need updating. Use this whenever a Lua file is created or modified, a new behaviour is added, a requirement changes, or an architectural decision is made.
---

# Sync Docs After Code Changes

Use this skill whenever code in `todoist.koplugin/` is created or modified. Its job is to
ensure that specs and architecture docs never drift from the implementation.

---

## When to Apply This Skill

Apply automatically after **any** of these events:

- A Lua file is created, modified, or deleted
- A new feature, behaviour, or user-visible option is added
- A requirement changes (even informally, mid-conversation)
- An architectural decision is made (new pattern, new module, new constraint)
- A bug is fixed that reveals a spec was wrong or incomplete
- A spec status needs to move (`DRAFT → APPROVED → IN PROGRESS → DONE`)

---

## Step 1 — Identify Affected Specs

For every changed Lua file, determine which SPEC(s) it implements:

1. Check the file's module comment (first `--[[ ... ]]` block) for `SPEC-NNN` references.
2. Check function-level comments for `-- SPEC-NNN Req N:` inline citations.
3. Cross-reference `spec/features/` — scan for specs whose **Requirements** or **Scope**
   mention the changed file or behaviour.

A single code change may affect multiple specs (e.g. changing `_render` in `tasklist.lua`
could affect SPEC-001, SPEC-007, SPEC-010, SPEC-015).

---

## Step 2 — Check Each Affected Spec

For each affected spec file (`spec/features/SPEC-NNN-*.md`), verify:

| Check | Action if stale |
|---|---|
| `status` field | Advance: `DRAFT→APPROVED→IN PROGRESS→DONE` as appropriate |
| `updated` date | Set to today's date |
| Requirement text matches implementation | Update requirement to match what was built |
| Field names / API endpoints / query strings | Correct any that changed (e.g. `assignee_id` → `responsible_uid`) |
| Scope "In scope" / "Out of scope" lists | Add or remove items that changed |
| Edge Cases section | Add any edge cases discovered during implementation |
| Open Questions section | Close any questions that were resolved during implementation |

**Do not change** `id`, `created`, or `gate` fields.

---

## Step 3 — Check Architecture Docs

### `architecture/overview.md`

Check each section for staleness:

- **File Layout** — does it list every file that now exists? Update paths and descriptions.
- **Component Map** (mermaid) — does it show all current modules and their relationships?
- **Data Flow** — does each numbered flow still match the code?  
- **Navigation Architecture** — if navigation changed, update the UIManager stack diagram.
- **External Dependencies** table — are all API endpoints listed and accurate?
- **Planned Improvements** — remove items that have been implemented; add new ones.

### `architecture/adr/` — Existing ADRs

Scan ADRs for any **Consequences** or **Decision** text that is now inaccurate:

- If a consequence is no longer true, add a note or create a superseding ADR.
- If an endpoint, field name, or file path changed, update the affected ADR.
- **Never edit** `status: ACCEPTED` to change the decision itself — write a new ADR instead.

### `architecture/adr/` — New ADRs

Write a new ADR when **any** of these occur:

- A new module or file is introduced that changes the component structure
- A new persistence key is added to a LuaSettings file
- A new API endpoint is used for the first time
- A non-obvious trade-off was made (e.g. choosing client-side filtering over server-side)
- An existing ADR is superseded by a new approach

Use the template from `architecture/README.md`. Set `status: ACCEPTED` if the decision is
already implemented; `status: PROPOSED` if it is planned but not yet built.

---

## Step 4 — Update Inline Code Citations

If a spec requirement number changed (e.g. Req 5 became Req 6 after a rewrite), find and
update the corresponding `-- SPEC-NNN Req N:` comments in the Lua source file.

---

## Step 5 — Report What Was Updated

After completing the checks, include in your response a brief **Docs updated** section:

```
## Docs updated
- spec/features/SPEC-015-filter-by-assignee.md — status DONE, field name responsible_uid
- architecture/overview.md — file layout: added ui/home.lua
- architecture/adr/ADR-005-ui-navigation-architecture.md — new ADR (ACCEPTED)
```

If nothing needed updating, say so explicitly: "No doc changes required."

---

## Priorities and Shortcuts

- **Spec accuracy > completeness**: a short, correct requirement is better than a long,
  wrong one. Trim requirements that no longer match rather than leaving them as aspirational.
- **Don't gold-plate**: only update sections where the text is actually wrong or missing.
  Rewording correct text for style is not needed.
- **Status field is the minimum**: if you can only do one thing, at least advance the spec
  status and update the `updated` date.
- **ADR threshold**: not every small change warrants an ADR. Only write one if the change
  represents a genuine architectural decision with trade-offs. Bug fixes and minor
  refactors do not need ADRs.
