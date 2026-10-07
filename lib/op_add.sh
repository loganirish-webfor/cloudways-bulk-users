#!/usr/bin/env bash
# op_add_site: create the employee on the current site unless they, or a
# conflicting account, already exist.
# Note: every WP-CLI call runs with plugins and themes skipped, so `role exists`
# cannot see roles that a plugin registers at runtime.

add_report_existing() { # ID of the account that already is the employee
  local id="$1" detail="" rc
  R_EXISTS="Yes"; R_ACTION="NONE"
  user_roles "$id" || { record_result FAILED "role lookup: $(err_reason)"; return; }
  R_ROLE="${UROLES:--}"
  marker_read "$id"; rc=$?
  if [ "$rc" -eq 2 ]; then record_result FAILED "marker lookup: $(err_reason)"; return; fi
  if [ "$rc" -eq 0 ]; then record_result "ALREADY EXISTS" "DISABLED, use restore"; return; fi
  has_role "$UROLES" "$ROLE" || detail="(role: ${UROLES:-none}, expected $ROLE)"
  record_result "ALREADY EXISTS" "$detail"
}

op_add_site() {
  local found_l id_l found_e id_e rc
  R_WP="Yes"
  lookup_user "$USERNAME" || { record_result FAILED "username lookup: $(err_reason)"; return; }
  found_l="$U_FOUND"; id_l="$U_ID"
  lookup_user "$EMAIL" || { record_result FAILED "email lookup: $(err_reason)"; return; }
  found_e="$U_FOUND"; id_e="$U_ID"

  if [ "$found_l" -eq 1 ] && [ "$found_e" -eq 1 ] && [ "$id_l" = "$id_e" ]; then
    add_report_existing "$id_l"; return
  fi
  if [ "$found_l" -eq 1 ] && [ "$found_e" -eq 0 ]; then
    # An account this tool disabled has its email swapped; recognise it by its marker.
    marker_read "$id_l"; rc=$?
    if [ "$rc" -eq 2 ]; then record_result FAILED "marker lookup: $(err_reason)"; return; fi
    if [ "$rc" -eq 0 ] && [ "$(lower "$MK_EMAIL")" = "$(lower "$EMAIL")" ]; then
      add_report_existing "$id_l"; return
    fi
    R_EXISTS="Yes (other email)"; R_ACTION="NONE"
    record_result "USERNAME CONFLICT" "username exists on user #$id_l with a different email"
    return
  fi
  if [ "$found_e" -eq 1 ]; then
    R_EXISTS="Email taken"; R_ACTION="NONE"
    if [ "$found_l" -eq 1 ]; then
      record_result "EMAIL CONFLICT" "email on user #$id_e; username on user #$id_l"
    else
      record_result "EMAIL CONFLICT" "email on user #$id_e"
    fi
    return
  fi

  R_EXISTS="No"
  if ! wpx_try role exists "$ROLE"; then
    # `role exists` exits 1 only for a missing role; timeouts, fatals and DB errors are other codes.
    if [ "$WP_RC" -eq 1 ] && [ -z "$(err_clean)" ]; then
      record_result FAILED "role '$ROLE' does not exist on this site"
    else
      record_result FAILED "role lookup: $(err_reason)"
    fi
    return
  fi
  R_ACTION="CREATE"
  if [ "$EXECUTE" -ne 1 ]; then record_result "WOULD CREATE" ""; return; fi

  local args=(user create "$USERNAME" "$EMAIL" --role="$ROLE" --first_name="$FIRST_NAME"
              --last_name="$LAST_NAME" --display_name="$DISPLAY_NAME" --porcelain)
  [ "$SEND_EMAIL" -eq 1 ] && args+=(--send-email)
  if wpx_try "${args[@]}"; then
    # WP_OUT is the numeric id with --porcelain. Never echo it unless it is purely digits.
    case "$WP_OUT" in ''|*[!0-9]*) record_result CREATED "" ;; *) record_result CREATED "user #$WP_OUT" ;; esac
  else
    record_result FAILED "$(err_reason)"
  fi
}
