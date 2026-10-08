# --- NOT FOUND is only for a site where neither the username nor the email exists ---
fixtures_reset
nf_before="$(fp app_a)$(fp app_b)"
run_tool "${DIS[@]}" --sites app_a,app_b --execute
assert_eq "NOT FOUND" "$(status_of app_a)" "neither username nor email exists: NOT FOUND"
assert_eq "NOT FOUND" "$(status_of app_b)" "second such site: NOT FOUND"
assert_eq 0 "$RC" "all NOT FOUND exits 0"
assert_eq "$nf_before" "$(fp app_a)$(fp app_b)" "NOT FOUND changed nothing"

# --- email held by a different username: review, never NOT FOUND --------------------
fixtures_reset
et_before="$(fp app_emailtaken)"
run_tool "${DIS[@]}" --sites app_emailtaken --execute
assert_eq "EMAIL FOUND UNDER OTHER USERNAME" "$(status_of app_emailtaken)" "email on another username: EMAIL FOUND UNDER OTHER USERNAME"
assert_contains "$(detail_of app_emailtaken)" "email on user #" "detail names the account id"
assert_contains "$(detail_of app_emailtaken)" "nothing changed" "detail says nothing changed"
assert_eq "Email under other login" "$(tsv_col app_emailtaken 4)" "USER EXISTS column says the email is under another login"
assert_contains "$OUT" "EMAIL FOUND UNDER OTHER USERNAME - REVIEW REQUIRED" "shown as REVIEW REQUIRED"
assert_eq 1 "$RC" "email under another username exits 1"
assert_eq "$et_before" "$(fp app_emailtaken)" "that site is unchanged even with --execute"

prep_jane
assert_eq yes "$(auth_ok app_a jane.doe known-pass-1)" "precondition: password works"
assert_eq yes "$(app_pw_ok app_a jane.doe "$APP_PW_app_a")" "precondition: app password works"

# --- dry run ------------------------------------------------------------------
before="$(all_fp)"
run_tool "${DIS[@]}" --all
assert_eq "$before" "$(all_fp)" "disable dry run leaves every database identical"
assert_eq "WOULD DISABLE" "$(status_of app_a)" "app_a: WOULD DISABLE"
assert_eq "WOULD DISABLE" "$(status_of app_b)" "app_b: WOULD DISABLE"
assert_eq "EMAIL FOUND UNDER OTHER USERNAME" "$(status_of app_emailtaken)" "email held by another username: EMAIL FOUND UNDER OTHER USERNAME"
assert_eq "EMAIL MISMATCH" "$(status_of app_usertaken)" "same username, different email: EMAIL MISMATCH"
assert_eq "LAST ADMIN" "$(status_of app_soleadmin)" "only administrator: LAST ADMIN"
assert_contains "$OUT" "LAST ADMIN - REVIEW REQUIRED" "last admin shows REVIEW REQUIRED"

# --- guards hold on a live run ------------------------------------------------
g_before="$(fp app_usertaken)$(fp app_soleadmin)$(fp app_emailtaken)"
run_tool "${DIS[@]}" --sites app_usertaken,app_soleadmin,app_emailtaken --execute
assert_eq "$g_before" "$(fp app_usertaken)$(fp app_soleadmin)$(fp app_emailtaken)" "guarded sites unchanged"

# --- live disable ----------------------------------------------------------------
reset_key="$(fwp app_a eval '$u = get_user_by( "login", "jane.doe" ); echo get_password_reset_key( $u );')"
key_state() { fwp app_a eval "\$r = check_password_reset_key( '$reset_key', 'jane.doe' ); echo is_wp_error( \$r ) ? 'dead' : 'valid';"; }
assert_eq valid "$(key_state)" "precondition: a Lost-your-password key requested before the disable is valid"
users_before="$(user_count app_a)"
admin_before="$(fwp app_a user get admin --field=user_email)"
run_tool "${DIS[@]}" --sites app_a,app_b --execute
assert_eq 0 "$RC" "live disable exits 0"
assert_eq dead "$(key_state)" "pre-existing password reset key is dead after disable"
for a in app_a app_b; do
  id="$(eval "printf '%s' \"\$LID_$a\"")"
  pw="$(eval "printf '%s' \"\$APP_PW_$a\"")"
  assert_eq DISABLED "$(status_of "$a")" "$a: DISABLED"
  assert_eq no "$(auth_ok "$a" jane.doe known-pass-1)" "$a: old password rejected"
  assert_eq no "$(app_pw_ok "$a" jane.doe "$pw")" "$a: application password revoked"
  assert_eq '[]' "$(fwp "$a" user session list "$id" --format=json)" "$a: sessions destroyed"
  assert_eq "" "$(roles_sorted "$a" jane.doe)" "$a: no roles"
  assert_eq "" "$(fwp "$a" user list-caps "$id")" "$a: no capabilities"
  assert_eq "disabled+$id@webfor.invalid" "$(fwp "$a" user get "$id" --field=user_email)" "$a: email neutralised"
  assert_eq "$id" "$(fwp "$a" user get jane.doe --field=ID)" "$a: user record kept"
  assert_eq 1 "$(fwp "$a" post list --author="$id" --post_status=any --format=count)" "$a: authored content kept"
  assert_contains "$(fwp "$a" user meta get "$id" webfor_disabled --format=json)" '"state":"complete"' "$a: marker complete"
  assert_contains "$(fwp "$a" user meta get "$id" webfor_disabled --format=json)" '"email":"jane.doe@webfor.com"' "$a: marker keeps the original email (restore needs it)"
  assert_eq 0 "$(mail_count "$a")" "$a: no mail sent"
