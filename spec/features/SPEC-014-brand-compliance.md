---
id: SPEC-014
title: Todoist Brand Compliance
status: DONE
created: 2026-07-07
updated: 2026-07-07
gate: G1
---

## Goal

Ensure the plugin meets every requirement of Todoist's published brand-usage policy so it may be distributed publicly without infringing Doist's trademarks or violating the Todoist API Terms of Service.

## Background

Todoist's API developer documentation specifies four binding requirements for third-party apps that use the Todoist platform:

1. **Naming** — "Todoist" must not be the primary name of the app; acceptable formats are "x for Todoist" or "x with Todoist".
2. **Disclaimer** — The app description must state it is *"not created by, affiliated with, or supported by Doist."*
3. **Logo and branding** — Any use of Todoist's marks must comply with Doist's brand guidelines.
4. **Legal compliance** — Using Todoist branding implies acceptance of Doist's brand guidelines and Terms of Service.

The plugin currently violates requirements 1 and 2:
- `_meta.lua` sets `fullname = "Todoist"`, making "Todoist" the sole and primary name of the plugin.
- No disclaimer appears anywhere in the plugin description, Settings About screen, or README.

Requirement 3 is satisfied by default because the plugin contains no Todoist logo assets. Requirement 4 is a legal acceptance obligation with no code surface; it is documented here for awareness.

## Scope

### In scope
- Renaming the plugin's public-facing name to a compliant form (e.g. `"KOReader for Todoist"`)
- Adding the mandatory Doist disclaimer to `_meta.lua`'s `description` field
- Displaying the disclaimer in the Settings screen About panel
- Adding the disclaimer to `README.md`

### Out of scope
- Changing the internal plugin folder name (`todoist.koplugin`) or Lua `name` key — these are technical identifiers, not user-facing names
- Obtaining explicit written approval from Doist (the policy is self-service for compliant apps)
- Updating any Todoist logo assets (none exist; no action required)

## Requirements

1. The `fullname` field in `_meta.lua` **MUST NOT** use "Todoist" as a standalone name. It **MUST** follow the format `"<independent name> for Todoist"` or `"<independent name> with Todoist"`. The chosen name for this plugin is **`"KO-Tasks for Todoist"`**.
2. The `description` field in `_meta.lua` **MUST** include the sentence `"Not created by, affiliated with, or supported by Doist."` either verbatim or in a form that conveys the same meaning without omission of any of the three predicates (created by / affiliated with / supported by).
3. The Settings screen About panel **MUST** display the disclaimer `"Not created by, affiliated with, or supported by Doist."` as part of its text.
4. `README.md` **MUST** include a clearly labelled **Disclaimer** section containing the full Doist disclaimer text.
5. No file in the distributed plugin archive **MUST** include Todoist or Doist logo assets (SVG, PNG, or similar image files bearing Todoist branding) unless explicit written permission has been granted by Doist.
6. The About panel **MUST** also display the plugin's compliant public name (Req 1) so users see the branded name consistently across the UI.

## Edge Cases

- If Doist updates their brand guidelines and the required disclaimer text changes, this spec must be revisited; the implementation should use a single shared constant or string so the disclaimer appears consistently and only needs updating in one place.
- The internal `name` key (`"todoist"`) used by KOReader's plugin loader is a technical identifier, not a user-visible name; it does not need to comply with the naming rule and must not be changed (changing it would break installations).
- The KOReader Tools menu entry label (`"Todoist"`) is derived from `fullname`; updating `fullname` to the compliant form will automatically update the menu label without any additional code change.

## Open Questions

<!-- None — all questions resolved. The chosen independent name is "KO-Tasks", giving the full plugin name "KO-Tasks for Todoist". -->

## Related

- `_meta.lua` — `fullname` and `description` fields (Req 1, 2)
- `ui/settings.lua` — About panel (Req 3, 6)
- `README.md` — Disclaimer section (Req 4)
- Todoist API brand-usage policy — https://developer.todoist.com/appconsole.html (external)
