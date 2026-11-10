#!/usr/bin/env bash
# Text checks for the extension boundaries (0A.09-T6). Usage: extension-lint.sh [core_dir] [extensions_dir]
set -uo pipefail
CORE="${1:-supabase/migrations}"
EXT="${2:-supabase/extensions}"
status=0
core_schemas='(public|app|auth|storage|realtime|vault)'

# 1. Core migrations must not depend on an extension (schema-qualified ext_<name>. references).
if grep -nE '(^|[^a-z0-9_])ext_[a-z0-9_]+\.' "$CORE"/*.sql 2>/dev/null; then
  echo "LINT [core_references_extension] a core migration references an extension schema; the core must work without it." >&2
  status=1
fi

# 2. Extension migrations must not change core objects.
shopt -s nullglob
for f in "$EXT"/*/migrations/*.sql; do
  body="$(sed 's/--.*$//' "$f" | tr '\n' ' ' | sed 's/;/;\n/g')"
  bad="$(printf '%s\n' "$body" | grep -niE \
    -e "\b(alter|drop|truncate)\s+(table|view|function|policy|trigger|index|type|schema)\s+(if\s+exists\s+)?${core_schemas}\." \
    -e "\b(update|delete\s+from)\s+${core_schemas}\." \
    -e "\bcreate\s+(or\s+replace\s+)?(trigger|policy|index)\b[^;]*\bon\s+${core_schemas}\." \
    -e "\bcreate\s+or\s+replace\s+function\s+${core_schemas}\." \
    -e "\binsert\s+into\s+${core_schemas}\.[a-z_]+" )"
  bad="$(printf '%s\n' "$bad" | grep -viE "insert\s+into\s+public\.(extensions|event_definitions|event_listeners)\b" | grep -v '^$')"
  if [[ -n "$bad" ]]; then
    echo "$f:" >&2
    printf '%s\n' "$bad" >&2
    echo "LINT [extension_changes_core] an extension migration changes core objects; use core RPCs and events instead." >&2
    status=1
  fi
done
exit $status
