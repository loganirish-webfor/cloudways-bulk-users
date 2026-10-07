#!/usr/bin/env bash
# Per-site result state, console report, TSV, totals, exit code.

RES_LABEL=(); RES_FOLDER=(); RES_WP=(); RES_EXISTS=(); RES_ROLE=()
RES_ACTION=(); RES_STATUS=(); RES_DETAIL=(); RES_WARN=()

reset_site_state() {
  SITE_PATH=""; SITE_LABEL=""
  R_WP="-"; R_EXISTS="-"; R_ROLE="-"; R_ACTION="-"; R_WARN=""
  step_ok=""; step_fail=""
  UF=""; UROLES=""
}

is_review_status() {
  case "$1" in
    "EMAIL CONFLICT"|"USERNAME CONFLICT"|"EMAIL MISMATCH"|"LAST ADMIN") return 0 ;;
  esac
  return 1
}

# record_result STATUS [DETAIL] : the one place a site's outcome is stored.
record_result() {
  local status="$1" detail="${2:-}" label="${SITE_LABEL:-(app: $SITE_FOLDER)}"
  RES_LABEL+=("$label"); RES_FOLDER+=("$SITE_FOLDER"); RES_WP+=("$R_WP")
  RES_EXISTS+=("$R_EXISTS"); RES_ROLE+=("$R_ROLE"); RES_ACTION+=("$R_ACTION")
  RES_STATUS+=("$status"); RES_DETAIL+=("$detail"); RES_WARN+=("$R_WARN")
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(tsv_clean "$label")" "$SITE_FOLDER" "$R_WP" "$R_EXISTS" "$(tsv_clean "$R_ROLE")" \
    "$R_ACTION" "$status" "$(tsv_clean "$detail")" "$(tsv_clean "$R_WARN")" >> "$TSV_FILE"
  log_line "RESULT $SITE_FOLDER: $status${detail:+ - $detail}"
  [ "$status" = FAILED ] && log_line "ERROR $SITE_FOLDER: $detail"
  return 0
}

display_status() { # index
  local s="${RES_STATUS[$1]}" d="${RES_DETAIL[$1]}"
  is_review_status "$s" && s="$s - REVIEW REQUIRED"
  [ -n "$d" ] && s="$s - $d"
  printf '%s' "$s"
}

print_report() {
  local i n=${#RES_STATUS[@]} s found=0
  say ""
  say "$MODE RESULTS: $OPERATION $USERNAME <$EMAIL> server=$SERVER_NAME"
  say "SITE | WP | USER EXISTS | ROLE | ACTION | RESULT | WARNINGS"
  for ((i = 0; i < n; i++)); do
    say "${RES_LABEL[$i]} | ${RES_WP[$i]} | ${RES_EXISTS[$i]} | ${RES_ROLE[$i]} | ${RES_ACTION[$i]} | $(display_status "$i") | ${RES_WARN[$i]:--}"
  done
  say ""
  say "Totals:"
  printf '%s\n' "${RES_STATUS[@]}" | sort | uniq -c | while read -r c s; do say "  $s: $c"; done
  say "  Applications processed: $n"
  for ((i = 0; i < n; i++)); do
    s="${RES_STATUS[$i]}"
    if [ "$s" = FAILED ] || [ "$s" = SKIPPED ] || is_review_status "$s"; then
      if [ "$found" -eq 0 ]; then say ""; say "Needs manual review:"; found=1; fi
      say "  - ${RES_LABEL[$i]}: $(display_status "$i")"
    fi
  done
  if [ "$EXECUTE" -ne 1 ]; then say ""; say "DRY RUN: no changes were made."; fi
}

# run_exit_code: 1 if any FAILED or review status, else 0.
run_exit_code() {
  local s
  for s in "${RES_STATUS[@]}"; do
    if [ "$s" = FAILED ] || is_review_status "$s"; then return 1; fi
  done
  return 0
}
