#!/bin/sh

# Generate BuildRequires for Rust projects from Cargo.lock.
# This shell implementation avoids Python dependencies in rpmbuild.

set -u

print_err() {
    printf '%s\n' "$*" >&2
}

clean_version() {
    case "$1" in
        *+*) printf '%s\n' "${1%%+*}" ;;
        *) printf '%s\n' "$1" ;;
    esac
}

usage() {
    print_err "Usage: cargo_buildrequires.sh --output <file> [--registry <path>]"
    exit 1
}

REGISTRY_PATH="/usr/share/cargo/registry"
OUTPUT_FILE=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        -d|--dev)
            shift
            ;;
        -b|--build)
            shift
            ;;
        --registry)
            [ "$#" -ge 2 ] || usage
            REGISTRY_PATH="$2"
            shift 2
            ;;
        --output)
            [ "$#" -ge 2 ] || usage
            OUTPUT_FILE="$2"
            shift 2
            ;;
        *)
            usage
            ;;
    esac
done

[ -n "$OUTPUT_FILE" ] || usage

if [ ! -f Cargo.lock ]; then
    print_err "Error: Cargo.lock not found"
    print_err "Hint: Run 'cargo generate-lockfile' or 'cargo update' to generate it"
    exit 1
fi

output_dir=$(dirname "$OUTPUT_FILE")
mkdir -p "$output_dir"

tmp_output=$(mktemp)
tmp_packages=$(mktemp)
trap 'rm -f "$tmp_output" "$tmp_packages"' EXIT INT TERM

printf 'rust\n' > "$tmp_output"

awk '
function flush_pkg() {
    if (in_pkg && name != "" && version != "") {
        printf "%s\t%s\t%s\n", name, version, source
    }
}
BEGIN {
    in_pkg = 0
    name = ""
    version = ""
    source = ""
}
/^\[\[package\]\]/ {
    flush_pkg()
    in_pkg = 1
    name = ""
    version = ""
    source = ""
    next
}
in_pkg && /^name[[:space:]]*=/ {
    line = $0
    sub(/^[^=]*=[[:space:]]*"/, "", line)
    sub(/"[[:space:]]*$/, "", line)
    name = line
    next
}
in_pkg && /^version[[:space:]]*=/ {
    line = $0
    sub(/^[^=]*=[[:space:]]*"/, "", line)
    sub(/"[[:space:]]*$/, "", line)
    version = line
    next
}
in_pkg && /^source[[:space:]]*=/ {
    line = $0
    sub(/^[^=]*=[[:space:]]*"/, "", line)
    sub(/"[[:space:]]*$/, "", line)
    source = line
    next
}
END {
    flush_pkg()
}
' Cargo.lock > "$tmp_packages"

dep_count=0
missing_requirements=0

while IFS="$(printf '\t')" read -r crate_name crate_version source; do
    [ -n "$crate_name" ] || continue
    [ -n "$crate_version" ] || continue

    if [ -z "$source" ]; then
        print_err "Skipping current project: $crate_name $crate_version"
        continue
    fi

    case "$source" in
        file://*)
            print_err "Skipping local dependency: $crate_name $crate_version ($source)"
            continue
            ;;
        git+*)
            print_err "Skipping git dependency: $crate_name $crate_version ($source)"
            continue
            ;;
    esac

    dep_count=$((dep_count + 1))

    is_installed=0
    if [ -d "$REGISTRY_PATH" ]; then
        for d in "$REGISTRY_PATH/$crate_name"-*; do
            [ -d "$d" ] || continue
            dir_name=${d##*/}
            remainder=${dir_name#"$crate_name"-}
            case "$remainder" in
                [0-9]*)
                    is_installed=1
                    break
                    ;;
            esac
        done
    fi

    normalized_name=$(printf '%s' "$crate_name")
    clean_ver=$(clean_version "$crate_version")
    dep_full="crate($normalized_name) >= $clean_ver"

    if [ "$is_installed" -eq 1 ]; then
        :
        # print_err "[OK] Requirement satisfied: $crate_name-$crate_version (installed)"
    else
        # print_err "[MISSING] Requirement not satisfied: $crate_name-$crate_version"
        missing_requirements=1
    fi

    printf '%s\n' "$dep_full" >> "$tmp_output"
done < "$tmp_packages"

print_err ""
print_err "Found $dep_count dependencies in Cargo.lock"

mv "$tmp_output" "$OUTPUT_FILE"
print_err "Generated BuildRequires written to: $OUTPUT_FILE"

if [ "$missing_requirements" -eq 1 ]; then
    print_err ""
    print_err "Missing dependencies detected - triggering OBS bootstrap cycle"
    exit 0
fi

print_err ""
print_err "All dependencies satisfied"
exit 0
