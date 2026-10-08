prep_jane
run_tool "${DIS[@]}" --sites app_a,app_b --execute
assert_eq DISABLED "$(status_of app_a)" "precondition: disabled"

# --- dry run ------------------------------------------------------------------
before="$(all_fp)"
run_tool "${RST[@]}" --all
assert_eq "$before" "$(all_fp)" "restore dry run leaves every database identical"
assert_eq "WOULD RESTORE" "$(status_of app_a)" "app_a: WOULD RESTORE"
assert_eq "NOT DISABLED" "$(status_of app_exists)" "never disabled: NOT DISABLED"
assert_eq "NOT FOUND" "$(status_of app_emailtaken)" "no such user: NOT FOUND"

# --- guards ------------------------------------------------------------------------
run_tool restore --username jane.doe --email other.person@webfor.com --sites app_a --execute
assert_eq "EMAIL MISMATCH" "$(status_of app_a)" "restore with the wrong email is refused"
assert_eq "disabled+$LID_app_a@webfor.invalid" "$(fwp app_a user get "$LID_app_a" --field=user_email)" "still disabled after refusal"

fwp app_a user create squatter jane.doe@webfor.com --role=subscriber --porcelain >/dev/null
s_before="$(fp app_a)"
run_tool "${RST[@]}" --sites app_a --execute
assert_eq "EMAIL CONFLICT" "$(status_of app_a)" "original email now owned by someone else: EMAIL CONFLICT"
assert_eq "$s_before" "$(fp app_a)" "conflict leaves the site unchanged (marker kept)"
fwp app_a user delete squatter --yes >/dev/null   # test cleanup only; the tool never deletes

# --- live restore --------------------------------------------------------------------
run_tool "${RST[@]}" --sites app_a,app_b --execute
assert_eq 0 "$RC" "live restore exits 0"
for a in app_a app_b; do
  id="$(eval "printf '%s' \"\$LID_$a\"")"
  assert_eq RESTORED "$(status_of "$a")" "$a: RESTORED"
  assert_eq "jane.doe@webfor.com" "$(fwp "$a" user get "$id" --field=user_email)" "$a: email back"
  assert_eq no "$(auth_ok "$a" jane.doe known-pass-1)" "$a: old password still does not work"
  assert_contains "$(warn_of "$a")" "Lost your password" "$a: report says a reset is required"
  assert_eq 1 "$(fwp "$a" post list --author="$id" --post_status=any --format=count)" "$a: content intact"
  fwp "$a" user meta get "$id" webfor_disabled >/dev/null 2>&1
  assert_eq 1 "$?" "$a: marker removed"
done
assert_eq administrator "$(roles_sorted app_a jane.doe)" "app_a: administrator back"
# review focus 4: every role comes back
assert_eq "administrator,editor" "$(roles_sorted app_b jane.doe)" "app_b: both roles back"

# --- the employee sets a new password via the reset flow ------------------------------
fwp app_a user update "$LID_app_a" --user_pass=new-pass-2 >/dev/null   # stands in for the emailed reset link
assert_eq yes "$(auth_ok app_a jane.doe new-pass-2)" "restored account authenticates once a new password is set"

# --- idempotent ----------------------------------------------------------------------------
after="$(fp app_a)"
run_tool "${RST[@]}" --sites app_a --execute
assert_eq "NOT DISABLED" "$(status_of app_a)" "second restore: NOT DISABLED"
assert_eq "$after" "$(fp app_a)" "second restore changed nothing"

# --- unusual stored role: refused before anything changes -----------------------
prep_jane
run_tool "${DIS[@]}" --sites app_a --execute
id="$LID_app_a"
fwp app_a user meta update "$id" webfor_disabled \
  '{"at":"2026-01-02T03:04:05Z","server":"oldsrv","roles":["administrator","Weird Role"],"email":"jane.doe@webfor.com","state":"complete"}' --format=json >/dev/null
w_before="$(fp app_a)"
run_tool "${RST[@]}" --sites app_a
assert_eq FAILED "$(status_of app_a)" "weird stored role, dry run: FAILED"
run_tool "${RST[@]}" --sites app_a --execute
assert_eq FAILED "$(status_of app_a)" "weird stored role: FAILED"
assert_contains "$(detail_of app_a)" "unusual" "weird stored role: detail says so"
assert_eq "$w_before" "$(fp app_a)" "weird stored role: nothing changed (no role re-added, email and marker untouched)"
assert_eq "" "$(roles_sorted app_a jane.doe)" "weird stored role: still no roles"
assert_contains "$(fwp app_a user meta get "$id" webfor_disabled --format=json)" '"Weird Role"' "weird stored role: marker kept"

# --- partially disabled account (in_progress marker, roles gone, email original) ---
prep_jane
id="$LID_app_a"
fwp app_a user meta update "$id" webfor_disabled \
  '{"at":"2026-01-02T03:04:05Z","server":"oldsrv","roles":["administrator"],"email":"jane.doe@webfor.com","state":"in_progress"}' --format=json >/dev/null
fwp app_a user remove-role "$id" administrator >/dev/null
run_tool "${RST[@]}" --sites app_a
assert_eq "WOULD RESTORE" "$(status_of app_a)" "partial disable, dry run: WOULD RESTORE"
run_tool "${RST[@]}" --sites app_a --execute
assert_eq RESTORED "$(status_of app_a)" "partial disable: RESTORED"
assert_eq administrator "$(roles_sorted app_a jane.doe)" "partial disable: role back"
assert_eq "jane.doe@webfor.com" "$(fwp app_a user get "$id" --field=user_email)" "partial disable: email unchanged"
fwp app_a user meta get "$id" webfor_disabled >/dev/null 2>&1
assert_eq 1 "$?" "partial disable: marker removed"

# --- stored role splitting never globs ------------------------------------------
gb="$(mktemp -d)"
touch "$gb/editor" "$gb/administrator"
glob_out="$( cd "$gb" && . "$ROOT/lib/common.sh" && . "$ROOT/lib/wp.sh" && . "$ROOT/lib/op_restore.sh" \
  && MK_ROLES='editor,*' && split_mk_roles && printf '%s|%s|%s' "${#MK_ROLE_LIST[@]}" "${MK_ROLE_LIST[0]}" "${MK_ROLE_LIST[1]}" )"
assert_eq '2|editor|*' "$glob_out" "split_mk_roles keeps '*' literal (no filename expansion)"
empty_out="$( cd "$gb" && . "$ROOT/lib/common.sh" && . "$ROOT/lib/wp.sh" && . "$ROOT/lib/op_restore.sh" \
  && MK_ROLES='' && split_mk_roles && validate_mk_roles && printf '%s' "${#MK_ROLE_LIST[@]}" )"
assert_eq 0 "$empty_out" "empty stored roles give an empty list and validate"
rm -rf "$gb"