done
assert_contains "$(fwp app_b user meta get "$LID_app_b" webfor_disabled --format=json)" '"roles":["administrator","editor"]' "app_b: both roles recorded"
assert_eq "$users_before" "$(user_count app_a)" "no users added or removed"
assert_eq "$admin_before" "$(fwp app_a user get admin --field=user_email)" "other admin untouched"

# --- idempotent ----------------------------------------------------------------
after="$(fp app_a)"
run_tool "${DIS[@]}" --sites app_a --execute
assert_eq "ALREADY DISABLED" "$(status_of app_a)" "second disable: ALREADY DISABLED"
assert_eq "$after" "$(fp app_a)" "second disable changed nothing"

# --- review focus 3: add after disable ---------------------------------------
run_tool "${ADD[@]}" --sites app_a --execute
assert_eq "ALREADY EXISTS" "$(status_of app_a)" "add after disable: ALREADY EXISTS"
assert_contains "$(detail_of app_a)" "DISABLED, use restore" "add after disable points to restore"
assert_eq "$after" "$(fp app_a)" "add after disable changed nothing"

# --- review focus 2: disable guard is case-insensitive on email ----------------
prep_jane
run_tool disable --username jane.doe --email JANE.DOE@WEBFOR.COM --sites app_a --execute
assert_eq DISABLED "$(status_of app_a)" "mixed-case --email still matches the account"

# --- email mismatch on an already-disabled account is refused -------------------
run_tool disable --username jane.doe --email other.person@webfor.com --sites app_a --execute
assert_eq "EMAIL MISMATCH" "$(status_of app_a)" "disable with the wrong email is refused"

# --- resume: hand-built in_progress marker, role already removed ------------------
prep_jane
id="$LID_app_a"
mk='{"at":"2026-01-02T03:04:05Z","server":"oldsrv","roles":["administrator"],"email":"jane.doe@webfor.com","state":"in_progress"}'
fwp app_a user meta update "$id" webfor_disabled "$mk" --format=json >/dev/null
fwp app_a user remove-role "$id" administrator >/dev/null
r_before="$(fp app_a)"
run_tool "${DIS[@]}" --sites app_a
assert_eq "WOULD DISABLE" "$(status_of app_a)" "resume dry run: WOULD DISABLE"
assert_eq "DISABLE (resume)" "$(tsv_col app_a 6)" "resume dry run: action is DISABLE (resume)"
assert_contains "$(detail_of app_a)" "roles: administrator" "resume dry run reports the stored roles"
assert_eq "$r_before" "$(fp app_a)" "resume dry run changed nothing"
run_tool "${DIS[@]}" --sites app_a --execute
assert_eq 0 "$RC" "resume live run exits 0"
assert_eq DISABLED "$(status_of app_a)" "resume: DISABLED"
r_mk="$(fwp app_a user meta get "$id" webfor_disabled --format=json)"
assert_contains "$r_mk" '"state":"complete"' "resume: marker complete"
assert_contains "$r_mk" '"at":"2026-01-02T03:04:05Z"' "resume: stored timestamp kept"
assert_contains "$r_mk" '"server":"oldsrv"' "resume: stored server kept"
assert_contains "$r_mk" '"roles":["administrator"]' "resume: stored roles kept (not the demoted current state)"
assert_contains "$r_mk" '"email":"jane.doe@webfor.com"' "resume: stored email kept"
assert_eq no "$(auth_ok app_a jane.doe known-pass-1)" "resume: old password rejected"
assert_eq no "$(app_pw_ok app_a jane.doe "$APP_PW_app_a")" "resume: application password revoked"
assert_eq '[]' "$(fwp app_a user session list "$id" --format=json)" "resume: sessions destroyed"
assert_eq "disabled+$id@webfor.invalid" "$(fwp app_a user get "$id" --field=user_email)" "resume: email neutralised"
assert_eq 0 "$(mail_count app_a)" "resume: no mail sent"

