#!/usr/bin/env bash
set -euo pipefail

tmpfile="$(mktemp "${TMPDIR:-/tmp}/resolve-context.XXXXXX")"
trap 'rm -f "$tmpfile"' EXIT

mode=""
chunk_id=""
task_id=""
map_file="llms-map.json"
max_files=""
max_bytes=""

usage() {
  cat <<USAGE
Usage: $0 --mode <plan|chunk|task> [--chunk <id>] [--task <id>] [--map <path>] [--max-files <n>] [--max-bytes <n>]
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --mode) mode="${2:-}"; shift 2 ;;
    --chunk) chunk_id="${2:-}"; shift 2 ;;
    --task) task_id="${2:-}"; shift 2 ;;
    --map) map_file="${2:-}"; shift 2 ;;
    --max-files) max_files="${2:-}"; shift 2 ;;
    --max-bytes) max_bytes="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [ -z "$mode" ]; then
  echo "error: --mode is required" >&2
  exit 1
fi

if [ ! -f "$map_file" ]; then
  echo "error: map file not found: $map_file" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  if [ "$mode" = "plan" ]; then
    printf '%s\n' \
      "docs/SPEC.md" \
      "llms-map.json"
    echo "warning: degraded mode (jq not found); returned default plan context" >&2
    exit 0
  fi
  echo "error: jq is required for chunk/task context resolution" >&2
  exit 1
fi

case "$mode" in
  plan)
    jq -r '
      (.baseline_read_order // [])[]
    ' "$map_file" ;;
  chunk)
    if [ -z "$chunk_id" ]; then
      echo "error: --chunk is required for --mode chunk" >&2
      exit 1
    fi
    if ! jq -e --arg chunk "$chunk_id" '.chunks[$chunk]' "$map_file" >/dev/null 2>&1; then
      echo "error: chunk not found in map: $chunk_id" >&2
      exit 1
    fi
    jq -r --arg chunk "$chunk_id" '
      [
        (.sub_agent_context.always_read // [])[],
        (.chunks[$chunk].docs // [])[],
        (.chunks[$chunk].capsule // empty)
      ]
      | unique
      | .[]
    ' "$map_file" ;;
  task)
    if [ -z "$task_id" ]; then
      echo "error: --task is required for --mode task" >&2
      exit 1
    fi
    if ! jq -e --arg task "$task_id" '.task_router[$task]' "$map_file" >/dev/null 2>&1; then
      echo "error: task not found in task_router: $task_id" >&2
      exit 1
    fi
    jq -r --arg task "$task_id" '
      . as $root
      |
      [
        ($root.sub_agent_context.always_read // [])[],
        ($root.task_router[$task].docs // [])[],
        (($root.task_router[$task].likely_chunks // [])
          | map(. as $c | ($root.chunks[$c].docs // []) + [($root.chunks[$c].capsule // empty)])
          | flatten
        )[]
      ]
      | map(select(. != null and . != ""))
      | unique
      | .[]
    ' "$map_file" ;;
  *)
    echo "error: invalid mode $mode" >&2
    exit 1 ;;
esac | awk 'NF{print}' | while IFS= read -r file; do
  echo "$file"
done | sort -u > "$tmpfile"

# Include preflight doc if configured and file exists.
preflight_doc="$(jq -r '.preflight.doc // empty' "$map_file" 2>/dev/null)"
if [ -n "$preflight_doc" ] && [ -f "$preflight_doc" ]; then
  if ! grep -qx "$preflight_doc" "$tmpfile" 2>/dev/null; then
    echo "$preflight_doc" >> "$tmpfile"
  fi
fi

# Emit knowledge pack URLs on stderr (stdout stays file-paths-only).
emit_knowledge_packs() {
  local chunk_id="$1"
  jq -r --arg chunk "$chunk_id" '
    (.chunks[$chunk].knowledge_packs // []) as $pack_ids
    | (.knowledge_packs // {}) as $packs
    | $pack_ids[]
    | . as $id
    | $packs[$id] // empty
    | "  \($id) kind=\(.kind) " +
      if .kind == "llms_txt" then
        "llms_txt_url=\(.llms_txt_url // "") llms_full_url=\(.llms_full_url // "")"
      else
        "url=\(.url // "")"
      end
  ' "$map_file" 2>/dev/null
}

case "$mode" in
  chunk)
    if [ -n "$chunk_id" ]; then
      kp_lines="$(emit_knowledge_packs "$chunk_id")"
      if [ -n "$kp_lines" ]; then
        echo "knowledge_packs chunk=$chunk_id" >&2
        echo "$kp_lines" >&2
      fi
    fi
    ;;
  task)
    if [ -n "$task_id" ]; then
      likely="$(jq -r --arg task "$task_id" '.task_router[$task].likely_chunks[]? // empty' "$map_file" 2>/dev/null)"
      for c in $likely; do
        kp_lines="$(emit_knowledge_packs "$c")"
        if [ -n "$kp_lines" ]; then
          echo "knowledge_packs chunk=$c" >&2
          echo "$kp_lines" >&2
        fi
      done
    fi
    ;;
esac

if [ -z "$max_files" ] || [ -z "$max_bytes" ]; then
  budgets="$(jq -r --arg mode "$mode" '.context_budgets[$mode] // {} | [.max_files // "", .max_bytes // ""] | @tsv' "$map_file")"
  [ -z "$max_files" ] && max_files="$(echo "$budgets" | awk -F'\t' '{print $1}')"
  [ -z "$max_bytes" ] && max_bytes="$(echo "$budgets" | awk -F'\t' '{print $2}')"
fi

files_count="$(wc -l < "$tmpfile" | tr -d ' ')"

bytes_total=0
while IFS= read -r file; do
  if [ -f "$file" ]; then
    size="$(wc -c < "$file" | tr -d ' ')"
    bytes_total=$((bytes_total + size))
  fi
done < "$tmpfile"

if [ -n "$max_files" ] && [ "$files_count" -gt "$max_files" ]; then
  echo "error: context pack has $files_count files, exceeds max_files=$max_files" >&2
  exit 1
fi

if [ -n "$max_bytes" ] && [ "$bytes_total" -gt "$max_bytes" ]; then
  echo "error: context pack has $bytes_total bytes, exceeds max_bytes=$max_bytes" >&2
  exit 1
fi

cat "$tmpfile"

echo "context_summary mode=$mode files=$files_count bytes=$bytes_total" >&2
