fixtures_reset

# --- dry run: proposes, changes nothing ------------------------------------
before="$(all_fp)"
run_tool "${ADD[@]}" --all
assert_eq "$before" "$(all_fp)" "add dry run leaves every database identical"
assert_eq 1 "$RC" "dry run with conflicts/failures exits 1"
assert_eq "WOULD CREATE" "$(status_of app_a)" "app_a: WOULD CREATE"
assert_eq "WOULD CREATE" "$(status_of app_b)" "app_b: WOULD CREATE"
assert_eq "ALREADY EXISTS" "$(status_of app_exists)" "app_exists: ALREADY EXISTS"
assert_eq "EMAIL CONFLICT" "$(status_of app_emailtaken)" "app_emailtaken: EMAIL CONFLICT"
assert_eq "USERNAME CONFLICT" "$(status_of app_usertaken)" "app_usertaken: USERNAME CONFLICT"
assert_eq "ALREADY EXISTS" "$(status_of app_soleadmin)" "app_soleadmin: ALREADY EXISTS"
assert_contains "$OUT" "EMAIL CONFLICT - REVIEW REQUIRED" "conflict shows REVIEW REQUIRED"
assert_contains "$OUT" "DRY RUN: no changes were made." "dry-run footer"

# --- live create on two sites only ------------------------------------------
users_before="$(user_count app_a)"
admin_email_before="$(fwp app_a user get admin --field=user_email)"
run_tool "${ADD[@]}" --sites app_a,app_b --execute
assert_eq 0 "$RC" "live create exits 0"
assert_eq CREATED "$(status_of app_a)" "app_a: CREATED"
assert_eq CREATED "$(status_of app_b)" "app_b: CREATED"
assert_eq "$((users_before + 1))" "$(user_count app_a)" "exactly one user added"
assert_eq "logan.irish@webfor.com" "$(fwp app_a user get logan.irish --field=user_email)" "email correct"
assert_eq administrator "$(roles_sorted app_a logan.irish)" "role is administrator"
assert_eq "Logan Irish" "$(fwp app_a user get logan.irish --field=display_name)" "display name"
assert_eq "Logan" "$(fwp app_a user meta get "$(fwp app_a user get logan.irish --field=ID)" first_name)" "first name"
assert_eq "$admin_email_before" "$(fwp app_a user get admin --field=user_email)" "existing admin untouched"
assert_eq 0 "$(mail_count app_a)" "no email sent on create"
assert_not_contains "$OUT" "Password:" "no password printed"
assert_not_contains "$(cat "${TSV%.tsv}.log")" "Password:" "no password logged"

# --- duplicate protection ----------------------------------------------------
registered="$(fwp app_a user get logan.irish --field=user_registered)"
run_tool "${ADD[@]}" --sites app_a,app_b --execute
assert_eq "ALREADY EXISTS" "$(status_of app_a)" "second run: ALREADY EXISTS"
assert_eq "$((users_before + 1))" "$(user_count app_a)" "no duplicate created"
assert_eq "$registered" "$(fwp app_a user get logan.irish --field=user_registered)" "existing account unchanged"

# --- review focus 2: email case-insensitivity -------------------------------
run_tool add --username logan.irish --email Logan.Irish@Webfor.com --first-name Logan --last-name Irish --display-name "Logan Irish" --sites app_a --execute
assert_eq "ALREADY EXISTS" "$(status_of app_a)" "mixed-case email still the same account"

# --- conflicts are never modified --------------------------------------------
c_before="$(fp app_emailtaken)$(fp app_usertaken)"
run_tool "${ADD[@]}" --sites app_emailtaken,app_usertaken --execute
assert_eq "$c_before" "$(fp app_emailtaken)$(fp app_usertaken)" "conflict sites unchanged on a live run"
assert_eq 1 "$RC" "conflicts exit 1"

# --- role note when the existing account is not an administrator -------------
fwp app_exists user set-role logan.irish editor >/dev/null
run_tool "${ADD[@]}" --sites app_exists
assert_contains "$(detail_of app_exists)" "role: editor, expected administrator" "role mismatch noted, not changed"
assert_eq editor "$(roles_sorted app_exists logan.irish)" "role not modified"

# --- a role that does not exist on the site ----------------------------------
run_tool add --username new.person --email new.person@webfor.com --first-name New --last-name Person --display-name "New Person" --role nosuchrole --sites app_a --execute
assert_eq FAILED "$(status_of app_a)" "unknown role -> FAILED"
assert_contains "$(detail_of app_a)" "does not exist" "unknown role reason"
