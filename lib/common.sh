#!/usr/bin/env bash
# Shared helpers: usage errors, logging, input validation.

die_usage() { printf 'error: %s\n' "$*" >&2; exit 2; }

lower() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }

log_line() {
  [ -n "${LOG_FILE:-}" ] || return 0
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

# say: print to the console and the log.
say() { printf '%s\n' "$*"; log_line "$*"; }

# A leading '-' is rejected so a name can never be taken for a wp flag.
valid_username() { [[ "$1" =~ ^[a-z0-9._-]+$ ]] && [[ ! "$1" =~ ^[0-9]+$ ]] && [[ "$1" != -* ]]; }
valid_email() {
  local re='^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
  [[ "$1" =~ $re ]]
}
valid_slug()   { [[ "$1" =~ ^[a-z0-9_-]+$ ]]; }
valid_folder() { [[ "$1" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]*$ ]]; }
email_in_domain() { [ "$(lower "${1##*@}")" = "$(lower "$2")" ]; }
tsv_clean() { printf '%s' "$1" | tr '\t\n\r' '   '; }
