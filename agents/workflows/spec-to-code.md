# Workflow: Spec to Code

This workflow guides an agent from an approved spec to mergeable code.

---

## Step 1 — Verify the spec is ready (G1 gate)

Read `spec/features/SPEC-XXX-<feature>.md` and confirm:
- [ ] Status is APPROVED
- [ ] No open questions remain
- [ ] Every requirement is numbered and testable
- [ ] An ADR exists if structural changes are needed

If any item is unchecked, **stop** and resolve it before continuing.

---

## Step 2 — Understand the architecture

Read any ADRs in `architecture/adr/` relevant to the feature.
Read `architecture/overview.md` if it exists.

---

## Step 3 — Plan the implementation

Write a short plan (bullet points) covering:
- Files to create or modify
- Data structures or interfaces to add
- Tests to write

Do not start coding until the plan is reviewed.

---

## Step 4 — Implement

Follow `agents/roles/developer.md` constraints.
Update the spec status to **IN PROGRESS**.

---

## Step 5 — Verify (G2 gate)

Run the test suite. For each acceptance criterion in the spec, confirm a test exists.
Check every G2 criterion in `spec/quality-gates.md`.

---

## Step 6 — Wrap up

- Update spec status to **DONE**
- Write a concise summary of what changed and what was verified
