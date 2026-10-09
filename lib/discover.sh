#!/usr/bin/env bash
# Application discovery and per-site validation. Read-only.

discover_apps() {
  local d
  for d in "$APPS_ROOT"/*/; do
    [ -d "$d" ] || continue
    basename "$d"
  done | sort
}

# app_realpath FOLDER -> the physical path of $APPS_ROOT/FOLDER (symlinks resolved); empty if it does not exist.
app_realpath() { ( cd -P "$APPS_ROOT/$1" 2>/dev/null && pwd -P ); }

# collapse_aliases: Cloudways lists each site twice under the apps root, the real folder
# (random id) and a friendly-name symlink to it (29 of 62 entries on one live server).
# Keep one entry per physical folder, preferring the real folder over a symlink, and
# record the dropped names in ALIAS_SKIPPED. A folder that does not resolve is kept as
# it is (validate_site reports it), and so is a symlink that points at something else.
collapse_aliases() {
  local n=${#TARGETS[@]} i j li lj drop keep=() paths=()
  ALIAS_SKIPPED=()
  [ "$n" -gt 0 ] || return 0
  for ((i = 0; i < n; i++)); do paths[i]="$(app_realpath "${TARGETS[i]}")"; done
  for ((i = 0; i < n; i++)); do
    drop=0
    if [ -n "${paths[i]}" ]; then
      li=0; [ -L "$APPS_ROOT/${TARGETS[i]}" ] && li=1
      for ((j = 0; j < n; j++)); do
        [ "$j" -ne "$i" ] && [ "${paths[j]}" = "${paths[i]}" ] || continue
        lj=0; [ -L "$APPS_ROOT/${TARGETS[j]}" ] && lj=1
        if [ "$li" -gt "$lj" ] || { [ "$li" -eq "$lj" ] && [ "$j" -lt "$i" ]; }; then drop=1; break; fi
      done
    fi
    if [ "$drop" -eq 1 ]; then ALIAS_SKIPPED+=("${TARGETS[i]}"); else keep+=("${TARGETS[i]}"); fi
  done
  if [ ${#keep[@]} -eq 0 ]; then TARGETS=(); else TARGETS=("${keep[@]}"); fi
}

# validate_site: needs SITE_FOLDER. rc 0 usable (sets SITE_PATH, SITE_LABEL, R_WP).
# rc 1 unusable (sets V_STATUS, V_DETAIL).
validate_site() {
  local dir="$APPS_ROOT/$SITE_FOLDER"
  V_STATUS=""; V_DETAIL=""
  SITE_LABEL="(app: $SITE_FOLDER)"
  if [ ! -d "$dir" ]; then V_STATUS=SKIPPED; V_DETAIL="no such application folder"; return 1; fi
  SITE_PATH="$dir/public_html"
  if [ ! -d "$SITE_PATH" ]; then R_WP="No"; V_STATUS=SKIPPED; V_DETAIL="no public_html"; return 1; fi
  if ! wpx_try core is-installed; then
    R_WP="No"
    case "$WP_ERR" in
      *"does not seem to be a WordPress installation"*)
        V_STATUS=SKIPPED; V_DETAIL="not WordPress" ;;
      *)
        if [ "$WP_RC" -eq 1 ] && [ -z "$(err_clean)" ]; then
          # Silent exit 1: either WordPress is not installed, or the database is unreachable.
          if wpx_try db query "SELECT 1"; then
            V_STATUS=SKIPPED; V_DETAIL="WordPress files found but not installed"
          else
            V_STATUS=FAILED; V_DETAIL="database not reachable: $(err_reason)"
          fi
        else
          V_STATUS=FAILED; V_DETAIL="WP-CLI error: $(err_reason)"
        fi ;;
    esac
    return 1
  fi
  R_WP="Yes"
  if wpx_try core is-installed --network; then
    V_STATUS=SKIPPED; V_DETAIL="multisite, handle manually"; return 1
  fi
  if wpx_try option get siteurl && [ -n "$WP_OUT" ]; then SITE_LABEL="$WP_OUT (app: $SITE_FOLDER)"; fi
  return 0
}
