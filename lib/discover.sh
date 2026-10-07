#!/usr/bin/env bash
# Application discovery and per-site validation. Read-only.

discover_apps() {
  local d
  for d in "$APPS_ROOT"/*/; do
    [ -d "$d" ] || continue
    basename "$d"
  done | sort
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
