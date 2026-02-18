---
name: chunky
license: MIT
description: Spec-first workflow for planning and shipping large features with coding agents. Chunks work into independently executable units with minimal context routing. Includes pre-flight Q&A to surface unknowns before execution and knowledge packs for external docs (llms.txt, API references). Use when planning a large feature, breaking down complex scope, chunking work for agents, oneshot implementation, or spec-driven development.
---

# Chunky

Spec-first, chunk-based feature shipping for coding agents.

When this skill is activated, follow the three phases below in order. Each phase produces concrete artifacts in the target repo. Do not skip phases.

## Assumptions

- **CWD is always the target repo root.**
- Scripts and assets live in the skill directory — the directory containing this `SKILL.md` file. Derive the skill directory from this file's path and use it when running scripts (e.g., if this file is at `/home/user/.agents/skills/chunky/SKILL.md`, the skill directory is `/home/user/.agents/skills/chunky`).
- `jq` is required for chunk and task context resolution. Scripts degrade gracefully without it for basic operations.

## Phase 1 — Design

**Goal:** Produce a single spec document the rest of the workflow depends on.

1. Create `docs/SPEC.md` in the target repo.
2. The spec must include these sections:
   - **Problem / Goal** — what we're building and why.
   - **Non-goals** — what is explicitly out of scope.
   - **Acceptance criteria** — global conditions for the feature to be considered done.
   - **Constraints** — technical, security, or compatibility requirements.
   - **Verification approach** — how we prove it works (test commands, manual steps).
3. Stop. Before moving to Phase 2, confirm: every acceptance criterion is testable, constraints don't contradict goals, and the verification approach can actually prove the criteria are met.

## Phase 2 — Plan

**Goal:** Break the spec into independently executable chunks with routing metadata.

### Step 1: Create `llms-map.json`

Use `assets/llms-map.template.json` as a starting point. Populate:

- `schema_version` — use `"1.0.0"`.
- `updated` — today's date in `YYYY-MM-DD` format.
- `baseline_read_order` — files an agent should read when planning (at minimum `docs/SPEC.md`).
- `sub_agent_context.always_read` — files loaded for every chunk (at minimum `docs/SPEC.md`).
- `context_budgets` — max files and bytes per mode. Keep chunk budgets small.
- `verification.per_chunk` — commands every chunk must pass after implementation.
- `chunks` — one entry per chunk. Each chunk requires:
  - `title` — short name.
  - `target` — the directory or package this chunk modifies.
  - `depends_on` — array of chunk IDs that must be completed first (empty array if none).
  - `docs` — files the agent needs to read for this chunk.
  - `capsule` — path to the chunk capsule file (e.g. `docs/chunks/P1-C1.md`).
  - `complexity` — `"S"`, `"M"`, or `"L"`.

Optional fields: `knowledge_packs`, `preflight`, `task_router`, `orchestrator`, `phases`, `freshness`. See `assets/llms-map.schema.json` for the full schema.

### Step 2: Write chunk capsules

For each chunk in `llms-map.json`, create `docs/chunks/<CHUNK_ID>.md` using the template in `references/schema-and-templates.md`. Each capsule must include what to build, acceptance criteria, file ownership, and verification commands.

### Step 3: Create `llms.txt`

Create `llms.txt` in the target repo root. Use `assets/llms.txt.template` as a starting point. It must include:

1. What this repo/feature is.
2. Start here → `docs/SPEC.md`.
3. Chunk navigation → `llms-map.json` and `docs/chunks/`.
4. Verification commands that must pass.

### Step 4: Register knowledge packs

If any chunk depends on external documentation (library docs, API references, llms.txt files), add a `knowledge_packs` map to `llms-map.json` and reference pack IDs from each chunk's `knowledge_packs` array. See `references/schema-and-templates.md` for the format.

### Step 5: Pre-flight Q&A

The preflight has two stages. Stage A is read-only — no file edits. Stage B writes the results.

#### Stage A — Draft questions (read-only)

1. Read the spec, all chunk capsules, and any knowledge pack URLs registered in `llms-map.json`.
2. Identify every question the agent cannot answer from available context. Only ask questions that would change code, schema, verification, rollout, or security decisions. For anything else, state an assumption.
3. Present the questions **in the conversation** (not in a file yet) using this format:

