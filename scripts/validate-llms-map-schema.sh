#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

map_file="llms-map.json"
schema_file="$SKILL_DIR/assets/llms-map.schema.json"
strict_mode="false"

usage() {
  cat <<USAGE
Usage: $0 [--map <path>] [--schema <path>] [--strict]

Options:
  --map <path>     Path to llms-map.json (default: llms-map.json)
  --schema <path>  Path to JSON schema (default: <skill_dir>/assets/llms-map.schema.json)
  --strict         Fail if no full JSON Schema validator backend is available
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --map) map_file="${2:-}"; shift 2 ;;
    --schema) schema_file="${2:-}"; shift 2 ;;
    --strict) strict_mode="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [ ! -f "$map_file" ]; then
  echo "schema validation failed: map file not found: $map_file" >&2
  exit 1
fi

if [ ! -f "$schema_file" ]; then
  echo "schema validation failed: schema file not found: $schema_file" >&2
  exit 1
fi

# Backend 1: Python jsonschema (preferred).
if command -v python3 >/dev/null 2>&1; then
  if python3 -c 'import jsonschema' >/dev/null 2>&1; then
    python3 - "$map_file" "$schema_file" <<'PY'
import json
import sys

import jsonschema

map_path = sys.argv[1]
schema_path = sys.argv[2]

with open(map_path, encoding="utf-8") as f:
    payload = json.load(f)

with open(schema_path, encoding="utf-8") as f:
    schema = json.load(f)

jsonschema.validate(instance=payload, schema=schema)
print("llms-map schema validation passed (python jsonschema)")
PY
    exit 0
  fi
fi

# Backend 2: ajv-cli (if available).
if command -v ajv >/dev/null 2>&1; then
  ajv validate --spec=draft2020 -s "$schema_file" -d "$map_file" >/dev/null
  echo "llms-map schema validation passed (ajv)"
  exit 0
fi

if [ "$strict_mode" = "true" ]; then
  echo "schema validation failed: no full JSON Schema backend found (need python jsonschema or ajv)" >&2
  exit 1
fi

echo "warning: no full JSON Schema validator backend available; skipping strict schema validation" >&2
echo "warning: install python package 'jsonschema' or ajv-cli for full validation" >&2
echo "llms-map schema validation skipped (degraded mode)"

