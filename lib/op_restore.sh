#!/usr/bin/env bash
# op_restore_site: reverse a disable made by this tool, using the marker usermeta.
# The password stays scrambled; the employee sets a new one via "Lost your password?".

# Split the stored (comma-separated) MK_ROLES into the array MK_ROLE_LIST without
# word splitting or globbing.
split_mk_roles() {
  MK_ROLE_LIST=()
  IFS=, read -r -a MK_ROLE_LIST <<< "$MK_ROLES" || true
}

# Check every stored role slug; sets WP_ERR/WP_RC and returns 1 on the first bad one.
validate_mk_roles() {
  local r
  split_mk_roles
  for r in ${MK_ROLE_LIST[@]+"${MK_ROLE_LIST[@]}"}; do
    valid_slug "$r" || { WP_ERR="Error: unusual stored role name '$r'"; WP_RC=1; return 1; }
  done
  return 0
}

restore_roles() { # ID. Re-adds every stored role; validates all of them before adding any.
  local id="$1" r
  validate_mk_roles || return 1
  for r in ${MK_ROLE_LIST[@]+"${MK_ROLE_LIST[@]}"}; do
    wpx_nostdout user add-role "$id" "$r" || return 1
  done
  return 0
}

op_restore_site() {
  local id rc
  R_WP="Yes"
  lookup_user "$USERNAME" || { record_result FAILED "user lookup: $(err_reason)"; return; }
  if [ "$U_FOUND" -ne 1 ]; then R_EXISTS="No"; R_ACTION="NONE"; record_result "NOT FOUND" ""; return; fi
  id="$U_ID"; R_EXISTS="Yes"
  user_roles "$id" || { record_result FAILED "role lookup: $(err_reason)"; return; }
  R_ROLE="${UROLES:--}"

  marker_read "$id"; rc=$?
  if [ "$rc" -eq 2 ]; then record_result FAILED "marker lookup: $(err_reason)"; return; fi
  if [ "$rc" -eq 1 ]; then R_ACTION="NONE"; record_result "NOT DISABLED" "no marker; nothing to restore"; return; fi
  if [ "$(lower "$MK_EMAIL")" != "$(lower "$EMAIL")" ]; then
    R_ACTION="NONE"; record_result "EMAIL MISMATCH" "stored email differs from --email"; return
  fi
  # A bad stored role would otherwise leave a half-restored user: refuse before touching anything.
  if ! validate_mk_roles; then R_ACTION="NONE"; record_result FAILED "$(err_reason); handle manually"; return; fi
  lookup_user "$MK_EMAIL" || { record_result FAILED "email lookup: $(err_reason)"; return; }
  if [ "$U_FOUND" -eq 1 ] && [ "$U_ID" != "$id" ]; then
    R_ACTION="NONE"; record_result "EMAIL CONFLICT" "original email now on user #$U_ID"; return
  fi

  R_ACTION="RESTORE"
  if [ "$EXECUTE" -ne 1 ]; then record_result "WOULD RESTORE" "roles: ${MK_ROLES:-none}"; return; fi

  # Order matters: email, then roles, then the marker. A failed earlier step keeps the marker so restore can be re-run.
  try_step 1 "email" wpx_nostdout user update "$id" --user_email="$MK_EMAIL"
  try_step 2 "roles" restore_roles "$id"
  if [ -n "$step_fail" ]; then
    record_result FAILED "PARTIAL (completed: ${step_ok:-none}; failed: $step_fail); marker kept, re-run restore"
    return
  fi
  try_step 3 "marker" wpx_nostdout user meta delete "$id" "$MARKER_KEY"
  if [ -n "$step_fail" ]; then
    record_result FAILED "access restored but marker not removed: $step_fail"; return
  fi
  R_WARN="password stays unusable; employee must use Lost your password"
  [ -n "$MK_ROLES" ] || R_WARN="$R_WARN; account had no roles when disabled"
  record_result RESTORED "roles: ${MK_ROLES:-none}"
}
