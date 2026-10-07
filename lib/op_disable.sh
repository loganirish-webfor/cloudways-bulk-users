#!/usr/bin/env bash
# op_disable_site: revoke the employee's access on the current site without
# deleting anything. Reversible with op_restore_site via the marker usermeta.

app_passwords_delete_all() { # ID. rc 0 also when none exist (WP-CLI exits 0 then) or the feature is unavailable.
  local e
  wpx_nostdout user application-password delete "$1" --all && return 0
  # Only the "feature absent" messages of old WP / WP-CLI count as success
  # (WP < 5.6: "Requires WordPress 5.6 or greater."; old WP-CLI: subcommand not registered).
  # Each pattern is tied to application passwords so an unrelated "not available"
  # error cannot hide an unrevoked application password. Anything else is a failure.
  e="$(lower "$WP_ERR")"
  case "$e" in
    *"requires wordpress 5.6"*|*"application password"*"not available"*|*"application-password"*"not a registered subcommand"*)
      R_WARN="${R_WARN:+$R_WARN; }application passwords unavailable on this site"; return 0 ;;
  esac
  return 1
}

# Split comma-separated UROLES into the array ROLE_LIST without word splitting or globbing.
split_uroles() {
  ROLE_LIST=()
  IFS=, read -r -a ROLE_LIST <<< "$UROLES" || true
}

remove_all_roles() { # ID
  local id="$1" r
  user_roles "$id" || return 1
  split_uroles
  for r in ${ROLE_LIST[@]+"${ROLE_LIST[@]}"}; do
    valid_slug "$r" || { WP_ERR="Error: unusual role name '$r'"; WP_RC=1; return 1; }
  done
  for r in ${ROLE_LIST[@]+"${ROLE_LIST[@]}"}; do
    wpx_nostdout user remove-role "$id" "$r" || return 1
  done
  wpx_try user list-caps "$id" || return 1
  [ -z "$WP_OUT" ] || R_WARN="${R_WARN:+$R_WARN; }user still has direct capabilities"
  return 0
}

# Step 2. `user reset-password --skip-email` replaces the password with a random one
# (output discarded: WP-CLI may print it). wp_set_password() then sets a second random
# password and clears user_activation_key, so a "Lost your password?" link requested
# before the disable cannot be used afterwards. Neither call sends mail; the password
# is generated inside PHP, never on argv or stdout. ID is digits (from lookup_user).
scramble_password() { # ID
  case "$1" in ''|*[!0-9]*) WP_ERR="Error: invalid user id"; WP_RC=1; return 1 ;; esac
  wpx_nostdout user reset-password "$1" --skip-email || return 1
  wpx_nostdout eval "wp_set_password( wp_generate_password( 32, true, true ), $1 );"
}

disable_steps() { # ID RESUME ORIG_EMAIL
  local id="$1" resume="$2" orig_email="$3"
  if [ "$resume" -eq 0 ]; then
    MK_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    MK_SERVER="$(printf '%s' "$SERVER_NAME" | tr -c 'A-Za-z0-9._-' '_')"
    MK_ROLES="$UROLES"; MK_EMAIL="$orig_email"
    if ! marker_write "$id" in_progress; then
      record_result FAILED "marker not written, nothing changed: $(err_reason)"; return
    fi
  fi
  try_step 2 "password"             scramble_password "$id"
  try_step 3 "sessions"             wpx_nostdout user session destroy "$id" --all
  try_step 4 "application passwords" app_passwords_delete_all "$id"
  try_step 5 "roles"                remove_all_roles "$id"
  try_step 6 "email"                wpx_nostdout user update "$id" --user_email="disabled+${id}@webfor.invalid"
  if [ -n "$step_fail" ]; then
    record_result FAILED "PARTIAL (completed: 1${step_ok:+,$step_ok}; failed: $step_fail); re-run disable to resume"
    return
  fi
  if ! marker_write "$id" complete; then
    record_result FAILED "access removed but marker not finalised: $(err_reason)"; return
  fi
  record_result DISABLED "roles removed: ${MK_ROLES:-none}; email neutralised"
}

op_disable_site() {
  local id rc resume=0 orig_email="" r n_admins
  R_WP="Yes"
  lookup_user "$USERNAME" || { record_result FAILED "user lookup: $(err_reason)"; return; }
  if [ "$U_FOUND" -ne 1 ]; then
    R_ACTION="NONE"
    # No such username. If a different account holds the employee's email, say so
    # instead of reporting NOT FOUND (the person would keep access unnoticed).
    lookup_user "$EMAIL" || { R_EXISTS="-"; record_result FAILED "email lookup: $(err_reason)"; return; }
    if [ "$U_FOUND" -eq 1 ]; then
      R_EXISTS="Email under other login"
      record_result "EMAIL FOUND UNDER OTHER USERNAME" "email on user #$U_ID; nothing changed"; return
    fi
    R_EXISTS="No"; record_result "NOT FOUND" ""; return
  fi
  id="$U_ID"; R_EXISTS="Yes"
  user_roles "$id" || { record_result FAILED "role lookup: $(err_reason)"; return; }
  R_ROLE="${UROLES:--}"

  marker_read "$id"; rc=$?
  if [ "$rc" -eq 2 ]; then record_result FAILED "marker lookup: $(err_reason)"; return; fi
  if [ "$rc" -eq 0 ]; then
    if [ "$(lower "$MK_EMAIL")" != "$(lower "$EMAIL")" ]; then
      R_ACTION="NONE"; record_result "EMAIL MISMATCH" "stored email differs from --email"; return
    fi
    if [ "$MK_STATE" = "complete" ]; then R_ACTION="NONE"; record_result "ALREADY DISABLED" ""; return; fi
    resume=1
  else
    user_field "$id" user_email || { record_result FAILED "email lookup: $(err_reason)"; return; }
    orig_email="$UF"
    if [ "$(lower "$orig_email")" != "$(lower "$EMAIL")" ]; then
      R_ACTION="NONE"; record_result "EMAIL MISMATCH" "username exists with a different email"; return
    fi
    split_uroles
    for r in ${ROLE_LIST[@]+"${ROLE_LIST[@]}"}; do
      valid_slug "$r" || { R_ACTION="NONE"; record_result FAILED "unusual role name '$r'; handle manually"; return; }
    done
    if has_role "$UROLES" administrator; then
      wpx_try user list --role=administrator --field=ID || { record_result FAILED "administrator count: $(err_reason)"; return; }
      n_admins="$(printf '%s\n' "$WP_OUT" | grep -c .)"
      if [ "$n_admins" -le 1 ]; then
        R_ACTION="NONE"; record_result "LAST ADMIN" "only administrator on this site"; return
      fi
    fi
  fi

  R_ACTION="DISABLE"; [ "$resume" -eq 1 ] && R_ACTION="DISABLE (resume)"
  if [ "$EXECUTE" -ne 1 ]; then record_result "WOULD DISABLE" "roles: $([ "$resume" -eq 1 ] && printf '%s' "${MK_ROLES:-none}" || printf '%s' "${UROLES:-none}")"; return; fi
  disable_steps "$id" "$resume" "$orig_email"
}
