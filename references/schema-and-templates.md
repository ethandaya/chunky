# Schema and Templates

## Canonical Files

| File | Purpose |
|------|---------|
| `assets/llms-map.schema.json` | JSON Schema for `llms-map.json` validation |
| `assets/llms-map.template.json` | Starter template for `llms-map.json` |
| `assets/llms.txt.template` | Starter template for `llms.txt` |

## Validation

Run from the target repo root:

```bash
$SKILL_DIR/scripts/validate-llms-map-schema.sh --map llms-map.json
```

Strict mode (fail if no validator backend is installed):

```bash
$SKILL_DIR/scripts/validate-llms-map-schema.sh --map llms-map.json --strict
```

## Chunk Capsule Template

Each `docs/chunks/<CHUNK_ID>.md` should follow this structure:

```md
# <CHUNK_ID>: <Title>

## Quick Reference

- Target: <path>
- Depends on: <chunk ids>
- Complexity: S|M|L
- File ownership: <explicit files/dirs>

## What To Build

<1-2 paragraphs>

## Acceptance Criteria

- [ ] <criterion 1>
- [ ] <criterion 2>

## Verification

\```bash
<verification commands>
\```
```

## Pre-flight Q&A Template

Create `docs/PREFLIGHT_QA.md` using this structure:

```md
# Pre-flight Q&A

## Open Questions

- [ ] <question the agent cannot answer from existing context>
- [ ] <question about ambiguous requirements>

## Answers

> **Q:** <question>
> **A:** <human's answer>

## Decisions

- <decision 1 — e.g. "Use Stripe Checkout, not custom forms">

## Constraints Discovered

- <constraint that affects chunk implementation>
```

## Knowledge Packs

Register external documentation in `llms-map.json` under `knowledge_packs`. Each entry has a stable ID, a `kind` (`llms_txt` or `url`), and the relevant URLs.

```json
"knowledge_packs": {
  "react-router": {
    "title": "React Router docs",
    "kind": "llms_txt",
    "llms_txt_url": "https://reactrouter.com/llms.txt",
    "llms_full_url": "https://reactrouter.com/llms-full.txt"
  },
  "stripe-api": {
    "title": "Stripe API reference",
    "kind": "url",
    "url": "https://docs.stripe.com/api"
  }
}
```

Reference packs per-chunk via their IDs:

```json
"P1-C1": {
  "title": "Add billing webhook handler",
  "knowledge_packs": ["stripe-api"]
}
```

The context resolver emits knowledge pack URLs on stderr so agents can fetch them before implementing.

## Required Top-Level Keys in `llms-map.json`

- `schema_version` — semver string
- `updated` — ISO date (YYYY-MM-DD)
- `chunks` — object mapping chunk IDs to chunk definitions
- `context_budgets` — budget entries for `plan`, `chunk`, and `task` modes
- `sub_agent_context` — must include `always_read` file list

See `assets/llms-map.schema.json` for the full schema definition.