```
## Pre-flight Questions

### Blocking (must answer before execution)
1. <question> — Assumption if unanswered: <default>
2. <question>

### Non-blocking (will assume default unless overridden)
3. <question> — Default assumption: <assumption>
```

4. **Stop. Do not proceed.** Ask the human to reply with numbered answers. Do not narrate next steps or continue into Phase 3.

> **Claude Code hint:** If available, use Plan mode or a Plan subagent for Stage A to enforce read-only research and prevent accidental edits.
>
> **Codex hint:** Use the `update_plan` tool to track preflight status (Drafting → Awaiting answers → Recording → Done).

#### Stage B — Record answers

After the human answers (or marks questions N/A):

1. Create `docs/PREFLIGHT_QA.md` using the template in `references/schema-and-templates.md`.
2. Transcribe all questions, answers, decisions, and discovered constraints into the file.
3. Set `preflight.doc` in `llms-map.json` to `"docs/PREFLIGHT_QA.md"`.
4. If any answer reveals new constraints, update `docs/SPEC.md` and affected chunk capsules.
5. If any answer reveals missing external docs, register them in `knowledge_packs` and add references to the relevant chunks.

Confirm before proceeding:
- [ ] All blocking questions answered or marked N/A with stated assumption.
- [ ] `docs/PREFLIGHT_QA.md` written and complete.
- [ ] `llms-map.json` `preflight.doc` set.
- [ ] Spec and capsules updated if answers changed constraints.

### Step 6: Validate

Run these from the target repo root (replace `$SKILL_DIR` with the absolute path to this skill's directory):

```bash
$SKILL_DIR/scripts/check-agent-context.sh .
$SKILL_DIR/scripts/validate-llms-map-schema.sh --map llms-map.json
```

If either fails, fix the artifacts before proceeding.

## Phase 3 — Execute

**Goal:** Implement one chunk at a time with minimal context.

### Pick a chunk

Choose a chunk whose `depends_on` entries are all completed. If using an orchestrator, follow wave order.

### Resolve context

Run from the target repo root:

```bash
$SKILL_DIR/scripts/resolve-context.sh --mode chunk --chunk <CHUNK_ID> --map llms-map.json
```

This outputs the file list for the chunk's context pack and enforces budget limits.

### Fetch external docs

If the resolver emits `knowledge_packs` on stderr, fetch those URLs (prefer `llms_full_url` when available, fall back to `llms_txt_url` or `url`). Use these as authoritative references during implementation. Do not guess at APIs or conventions covered by a knowledge pack.

### Implement

1. Read **only** the files in the resolved context pack and any fetched knowledge packs. Do not browse the repo.
2. If you discover missing context, stop — update the chunk's `docs` in `llms-map.json` and its capsule, then re-resolve.
3. Implement the chunk.

### Verify

1. Run the chunk's verification commands (from the capsule and `verification.per_chunk` in `llms-map.json`).
2. Confirm all acceptance criteria in the capsule are satisfied.
3. If verification fails, fix and re-verify. Do not move to the next chunk until all checks pass.

### Repeat

Move to the next chunk. Repeat resolve → fetch → implement → verify until all chunks are done.

## Execution Modes

The context resolver supports three modes:

| Mode | When | Command |
|------|------|---------|
| **chunk** | Implement one chunk | `--mode chunk --chunk <CHUNK_ID>` |
| **task** | Route a keyword to likely chunks | `--mode task --task <keyword>` |
| **plan** | Load full planning context | `--mode plan` |

## Skill Contents

- `SKILL.md` — this file
- `scripts/resolve-context.sh` — resolve minimal context pack from `llms-map.json`
- `scripts/check-agent-context.sh` — validate artifact coherence
- `scripts/validate-llms-map-schema.sh` — validate `llms-map.json` against schema
- `assets/llms-map.schema.json` — canonical JSON schema
- `assets/llms-map.template.json` — starter template for `llms-map.json`
- `assets/llms.txt.template` — starter template for `llms.txt`
- `references/schema-and-templates.md` — quick reference for schemas and templates
