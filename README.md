# Chunky

Spec-first, chunk-based feature shipping for coding agents.

Chunky is an [agent skill](https://agentskills.io) that breaks large features into independently executable chunks with minimal context routing. Instead of dumping an entire codebase into an agent's context, each chunk carries only the files it needs - keeping agents focused and implementations accurate.

## How It Works

Three phases, run in order:

### Phase 1 - Design

The agent writes a spec (`docs/SPEC.md`) covering the problem, non-goals, acceptance criteria, constraints, and verification approach. Nothing else happens until the spec is solid.

### Phase 2 - Plan

The spec gets broken into chunks. Each chunk is a self-contained unit of work with:

- **A capsule** (`docs/chunks/<ID>.md`) - what to build, acceptance criteria, verification commands
- **A routing entry** in `llms-map.json` - dependencies, file ownership, context budget
- **An entry point** (`llms.txt`) - human and agent-readable navigation

Validation scripts verify that all artifacts are coherent before execution begins.

### Phase 3 - Execute

For each chunk, the context resolver outputs the minimal set of files the agent needs. The agent reads only those files, implements the chunk, runs verification, and moves to the next one. No repo browsing, no unbounded context.

## File Structure

```
chunky/
├── SKILL.md                              # Skill instructions (agent runbook)
├── scripts/
│   ├── resolve-context.sh                # Resolve minimal context pack per chunk
│   ├── check-agent-context.sh            # Validate artifact coherence
│   └── validate-llms-map-schema.sh       # Validate llms-map.json against schema
├── assets/
│   ├── llms-map.schema.json              # JSON Schema for llms-map.json
│   ├── llms-map.template.json            # Starter template
│   └── llms.txt.template                 # Starter template
└── references/
    └── schema-and-templates.md           # Quick reference for schemas and templates
```

## Requirements

- **bash** - all scripts are POSIX-compatible bash
- **jq** - required for chunk and task context resolution (plan mode degrades gracefully without it)
- **python3 + jsonschema** or **ajv-cli** - optional, for full JSON Schema validation

## Usage

Tell your agent to use the `chunky` skill when starting a large feature. The agent will follow the three phases in `SKILL.md` automatically.

The context resolver supports three modes:

| Mode | Purpose | Command |
|------|---------|---------|
| `plan` | Load full planning context | `--mode plan` |
| `chunk` | Implement one chunk | `--mode chunk --chunk <ID>` |
| `task` | Route a keyword to likely chunks | `--mode task --task <keyword>` |

## Artifacts Produced (in target repo)

After running chunky, the target repo will contain:

| File | Purpose |
|------|---------|
| `docs/SPEC.md` | Feature specification |
| `llms-map.json` | Chunk routing map with context budgets |
| `llms.txt` | Agent-readable entry point |
| `docs/chunks/*.md` | One capsule per chunk |

## License

MIT