# --- reset key is dead after step 2 already, even if the email step (6) fails -----
prep_jane
id="$LID_app_a"
reset_key="$(fwp app_a eval '$u = get_user_by( "login", "jane.doe" ); echo get_password_reset_key( $u );')"
key_state() { fwp app_a eval "\$r = check_password_reset_key( '$reset_key', 'jane.doe' ); echo is_wp_error( \$r ) ? 'dead' : 'valid';"; }
assert_eq valid "$(key_state)" "precondition: reset key valid before the disable"
WP_BIN="$ROOT/tests/lib/wp-shim.sh" SHIM_FAIL="--user_email=disabled+$id@webfor.invalid" run_tool "${DIS[@]}" --sites app_a --execute
assert_contains "$(detail_of app_a)" "6 (email)" "setup: only the email step failed"
assert_eq no "$(auth_ok app_a jane.doe known-pass-1)" "setup: password already replaced"
assert_eq dead "$(key_state)" "reset key already dead although step 6 failed (step 2 closes it)"
assert_eq 0 "$(mail_count app_a)" "partial disable sent no mail"
run_tool "${DIS[@]}" --sites app_a --execute
assert_eq DISABLED "$(status_of app_a)" "re-run finishes after the email step failure"

# --- unusual role slug is refused before anything changes ---------------------
prep_jane
id="$LID_app_a"
fwp app_a role create Weird_Role "Weird" >/dev/null
fwp app_a user add-role "$id" Weird_Role >/dev/null
w_before="$(fp app_a)"
run_tool "${DIS[@]}" --sites app_a --execute
assert_eq FAILED "$(status_of app_a)" "unusual role name: FAILED"
assert_contains "$(detail_of app_a)" "unusual role name" "unusual role name: detail says so"
assert_eq "$w_before" "$(fp app_a)" "unusual role name: nothing changed, no marker written"
fwp app_a user meta get "$id" webfor_disabled >/dev/null 2>&1; w_rc=$?
assert_eq 1 "$w_rc" "unusual role name: marker absent"
assert_eq yes "$(auth_ok app_a jane.doe known-pass-1)" "unusual role name: password untouched"
fwp app_a user remove-role "$id" Weird_Role >/dev/null
fwp app_a role delete Weird_Role >/dev/null

# --- role splitting never globs (glob bait) -----------------------------------
gb="$(mktemp -d)"
touch "$gb/editor" "$gb/administrator"
glob_out="$( cd "$gb" && . "$ROOT/lib/common.sh" && . "$ROOT/lib/wp.sh" && . "$ROOT/lib/op_disable.sh" \
  && UROLES='editor,*' && split_uroles && printf '%s|%s|%s' "${#ROLE_LIST[@]}" "${ROLE_LIST[0]}" "${ROLE_LIST[1]}" )"
assert_eq '2|editor|*' "$glob_out" "split_uroles keeps '*' literal (no filename expansion)"
glob_rc="$( cd "$gb" && . "$ROOT/lib/common.sh" && . "$ROOT/lib/wp.sh" && . "$ROOT/lib/op_disable.sh" \
  && UROLES='' && split_uroles && printf '%s' "${#ROLE_LIST[@]}" )"
assert_eq 0 "$glob_rc" "split_uroles on empty roles gives an empty list"
rm -rf "$gb"

# --- user_roles keeps spaces inside a role slug ---------------------------------
rk="$(mktemp -d)"
printf '#!/bin/sh\necho "\\"administrator, weird role\\""\n' > "$rk/roles"
chmod +x "$rk/roles"
rr="$( export WP_BIN="$rk/roles"; . "$ROOT/lib/common.sh"; . "$ROOT/lib/wp.sh"; . "$ROOT/lib/op_disable.sh"
  SITE_PATH=/nonexistent; user_roles 1; split_uroles
  valid_slug "${ROLE_LIST[1]}" && v=ok || v=refused
  printf '%s|%s|%s' "$UROLES" "${#ROLE_LIST[@]}" "$v" )"
assert_eq 'administrator,weird role|2|refused' "$rr" "user_roles keeps 'weird role' intact and valid_slug refuses it"
rm -rf "$rk"

# --- app_passwords_delete_all: classification of WP-CLI failures ----------------
fk="$(mktemp -d)"
printf '#!/bin/sh\necho "Error: Requires WordPress 5.6 or greater." >&2\nexit 1\n' > "$fk/old_wp"
printf '#!/bin/sh\necho "Error: something else not available" >&2\nexit 1\n' > "$fk/other"
printf '#!/bin/sh\necho "Error: Application passwords are not available for this site." >&2\nexit 1\n' > "$fk/appnotavail"
printf '#!/bin/sh\necho "Error: Database error" >&2\nexit 1\n' > "$fk/dberr"
chmod +x "$fk"/*
apd() { # FAKE -> "rc|R_WARN"
  ( export WP_BIN="$fk/$1"; . "$ROOT/lib/common.sh"; . "$ROOT/lib/wp.sh"; . "$ROOT/lib/op_disable.sh"
    SITE_PATH=/nonexistent; R_WARN=""; app_passwords_delete_all 1; rc=$?; printf '%s|%s' "$rc" "$R_WARN" )
}
assert_eq '0|application passwords unavailable on this site' "$(apd old_wp)" "WP < 5.6: warning, step succeeds"
assert_eq '0|application passwords unavailable on this site' "$(apd appnotavail)" "application passwords not available: warning, step succeeds"
assert_eq '1|' "$(apd other)" "unrelated 'not available' error: step fails"
assert_eq '1|' "$(apd dberr)" "other error: step fails"
rm -rf "$fk"
