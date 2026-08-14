#!/usr/bin/env bash
# Common contract for Darwin/Linux boot backends. Sourced by boot.sh.

backend_error() {
    local title="$1" cause="$2" expected="$3" fix="$4"
    printf '\n[ERROR] %s\n\n[CAUSE]\n%s\n\n[EXPECTED]\n%s\n\n[SUGGESTED FIX]\n%s\n' \
        "$title" "$cause" "$expected" "$fix" >&2
}

backend_field() {
    local key="$1" data="$2"
    awk -F': ' -v key="$key" '$1 == key { print $2; exit }' <<<"$data"
}

backend_normalize() { tr '[:upper:]' '[:lower:]' <<<"$1"; }

backend_require_executable() {
    local name="$1" path="$2"
    [[ -n "$path" && -x "$path" ]] || {
        backend_error "Required tool unavailable" \
            "$name was not found or is not executable: ${path:-unset}." \
            "A configured executable for $name." \
            "Set ${name^^} to its path, or install the Linux runtime dependencies."
        return 1
    }
}

backend_with_timeout() {
    local seconds="$1"
    shift
    perl -e '
        use strict;
        use warnings;
        my $timeout = shift @ARGV;
        $SIG{ALRM} = sub { print STDERR "timed out after ${timeout}s: @ARGV\\n"; exit 124; };
        alarm $timeout;
        exec @ARGV or die "exec failed: $!\\n";
    ' "$seconds" "$@"
}
