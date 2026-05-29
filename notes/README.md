# Repository Notes Guide

This directory is the repository's note layer. The workflow is based on the "mise en place" idea: prepare the durable ingredients of understanding before implementation, tests, fixtures, and docs consume them.

Notes stand on their own. A note should explain one durable idea without depending on a specific test, fixture, implementation file, or documentation page to make sense.

Implementation, tests, fixtures, and docs may refer to notes by stable note id. Notes should not point back to concrete implementations, tests, fixtures, or documentation as part of their required meaning.

Docs are the human-focused linear reading experience. Write docs from the notes and the implementation, and let docs reference implementation details such as code blocks when useful. Docs should not refer readers back to notes.

Backlog, roadmap, and version tracking do not belong in note frontmatter. Keep that work in a separate top-level Markdown document instead of encoding it into notes.

## Notes-First Workflow

Use notes before downstream work hardens:

1. Capture the idea as a note.
2. Check whether it overlaps with an existing note.
3. Link it to related notes by title or id.
4. Let implementation, tests, fixtures, and docs consume the stable note id when they need traceability.
5. Move backlog, release, and version status into a separate top-level Markdown document.

This keeps the note graph focused on durable knowledge instead of project state.

## Atomicity

Each note must contain one discrete thought.

Good atomic notes describe exactly one:

- architectural decision
- invariant
- mechanism
- concept
- failure mode
- tradeoff

If a note contains multiple unrelated ideas, split it.

## Start With The Summary Contract

The first body paragraph is required. It must summarize the note in plain language so humans and agents can route to the right note without reading the whole graph.

If the opening paragraph cannot stand alone, the note is too vague or too broad.

## Use The How / What / Why Model

Every note should make these answers clear:

- What is the durable fact, decision, mechanism, or failure mode?
- Why does it matter or which invariant does it protect?
- How should a later reader apply it?

The note does not need literal headings for every answer, but all three answers should be easy to find.

## Every Note Should Link Outward To Related Notes

Every note should link outward to related notes.

Use links to show neighboring concepts, constraints, decisions, and tradeoffs. Keep the note graph radial: a reader should be able to move from one durable idea to the next without following implementation or documentation breadcrumbs.

## Keep IDs Stable

Every note uses a time-based frontmatter id in the form `YYYYMMDDHHMMSS`.

The id is for machines, search, routing, and stable reference. The filename is the human title. Do not put the numeric id in the visible title.

Stable ids matter because downstream automation, tests, fixtures, implementation comments, and docs can reference notes without depending on filenames that may change.

## Minimum Anatomy

Every note must contain:

- YAML frontmatter with `id`, `aliases`, and `tags`
- one atomic body with a non-empty opening summary paragraph
- one links section with explicit connections to related notes

Do not add backlog, version, target, test, fixture, implementation, or documentation references to note frontmatter.

## Recommended Workflow

1. Start from `Templates/Atomic Note Template.md`.
2. Assign a fresh `id` using local time in `YYYYMMDDHHMMSS` format.
3. Give the note a clear searchable filename.
4. Write one thought in your own words.
5. Add explicit links to related notes.
6. Save the file with a human-readable filename that matches the note title.
7. Keep the whole note within `4000` body characters and `100` body lines so the graph stays high-signal.

Suggested filename style: `Clear Searchable Title.md`.

## What Does Not Belong Here

Do not use this directory for:

- sprint planning
- transient checklists
- copied code dumps
- test, fixture, implementation, or documentation catalogs
- meeting notes without synthesis
- backlog management
- roadmap or release-version tracking

If the content will be obsolete as soon as a ticket closes or a release ships, put it in a separate top-level Markdown document.
