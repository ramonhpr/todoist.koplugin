# Agents

This folder contains agent prompt files used in AI-assisted development.
Each file defines the role, context, and constraints for a specific agent persona or workflow.

## Folder Structure

```
agents/
├── roles/          # Persona definitions (e.g. developer, reviewer, architect)
├── workflows/      # Step-by-step prompts for recurring tasks
└── AGENTS.md       # Root instructions inherited by all agents in this project
```

## How Agents Fit Into SDD

Agents are spec-aware. Before generating or reviewing code they must:

1. Read the relevant spec (`spec/features/SPEC-XXX-*.md`)
2. Check the current gate status (`spec/quality-gates.md`)
3. Operate only within the approved scope of the spec

## Adding a New Agent File

Create a file in `roles/` or `workflows/` using the naming convention:

```
<scope>-<role|task>.md
```

Examples:
- `roles/developer.md`
- `roles/reviewer.md`
- `workflows/spec-to-code.md`
- `workflows/gate-review.md`

Each agent file should state:

- **Role** – who this agent is pretending to be
- **Input** – what it needs to read before starting
- **Constraints** – what it must not do
- **Output** – what it should produce
