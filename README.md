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
- **Knowledge packs** - references to external docs (llms.txt files, API references) the agent should fetch
- **An entry point** (`llms.txt`) - human and agent-readable navigation

Before execution, the agent runs a **pre-flight Q&A** - surfacing questions it can't answer from available context. The human answers these questions once, and the answers become part of every chunk's context pack. This eliminates mid-implementation stalls where the agent stops to ask.

Validation scripts verify that all artifacts are coherent before execution begins.

### Phase 3 - Execute

Execution is parallelism-first. The wave planner derives execution waves from the chunk dependency graph — chunks with no unmet dependencies run concurrently. Each agent (subagent, teammate, or background task) resolves its chunk's context pack, fetches any knowledge pack URLs, implements, and verifies independently. A simple completion tracker (`docs/CHUNKS_DONE.txt`) drives wave advancement.

The skill includes agent-specific hints for Amp (Task tool), Claude Code (subagents and agent teams), and Codex CLI (background tasks), but the execution loop is environment-agnostic.

## File Structure

```
chunky/
├── SKILL.md                              # Skill instructions (agent runbook)
├── scripts/
│   ├── resolve-context.sh                # Resolve minimal context pack per chunk
│   ├── plan-waves.sh                     # Derive execution waves from dependency graph
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
- **jq** - required for chunk/task context resolution and wave planning (`resolve-context.sh --mode plan` degrades gracefully without it)
- **python3 + jsonschema** or **ajv-cli** - optional, for full JSON Schema validation

## Usage

Tell your agent to use the `chunky` skill when starting a large feature. The agent will follow the three phases in `SKILL.md` automatically.

The context resolver supports three modes:

| Script | Mode | Purpose | Command |
|--------|------|---------|---------|
| `resolve-context.sh` | `plan` | Load full planning context | `--mode plan` |
| `resolve-context.sh` | `chunk` | Implement one chunk | `--mode chunk --chunk <ID>` |
| `resolve-context.sh` | `task` | Route a keyword to likely chunks | `--mode task --task <keyword>` |
| `plan-waves.sh` | `waves` | Show all derived execution waves | `--waves` |
| `plan-waves.sh` | `next` | Show next runnable chunk IDs | `--next [--done <file>]` |

## Artifacts Produced (in target repo)

After running chunky, the target repo will contain:

| File | Purpose |
|------|---------|
| `docs/SPEC.md` | Feature specification |
| `llms-map.json` | Chunk routing map with context budgets |
| `llms.txt` | Agent-readable entry point |
| `docs/chunks/*.md` | One capsule per chunk |
| `docs/PREFLIGHT_QA.md` | Pre-flight questions and human answers |
| `docs/CHUNKS_DONE.txt` | Completed chunk IDs (one per line) |

## License

MIT
