#!/usr/bin/env bash
set -euo pipefail

map_file="llms-map.json"
done_file=""
output_mode="waves"

usage() {
  cat <<USAGE
Usage: $0 [--map <path>] [--done <path>] [--waves | --next]

Derive execution waves from chunk dependency graph.

Options:
  --map <path>    Path to llms-map.json (default: llms-map.json)
  --done <path>   File with completed chunk IDs (one per line)
  --waves         Print all waves with chunk IDs (default)
  --next          Print only the next runnable chunk IDs
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --map)
      [ -n "${2:-}" ] || { echo "error: --map requires a value" >&2; exit 1; }
      map_file="$2"; shift 2 ;;
    --done)
      [ -n "${2:-}" ] || { echo "error: --done requires a value" >&2; exit 1; }
      done_file="$2"; shift 2 ;;
    --waves) output_mode="waves"; shift ;;
    --next) output_mode="next"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [ ! -f "$map_file" ]; then
  echo "error: map file not found: $map_file" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required for wave planning" >&2
  exit 1
fi

# Load done chunks as JSON array.
done_json="[]"
if [ -n "$done_file" ]; then
  if [ -f "$done_file" ]; then
    done_json="$(jq -Rsc 'split("\n") | map(gsub("^\\s+|\\s+$";"")) | map(select(length > 0))' "$done_file")"
  else
    echo "warning: done file not found (treating as none completed): $done_file" >&2
  fi
fi

# Derive waves from dependency graph.
result="$(jq --argjson done "$done_json" '
  (.chunks // {}) as $chunks |
  ($chunks | keys) as $all_ids |
  ($done | map(. as $d | select($all_ids | index($d))) ) as $done_set |

  # Validate all depends_on references point to real chunks.
  ([ $all_ids[] | . as $id |
    ($chunks[$id].depends_on // [])[] |
    select(. as $dep | $all_ids | index($dep) | not) |
    "\(.) (referenced by \($id))"
  ] | unique) as $unknown_deps |
  if ($unknown_deps | length) > 0 then
    { error: "unknown dependencies: \($unknown_deps | join(", "))", waves: [], scheduled: [], remaining: [] }
  else

  # Iteratively schedule waves (max iterations = number of chunks to prevent infinite loops).
  ($all_ids | length) as $max_iter |
  { scheduled: $done_set, waves: [], remaining: ($all_ids - $done_set), iter: 0, error: null } |
  until((.remaining | length) == 0 or (.error != null) or (.iter >= $max_iter);
    .scheduled as $sched |
    .remaining as $rem |
    .iter as $i |
    # Find chunks whose deps are all in scheduled set.
    [ $rem[] | select(
      . as $id |
      ($chunks[$id].depends_on // []) |
      all(. as $dep | $sched | index($dep))
    ) ] as $runnable |
    if ($runnable | length) == 0 then
      .error = "cycle detected: cannot schedule chunks: \($rem | join(", "))"
    else
      .waves += [$runnable] |
      .scheduled += $runnable |
      .remaining -= $runnable |
      .iter = ($i + 1)
    end
  ) |
  # Check for unscheduled chunks after max iterations (also a cycle).
  if .error == null and (.remaining | length) > 0 then
    .error = "cycle detected: cannot schedule chunks: \(.remaining | join(", "))"
  else . end

  end
' "$map_file")"

# Check for cycle error.
error="$(echo "$result" | jq -r '.error // empty' 2>/dev/null)"
if [ -n "$error" ]; then
  echo "error: $error" >&2
  exit 1
fi

case "$output_mode" in
  waves)
    echo "$result" | jq -r '
      .waves | to_entries[] |
      "wave_\(.key + 1): \(.value | join(" "))"
    '
    wave_count="$(echo "$result" | jq '.waves | length')"
    total_chunks="$(echo "$result" | jq '[.waves[] | length] | add // 0')"
    echo "waves=$wave_count chunks=$total_chunks" >&2
    ;;
  next)
    next_wave="$(echo "$result" | jq -r '.waves[0] // [] | .[]')"
    if [ -z "$next_wave" ]; then
      echo "all chunks completed" >&2
      exit 0
    fi
    echo "$next_wave"
    count="$(echo "$next_wave" | wc -l | tr -d ' ')"
    echo "next_runnable=$count" >&2
    ;;
esac
