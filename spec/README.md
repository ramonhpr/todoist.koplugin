# Specifications

This folder contains feature and behaviour specifications that drive development.
Each spec is the source of truth for what gets built and is reviewed at every quality gate.

## Folder Structure

```
spec/
├── features/       # Feature-level specs (user-facing behaviour)
├── contracts/      # API / interface contracts (inputs, outputs, invariants)
└── quality-gates/  # Gate checklists and pass/fail criteria
```

## Spec Lifecycle

```
DRAFT → REVIEW → APPROVED → IN PROGRESS → DONE
```

| Status       | Meaning                                               |
|--------------|-------------------------------------------------------|
| DRAFT        | Being written; not yet ready for implementation       |
| REVIEW       | Ready for stakeholder/team sign-off                   |
| APPROVED     | Locked baseline; implementation may begin             |
| IN PROGRESS  | Active development against this spec                  |
| DONE         | Implemented, tested, and verified against the spec    |

## Writing a Spec

Every spec file should start with the following front-matter block:

```markdown
---
id: SPEC-XXX
title: <Short title>
status: DRAFT | REVIEW | APPROVED | IN PROGRESS | DONE
created: YYYY-MM-DD
updated: YYYY-MM-DD
gate: G1 | G2 | G3          # which quality gate this spec must pass
---
```

Then include the sections:

1. **Goal** – one-sentence purpose
2. **Background** – context and motivation
3. **Scope** – what is in / out of scope
4. **Requirements** – numbered, testable acceptance criteria
5. **Edge Cases** – known boundary conditions
6. **Open Questions** – unresolved decisions (clear before APPROVED)
