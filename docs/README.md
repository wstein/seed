# Documentation Scaffold

`cx init` created a minimal Antora documentation site for `myproject`.

## Structure

- `antora.yml`: component descriptor
- `modules/ROOT`: shared navigation and docs index
- `modules/onboarding`: contributor and operator entrypoint
- `modules/manual`: task-oriented operating guidance
- `modules/architecture`: arc42-based architecture spine

## Suggested Workflow

1. Keep high-level project orientation in `onboarding`.
2. Put repeatable commands and operational checks in `manual`.
3. Use the arc42 chapters in `architecture` for system design and tradeoffs.

The scaffold is intentionally small so the documentation can evolve from real
project needs instead of carrying placeholder bulk.
