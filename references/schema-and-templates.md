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

## Required Top-Level Keys in `llms-map.json`

- `schema_version` — semver string
- `updated` — ISO date (YYYY-MM-DD)
- `chunks` — object mapping chunk IDs to chunk definitions
- `context_budgets` — budget entries for `plan`, `chunk`, and `task` modes
- `sub_agent_context` — must include `always_read` file list

See `assets/llms-map.schema.json` for the full schema definition.
