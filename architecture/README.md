# Architecture

This folder contains Architecture Decision Records (ADRs) and high-level design documents.

## What Is an ADR?

An Architecture Decision Record captures a significant design choice: the context that forced a decision,
the options that were considered, and the rationale for the one that was chosen.
ADRs are immutable once accepted — superseded decisions get a new ADR, not an edit.

## Folder Structure

```
architecture/
├── adr/            # Individual Architecture Decision Records
├── diagrams/       # System and component diagrams (Mermaid, PNG, etc.)
└── overview.md     # Living high-level system overview
```

## ADR Lifecycle

```
PROPOSED → ACCEPTED → SUPERSEDED | DEPRECATED
```

## ADR Template

Create new ADRs in `adr/` with the filename `ADR-NNN-short-title.md`.

```markdown
---
id: ADR-NNN
title: Short Title
status: PROPOSED | ACCEPTED | SUPERSEDED | DEPRECATED
date: YYYY-MM-DD
supersedes: ADR-NNN   # optional
---

## Context

What is the situation that forced this decision?

## Decision

What was decided?

## Consequences

What becomes easier or harder as a result?

## Options Considered

| Option | Pros | Cons |
|--------|------|------|
|        |      |      |
```
