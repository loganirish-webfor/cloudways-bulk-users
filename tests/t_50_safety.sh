SHIM="$ROOT/tests/lib/wp-shim.sh"

# --- the tool can never delete a user ------------------------------------------
if grep -rn "user delete" "$ROOT/bin" "$ROOT/lib" >/dev/null; then bad "source contains 'user delete'"; else ok "source contains no 'user delete'"; fi

# --- failure isolation: a bad site never stops the run --------------------------
fixtures_reset
TOOL_STDIN=ALL run_tool "${ADD[@]}" --all --execute
assert_eq CREATED "$(status_of app_a)" "site before the broken one still processed"
assert_eq FAILED "$(status_of app_broken)" "broken site reported as FAILED"
assert_eq "USERNAME CONFLICT" "$(status_of app_usertaken)" "site after the broken one still processed"
assert_contains "$OUT" "Applications processed: 10" "totals add up to every folder"
assert_eq 1 "$RC" "run with a failure exits 1"

# --- --all --execute needs the typed confirmation -------------------------------------
fixtures_reset
b="$(all_fp)"
TOOL_STDIN=nope run_tool "${ADD[@]}" --all --execute
assert_eq 2 "$RC" "wrong confirmation -> exit 2"
assert_eq "$b" "$(all_fp)" "wrong confirmation changed nothing"

# --- no secrets in output or logs ----------------------------------------------------------
fixtures_reset
prep_logan
run_tool "${DIS[@]}" --sites app_a --execute
logs_text="$OUT$(cat "$LOGS"/*.log "$LOGS"/*.tsv)"
assert_not_contains "$logs_text" "known-pass-1" "known password never appears in output or logs"
assert_not_contains "$logs_text" "$APP_PW_app_a" "application password never appears in output or logs"
assert_not_contains "$logs_text" "Password:" "no 'Password:' line in output or logs"

# --- log content ------------------------------------------------------------------------------
LOGF="${TSV%.tsv}.log"
assert_contains "$(cat "$LOGF")" "EXECUTE: disable logan.irish <logan.irish@webfor.com> server=testsrv" "log header: mode, op, user, email, server"
assert_contains "$(cat "$LOGF")" "RESULT app_a: DISABLED" "log has the per-site result"
assert_contains "$(cat "$LOGF")" "Applications processed: 1" "log has totals"

# --- partial failure continues, then resume completes it ------------------------------
prep_logan
WP_BIN="$SHIM" SHIM_FAIL=application-password run_tool "${DIS[@]}" --sites app_a --execute
assert_eq FAILED "$(status_of app_a)" "step failure -> FAILED"
assert_contains "$(detail_of app_a)" "PARTIAL" "reported as PARTIAL"
assert_contains "$(detail_of app_a)" "4 (application passwords)" "names the failed step"
assert_contains "$(detail_of app_a)" "completed: 1,2,3,5,6" "later steps still ran"
assert_contains "$(fwp app_a user meta get "$LID_app_a" webfor_disabled --format=json)" '"state":"in_progress"' "marker left in_progress"
assert_eq no "$(auth_ok app_a logan.irish known-pass-1)" "password already scrambled despite the failure"
assert_eq "" "$(roles_sorted app_a logan.irish)" "roles already removed"
run_tool "${DIS[@]}" --sites app_a --execute
assert_eq DISABLED "$(status_of app_a)" "re-run resumes and finishes"
assert_contains "$(fwp app_a user meta get "$LID_app_a" webfor_disabled --format=json)" '"state":"complete"' "marker complete after resume"
assert_contains "$(fwp app_a user meta get "$LID_app_a" webfor_disabled --format=json)" '"roles":["administrator"]' "resume kept the original roles"
run_tool "${RST[@]}" --sites app_a --execute
assert_eq RESTORED "$(status_of app_a)" "a resumed disable can be restored"
assert_eq administrator "$(roles_sorted app_a logan.irish)" "roles back after resume then restore"

# --- review focus 5: a hung WP-CLI call times out and the run continues ---------------------
fixtures_reset
WP_BIN="$SHIM" SHIM_SLEEP=5 WP_TIMEOUT=2 run_tool "${ADD[@]}" --sites app_a,app_b
assert_eq FAILED "$(status_of app_a)" "hung site -> FAILED"
assert_contains "$(detail_of app_a)" "timed out" "reason mentions the timeout"
assert_eq FAILED "$(status_of app_b)" "next site was still attempted"

# --- add: a role-lookup error is reported as such, not as a missing role -----------------------
fixtures_reset
WP_BIN="$SHIM" SHIM_FAIL=role run_tool "${ADD[@]}" --sites app_a --execute
assert_eq FAILED "$(status_of app_a)" "role lookup error -> FAILED"
assert_contains "$(detail_of app_a)" "role lookup" "reported as a role lookup error"
assert_not_contains "$(detail_of app_a)" "does not exist" "not mislabelled as a missing role"
assert_eq 1 "$(user_count app_a)" "no user created after the role lookup error"

# --- add: a marker-lookup error is not mistaken for a username conflict -----------------------
fixtures_reset
b="$(fp app_usertaken)"
WP_BIN="$SHIM" SHIM_FAIL=meta run_tool "${ADD[@]}" --sites app_usertaken --execute
assert_eq FAILED "$(status_of app_usertaken)" "marker lookup error -> FAILED"
assert_contains "$(detail_of app_usertaken)" "marker lookup" "reported as a marker lookup error"
assert_eq "$b" "$(fp app_usertaken)" "marker lookup error changed nothing"

# --- restore: a failed role step leaves a PARTIAL result, marker kept, re-run completes ---------
prep_logan
run_tool "${DIS[@]}" --sites app_a --execute
assert_eq DISABLED "$(status_of app_a)" "setup: app_a disabled"
WP_BIN="$SHIM" SHIM_FAIL=add-role run_tool "${RST[@]}" --sites app_a --execute
assert_eq FAILED "$(status_of app_a)" "restore step failure -> FAILED"
assert_contains "$(detail_of app_a)" "PARTIAL" "restore reported as PARTIAL"
assert_contains "$(detail_of app_a)" "completed: 1" "email step completed"
mk="$(fwp app_a user meta get "$LID_app_a" webfor_disabled --format=json)"
assert_contains "$mk" '"state":"complete"' "marker kept after the partial restore"
assert_eq logan.irish@webfor.com "$(fwp app_a user get "$LID_app_a" --field=user_email)" "email already restored"
assert_eq "" "$(roles_sorted app_a logan.irish)" "roles still empty after the partial restore"
run_tool "${RST[@]}" --sites app_a --execute
assert_eq RESTORED "$(status_of app_a)" "re-run of restore finishes"
assert_eq administrator "$(roles_sorted app_a logan.irish)" "administrator back after the re-run"
mk="$(fwp app_a user meta get "$LID_app_a" webfor_disabled --format=json 2>/dev/null)"; mrc=$?
assert_eq "" "$mk" "marker gone after the re-run (no output)"
assert_eq 1 "$mrc" "marker gone after the re-run (exit 1)"
