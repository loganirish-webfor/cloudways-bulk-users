fixtures_reset

# --- usage errors exit 2 and touch nothing -------------------------------
run_tool add --username logan.irish --email logan.irish@webfor.com --first-name L --last-name I --display-name "L I"
assert_eq 2 "$RC" "no targeting -> exit 2"
run_tool add --username logan.irish --email logan.irish@webfor.com --first-name L --last-name I --display-name "L I" --all --sites app_a
assert_eq 2 "$RC" "--all and --sites together -> exit 2"
run_tool add --username Logan --email logan.irish@webfor.com --first-name L --last-name I --display-name "L I" --all
assert_eq 2 "$RC" "uppercase username rejected"
run_tool add --username 12345 --email logan.irish@webfor.com --first-name L --last-name I --display-name "L I" --all
assert_eq 2 "$RC" "all-digit username rejected"
run_tool add --username logan.irish --email logan@client.com --first-name L --last-name I --display-name "L I" --all
assert_eq 2 "$RC" "email outside allowed domain rejected"
run_tool add --username logan.irish --email logan.irish@webfor.com --display-name "L I" --all
assert_eq 2 "$RC" "add without first/last name rejected"
run_tool disable --username logan.irish --email logan.irish@webfor.com --sites ../etc
assert_eq 2 "$RC" "path traversal in --sites rejected"
run_tool disable --username logan.irish --email logan.irish@webfor.com --sites .
assert_eq 2 "$RC" "dot folder rejected"
run_tool disable --username logan.irish --email logan.irish@webfor.com --sites 'a;b'
assert_eq 2 "$RC" "odd characters in --sites rejected"
run_tool disable --username logan.irish --email logan.irish@webfor.com --all --exclude ../x
assert_eq 2 "$RC" "path traversal in --exclude rejected"
run_tool disable --username -x --email logan.irish@webfor.com --all
assert_eq 2 "$RC" "username with a leading dash rejected"
run_tool bogus --username x
assert_eq 2 "$RC" "unknown operation rejected"

# --- discovery and validation (op-independent statuses) -------------------
run_tool disable --username logan.irish --email logan.irish@webfor.com --all
assert_contains "$OUT" "DRY RUN" "dry run is the default and says so"
assert_eq SKIPPED "$(status_of app_notwp)" "empty public_html -> SKIPPED"
assert_contains "$(detail_of app_notwp)" "not WordPress" "reason: not WordPress"
assert_eq SKIPPED "$(status_of app_nopublic)" "no public_html -> SKIPPED"
assert_contains "$(detail_of app_nopublic)" "no public_html" "reason: no public_html"
assert_eq SKIPPED "$(status_of app_multisite)" "multisite -> SKIPPED"
assert_contains "$(detail_of app_multisite)" "multisite" "reason: multisite"
assert_eq FAILED "$(status_of app_broken)" "bad DB credentials -> FAILED"
assert_contains "$(tsv_col app_a 1)" "https://app_a.test" "label carries siteurl"
assert_contains "$OUT" "Needs manual review" "review list printed"
assert_contains "$OUT" "Applications processed: 10" "all ten folders processed"

run_tool disable --username logan.irish --email logan.irish@webfor.com --sites app_nope
assert_eq SKIPPED "$(status_of app_nope)" "unknown folder -> SKIPPED row, not a crash"
assert_contains "$(detail_of app_nope)" "no such application folder" "reason: no such folder"

run_tool disable --username logan.irish --email logan.irish@webfor.com --all --exclude app_a,app_b,app_exists,app_emailtaken,app_usertaken,app_soleadmin,app_notwp,app_nopublic,app_multisite,app_broken
assert_eq 1 "$RC" "zero targets after --exclude -> exit 1"
assert_contains "$OUT" "no applications" "zero-target message"

mkdir -p /tmp/wwu-empty-root
run_tool disable --username logan.irish --email logan.irish@webfor.com --all --apps-root /tmp/wwu-empty-root
assert_eq 1 "$RC" "empty apps root -> exit 1"

run_tool disable --username logan.irish --email logan.irish@webfor.com --all --exclude app_a
assert_eq "" "$(status_of app_a)" "--exclude removes a folder from the run"
if [ -n "$(status_of app_b)" ]; then ok "--exclude leaves the other folders in the run"; else bad "--exclude leaves the other folders in the run"; fi

# --- logging ---------------------------------------------------------------
LOGF="${TSV%.tsv}.log"
assert_eq 600 "$(stat -c %a "$LOGF")" "log file mode 600"
assert_eq 600 "$(stat -c %a "$TSV")" "tsv file mode 600"
assert_contains "$(cat "$LOGF")" "server=testsrv" "log records the server"
assert_contains "$(cat "$LOGF")" "logan.irish" "log records the username"

# --- marker_read: only a real "absent" is rc 1; silent failures are rc 2 ----
mk_rc() { # WP_BIN-or-empty -> marker_read rc for user 1 in app_a
  ( [ -n "$1" ] && WP_BIN="$1"
    . "$ROOT/lib/common.sh"; . "$ROOT/lib/wp.sh"
    SITE_PATH="$FX_ROOT/app_a/public_html"
    marker_read 1; echo $? )
}
printf '#!/bin/sh\nexit 255\n' > /tmp/wwu-silent-fail-255; chmod +x /tmp/wwu-silent-fail-255
printf '#!/bin/sh\nexit 124\n' > /tmp/wwu-silent-fail-124; chmod +x /tmp/wwu-silent-fail-124
assert_eq 1 "$(mk_rc "")" "marker_read: real user without a marker -> rc 1 (absent)"
assert_eq 2 "$(mk_rc /tmp/wwu-silent-fail-255)" "marker_read: silent exit 255 -> rc 2 (error), not absent"
assert_eq 2 "$(mk_rc /tmp/wwu-silent-fail-124)" "marker_read: silent exit 124 (timeout) -> rc 2 (error), not absent"
rm -f /tmp/wwu-silent-fail-255 /tmp/wwu-silent-fail-124

# --- a flag is not a value ---------------------------------------------------------
fixtures_reset
b="$(all_fp)"
run_tool disable --username logan.irish --email logan.irish@webfor.com --sites app_a --server --execute
assert_eq 2 "$RC" "--server followed by a flag -> exit 2"
assert_contains "$OUT" "--server needs a value" "usage error names the flag"
run_tool disable --username --email logan.irish@webfor.com --sites app_a
assert_eq 2 "$RC" "--username followed by a flag -> exit 2"
assert_eq "$b" "$(all_fp)" "flag-as-value changed nothing"

# --- an unwritable log dir stops a live run before any site is touched ---------------
fixtures_reset
b="$(all_fp)"
ro="$(mktemp -d)"; chmod 555 "$ro"
lw_out="$(printf '\n' | bash "$ROOT/bin/webfor-wp-users" add --username logan.irish --email logan.irish@webfor.com \
  --first-name Logan --last-name Irish --display-name "Logan Irish" \
  --apps-root "$FX_ROOT" --log-dir "$ro" --server testsrv --sites app_a,app_b --execute 2>&1)"; lw_rc=$?
chmod 755 "$ro"
assert_eq 2 "$lw_rc" "unwritable log dir with --execute -> exit 2"
assert_contains "$lw_out" "cannot create log files" "unwritable log dir: clear message"
assert_eq "$b" "$(all_fp)" "unwritable log dir: no site changed"
assert_eq 0 "$(ls "$ro" | wc -l | tr -d ' ')" "unwritable log dir: no log files created"
rm -rf "$ro"
