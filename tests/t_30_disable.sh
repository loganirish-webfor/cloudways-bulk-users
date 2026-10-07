prep_logan
assert_eq yes "$(auth_ok app_a logan.irish known-pass-1)" "precondition: password works"
assert_eq yes "$(app_pw_ok app_a logan.irish "$APP_PW_app_a")" "precondition: app password works"

# --- dry run ------------------------------------------------------------------
before="$(all_fp)"
run_tool "${DIS[@]}" --all
assert_eq "$before" "$(all_fp)" "disable dry run leaves every database identical"
assert_eq "WOULD DISABLE" "$(status_of app_a)" "app_a: WOULD DISABLE"
assert_eq "WOULD DISABLE" "$(status_of app_b)" "app_b: WOULD DISABLE"
assert_eq "NOT FOUND" "$(status_of app_emailtaken)" "no such user: NOT FOUND"
assert_eq "EMAIL MISMATCH" "$(status_of app_usertaken)" "same username, different email: EMAIL MISMATCH"
assert_eq "LAST ADMIN" "$(status_of app_soleadmin)" "only administrator: LAST ADMIN"
assert_contains "$OUT" "LAST ADMIN - REVIEW REQUIRED" "last admin shows REVIEW REQUIRED"

# --- guards hold on a live run ------------------------------------------------
g_before="$(fp app_usertaken)$(fp app_soleadmin)$(fp app_emailtaken)"
run_tool "${DIS[@]}" --sites app_usertaken,app_soleadmin,app_emailtaken --execute
assert_eq "$g_before" "$(fp app_usertaken)$(fp app_soleadmin)$(fp app_emailtaken)" "guarded sites unchanged"

# --- live disable ----------------------------------------------------------------
users_before="$(user_count app_a)"
admin_before="$(fwp app_a user get admin --field=user_email)"
run_tool "${DIS[@]}" --sites app_a,app_b --execute
assert_eq 0 "$RC" "live disable exits 0"
for a in app_a app_b; do
  id="$(eval "printf '%s' \"\$LID_$a\"")"
  pw="$(eval "printf '%s' \"\$APP_PW_$a\"")"
  assert_eq DISABLED "$(status_of "$a")" "$a: DISABLED"
  assert_eq no "$(auth_ok "$a" logan.irish known-pass-1)" "$a: old password rejected"
  assert_eq no "$(app_pw_ok "$a" logan.irish "$pw")" "$a: application password revoked"
  assert_eq '[]' "$(fwp "$a" user session list "$id" --format=json)" "$a: sessions destroyed"
  assert_eq "" "$(roles_sorted "$a" logan.irish)" "$a: no roles"
  assert_eq "" "$(fwp "$a" user list-caps "$id")" "$a: no capabilities"
  assert_eq "disabled+$id@webfor.invalid" "$(fwp "$a" user get "$id" --field=user_email)" "$a: email neutralised"
  assert_eq "$id" "$(fwp "$a" user get logan.irish --field=ID)" "$a: user record kept"
  assert_eq 1 "$(fwp "$a" post list --author="$id" --post_status=any --format=count)" "$a: authored content kept"
  assert_contains "$(fwp "$a" user meta get "$id" webfor_disabled --format=json)" '"state":"complete"' "$a: marker complete"
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
prep_logan
run_tool disable --username logan.irish --email LOGAN.IRISH@WEBFOR.COM --sites app_a --execute
assert_eq DISABLED "$(status_of app_a)" "mixed-case --email still matches the account"

# --- email mismatch on an already-disabled account is refused -------------------
run_tool disable --username logan.irish --email other.person@webfor.com --sites app_a --execute
assert_eq "EMAIL MISMATCH" "$(status_of app_a)" "disable with the wrong email is refused"
