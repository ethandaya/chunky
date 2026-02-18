#!/usr/bin/env bash
set -euo pipefail

root="${1:-.}"
map_file="$root/llms-map.json"

required_files="
llms.txt
llms-map.json
docs/SPEC.md
"

missing=0
for rel in $required_files; do
  if [ ! -e "$root/$rel" ]; then
    echo "missing required artifact: $rel" >&2
    missing=1
  fi
done

if [ "$missing" -ne 0 ]; then
  exit 1
fi

if [ ! -f "$map_file" ]; then
  echo "validation failed: llms-map.json not found" >&2
  exit 1
fi

if command -v jq >/dev/null 2>&1; then
  jq -e '.' "$map_file" >/dev/null || {
    echo "validation failed: llms-map.json is not valid JSON" >&2
    exit 1
  }

  jq -e '.schema_version and .updated and .chunks and .context_budgets and .sub_agent_context' "$map_file" >/dev/null || {
    echo "validation failed: missing required top-level keys (need schema_version, updated, chunks, context_budgets, sub_agent_context)" >&2
    exit 1
  }

  jq -e '.chunks | type=="object"' "$map_file" >/dev/null || {
    echo "validation failed: chunks must be an object" >&2
    exit 1
  }

  # Validate preflight doc exists if preflight.required is true.
  preflight_required="$(jq -r '.preflight.required // false' "$map_file")"
  preflight_doc="$(jq -r '.preflight.doc // empty' "$map_file")"
  if [ "$preflight_required" = "true" ] && [ -n "$preflight_doc" ] && [ ! -f "$root/$preflight_doc" ]; then
    echo "validation failed: preflight is required but doc not found: $preflight_doc" >&2
    exit 1
  fi

  # Validate knowledge_packs references in chunks point to defined packs.
  defined_packs="$(jq -r '.knowledge_packs // {} | keys[]' "$map_file" 2>/dev/null)"
  for chunk_kp in $(jq -r '.chunks | to_entries[] | select(.value.knowledge_packs) | .key as $c | .value.knowledge_packs[] | "\($c):\(.)"' "$map_file" 2>/dev/null); do
    c_id="${chunk_kp%%:*}"
    pack_id="${chunk_kp#*:}"
    echo "$defined_packs" | grep -qx "$pack_id" || {
      echo "validation failed: chunk $c_id references undefined knowledge_pack $pack_id" >&2
      exit 1
    }
  done

  chunk_ids="$(jq -r '.chunks | keys[]' "$map_file")"

  while IFS= read -r chunk; do
    [ -z "$chunk" ] && continue

    jq -e --arg c "$chunk" '
      .chunks[$c]
      | has("title", "target", "depends_on", "docs", "complexity")
    ' "$map_file" >/dev/null || {
      echo "validation failed: chunk missing required fields (need title, target, depends_on, docs, complexity): $chunk" >&2
      exit 1
    }

    deps="$(jq -r --arg c "$chunk" '.chunks[$c].depends_on[]? // empty' "$map_file")"
    for dep in $deps; do
      echo "$chunk_ids" | grep -qx "$dep" || {
        echo "validation failed: chunk $chunk depends on unknown chunk $dep" >&2
        exit 1
      }
    done

    docs="$(jq -r --arg c "$chunk" '.chunks[$c].docs[]? // empty' "$map_file")"
    for d in $docs; do
      [ -f "$root/$d" ] || {
        echo "validation failed: chunk $chunk references missing doc $d" >&2
        exit 1
      }
    done

    capsule="$(jq -r --arg c "$chunk" '.chunks[$c].capsule // empty' "$map_file")"
    if [ -n "$capsule" ] && [ ! -f "$root/$capsule" ]; then
      echo "validation failed: chunk $chunk references missing capsule $capsule" >&2
      exit 1
    fi
  done <<EOF_CHUNKS
$chunk_ids
EOF_CHUNKS
else
  echo "warning: degraded validation mode (jq not found)" >&2
  grep -q '"chunks"' "$map_file" || { echo "validation failed: chunks key missing" >&2; exit 1; }
fi

echo "agent context validation passed"
