# Quality Gates

Quality gates are explicit checkpoints that code and specs must pass before moving to the next phase.
A gate blocks progress until every criterion is met.

---

## G1 — Spec Gate (before any code is written)

**Purpose:** Ensure the spec is complete and agreed upon before implementation starts.

| # | Criterion                                                          | Owner  |
|---|--------------------------------------------------------------------|--------|
| 1 | Spec status is APPROVED                                            | Author |
| 2 | All open questions resolved                                        | Team   |
| 3 | Acceptance criteria are testable and unambiguous                   | Author |
| 4 | Architecture decision recorded (if structural changes are needed)  | Arch   |
| 5 | Relevant agent prompts updated to reflect new behaviour            | Author |

---

## G2 — Implementation Gate (before merging to main)

**Purpose:** Ensure the implementation matches the spec.

| # | Criterion                                                        | Owner |
|---|------------------------------------------------------------------|-------|
| 1 | All acceptance criteria from the spec have a corresponding test  | Dev   |
| 2 | All tests pass                                                   | CI    |
| 3 | No regressions in existing specs (test suite green)              | CI    |
| 4 | Code reviewed by at least one peer                               | Dev   |
| 5 | Spec status updated to IN PROGRESS or DONE                       | Dev   |

---

## G3 — Release Gate (before shipping)

**Purpose:** Ensure the feature is production-ready.

| # | Criterion                                                          | Owner |
|---|--------------------------------------------------------------------|-------|
| 1 | Spec status is DONE                                                | Dev   |
| 2 | All G2 criteria satisfied                                          | CI    |
| 3 | README / user-facing docs updated if behaviour changed             | Dev   |
| 4 | Architecture docs reflect any structural changes made              | Arch  |
| 5 | No open critical bugs against this spec                            | Dev   |

---

## Blocking a Gate

If a gate criterion is not met, open an issue with the label `gate-blocked` and link the relevant spec.
Do not bypass gates without explicit written approval from the team lead.
