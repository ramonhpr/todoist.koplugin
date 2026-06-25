---
id: SPEC-006
title: Priority Icons on Task Rows
status: ABANDONED
created: 2026-06-16
updated: 2026-06-16
gate: G1
---

## Goal

Replace the existing ASCII-art priority prefixes with consistent, fixed-width Unicode symbols that align task titles cleanly across all rows and remain legible on e-ink displays.

## Background

The current implementation in `ui/tasklist.lua` uses a `PRIO_PREFIX` table of ASCII strings — `[!!!]`, `[!! ]`, `[ ! ]`, and an empty string for no priority — to indicate task urgency. These strings have inconsistent visual weight, consume more characters than necessary, and the bracket-and-space approach produces a ragged left edge when tasks of different priorities are mixed in the same list.

The Todoist API represents priority with a `priority` field whose values are inverted relative to the displayed P1–P4 labels: `4` = P1 (most urgent), `3` = P2, `2` = P3, `1` = P4 (natural priority / no indicator). This inversion is a known API quirk and must be handled explicitly in the mapping layer.

The replacement symbols must satisfy two constraints that are specific to KOReader's target hardware: they must be fixed-width so that all task titles start at the same horizontal offset, and they must be drawn from the Basic Multilingual Plane at a size that renders correctly at 167 DPI e-ink resolution without appearing as replacement boxes on devices with limited font coverage. A user-facing toggle to disable all priority indicators entirely is required, consistent with the settings surface defined in SPEC-003.

## Scope

### In scope
- Replacing `PRIO_PREFIX` in `ui/tasklist.lua` with a new fixed-width Unicode symbol table
- Defining the P1–P4 symbol mapping as specified below
- Ensuring all four prefix strings (including the P4 empty case) occupy the same number of display characters so task titles align
- Adding a boolean setting `show_priority_icons` (default `true`) to the settings screen defined in SPEC-003
- Hiding all priority prefixes when `show_priority_icons` is `false`

### Out of scope
- Colour rendering of priority symbols (not meaningful on e-ink displays)
- Per-task priority editing from within KOReader
- Changing the priority value stored on Todoist's servers

## Requirements

1. The `PRIO_PREFIX` table in `ui/tasklist.lua` **MUST** be replaced with a new mapping that covers all four API `priority` values (`4`, `3`, `2`, `1`) using the symbols defined in requirements 2–5.
2. API `priority` value `4` (P1, most urgent) **MUST** map to the prefix `"!! "` (two exclamation marks followed by one space).
3. API `priority` value `3` (P2) **MUST** map to the prefix `"!  "` (one exclamation mark followed by two spaces).
4. API `priority` value `2` (P3) **MUST** map to the prefix `"·  "` (U+00B7 MIDDLE DOT followed by two spaces).
5. API `priority` value `1` (P4, natural priority) **MUST** map to the prefix `"   "` (three spaces), preserving title alignment without displaying any symbol.
6. All four prefix strings **MUST** have an identical display width of exactly 3 characters so that task titles align to the same column on every row regardless of priority.
7. The plugin **MUST** expose a boolean setting `show_priority_icons` (default `true`) on the settings screen described in SPEC-003.
8. When `show_priority_icons` is `false`, **all** priority prefixes (including the three-space P4 padding) **MUST** be omitted entirely, and task titles **MUST** begin at the start of the row.
9. The priority prefix **MUST** appear as the leftmost element of the task row string, before the task title and before any project label introduced by SPEC-005.
10. The symbols `!!`, `!`, and `·` **MUST** be drawn from the Basic Multilingual Plane and **MUST** render without substitution boxes on any KOReader-supported font that includes Latin-1 Supplement (U+0080–U+00FF), ensuring legibility at 167 DPI e-ink resolution.
11. The existing 78-character row limit enforced in `ui/tasklist.lua` **MUST** continue to apply to the full rendered row string including the priority prefix.
12. When `show_priority_icons` is toggled, the task list **MUST** re-render immediately without requiring a full data refresh.

## Edge Cases

- A task whose `priority` field is absent or set to an unrecognised value must fall back to the P4 treatment (no symbol, or three-space padding if icons are enabled) and must not raise an error.
- When priority icons are disabled (`show_priority_icons = false`), the saved setting must persist across plugin restarts.
- On a device whose installed font lacks U+00B7 (MIDDLE DOT), the rendering may fall back to the font's replacement glyph; this is acceptable provided it does not crash the plugin.
- Tasks with very long titles must still respect the 78-character limit after the 3-character priority prefix is prepended; truncation logic must account for the prefix width.
- Toggling `show_priority_icons` mid-session must not corrupt the task data or require a re-fetch from the API.

## Open Questions

<!-- leave as HTML comment if none -->

## Related

- SPEC-001 — Task list surface (row layout, 78-char limit, existing `PRIO_PREFIX` definition)
- SPEC-003 — Settings screen (home for the `show_priority_icons` toggle)
- SPEC-005 — Project display (project label appears after the priority prefix on the same row)
