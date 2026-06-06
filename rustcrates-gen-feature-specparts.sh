#!/bin/bash
set -euo pipefail

SOURCEDIR="${1:-}"

if [[ -z "$SOURCEDIR" ]]; then
  echo "usage: $0 SOURCEDIR" >&2
  exit 2
fi

if [[ -z "${RPM_SPECPARTS_DIR:-}" || ! -d "$RPM_SPECPARTS_DIR" ]]; then
  echo "error: dynamic spec generation is not supported by this RPM version (missing RPM_SPECPARTS_DIR)" >&2
  exit 1
fi

set -- "$SOURCEDIR"/*.spec
SPEC_SELF="$1"

SPECPART="$RPM_SPECPARTS_DIR/50-feature-files.specpart"
: > "$SPECPART"

if [[ ! -f "$SPEC_SELF" ]]; then
  echo "warning: no spec file found in $SOURCEDIR" >&2
  exit 0
fi

if ! awk '
  /^[[:space:]]*%package[[:space:]]+/ {
    if (match($0, /-n[[:space:]]+%\{name\}\+([A-Za-z0-9_.-]+)/, m) && !seen[m[1]]++) {
      print "%files -n %{name}+" m[1]
      print ""
      found = 1
    }
  }

  END {
    exit(found ? 0 : 2)
  }
' "$SPEC_SELF" >> "$SPECPART"; then
  echo "warning: no feature subpackages parsed from $SPEC_SELF" >&2
fi

