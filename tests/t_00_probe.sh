# Verifies the WP-CLI behaviours lib/wp.sh relies on (spec section 10).
#
# Measured against WP-CLI 2.12.0 / WordPress 7.1.3. Where reality differed from the plan,
# the assertion below was adjusted to the real behaviour (intent preserved) and the
# deviation is recorded here for lib/wp.sh (Task 2):
#  1. `user get ID --field=roles --format=json` does NOT emit a JSON array. It emits a
#     JSON *string* of the roles joined with ", ":  "administrator, editor"  (and "" for
#     no roles). `--fields=roles --format=json` gives {"roles":"administrator, editor"}
#     and `user list --field=roles` gives "administrator,editor" (no space) so the
#     separator differs per command. For an exact array use
#       wp eval 'echo wp_json_encode( array_values( get_userdata( ID )->roles ) );'
#     which prints ["administrator","editor"] and [] for none.
#  2. `user update --user_pass=...` and `user update --user_email=...` DO send mail
#     ("Password Changed" / "Email Changed", to the user's *old* email). `user create`
#     and `user reset-password --skip-email` send none. Suppress the notices with
#       --exec='WP_CLI::add_wp_hook("send_email_change_email","__return_false");
#               WP_CLI::add_wp_hook("send_password_change_email","__return_false");'
#     (plain add_filter() inside --exec fatals: --exec runs before WordPress loads, so
#     use WP_CLI::add_wp_hook). Verified below.
#  3. WordPress 7.x hashes application passwords with a "$generic$" fast hash, so
#     wp_check_password() cannot verify them. The app_pw_ok fixture helper now calls
#     wp_authenticate_application_password() (with application_password_is_api_request
#     forced true) instead.
#  4. Informational: `application-password delete --all` with none existing exits 0
#     (prints Success on stdout, nothing on stderr). A broken DB makes `core is-installed`
#     exit 1 with "Error: Error establishing a database connection. ..." on stderr.
#  5. Sandbox only: the Alpine mariadb client demands TLS, so tests/docker/Dockerfile
#     wraps mariadb/mariadb-dump to add --skip-ssl (WP-CLI runs them with --no-defaults,
#     so a my.cnf cannot do it) and raises PHP memory_limit for `wp core download`.
fixtures_reset
A=app_a
id="$(fwp "$A" user create probe probe@webfor.com --role=administrator --porcelain)"
case "$id" in ''|*[!0-9]*) bad "create --porcelain prints only the id (got '$id')" ;; *) ok "create --porcelain prints only the id" ;; esac

assert_eq '"administrator"' "$(fwp "$A" user get probe --field=roles --format=json)" "roles field is a JSON string (deviation 1)"
fwp "$A" user add-role "$id" editor >/dev/null
assert_eq '"administrator, editor"' "$(fwp "$A" user get probe --field=roles --format=json)" "multiple roles are joined with ', '"
assert_eq '["administrator","editor"]' "$(fwp "$A" eval "echo wp_json_encode( array_values( get_userdata( $id )->roles ) );")" "roles as an exact JSON array via eval"
fwp "$A" user remove-role "$id" editor >/dev/null
assert_eq "$id" "$(fwp "$A" user get probe@webfor.com --field=ID)" "user get accepts an email"
err="$(fwp "$A" user get nosuchuser --field=ID 2>&1 >/dev/null)"
assert_contains "$err" "Invalid user" "missing user error text"

json='{"at":"2026-10-07T00:00:00Z","server":"srv","roles":["administrator","editor"],"email":"probe@webfor.com","state":"in_progress"}'
fwp "$A" user meta update "$id" webfor_disabled "$json" --format=json >/dev/null
assert_eq "$json" "$(fwp "$A" user meta get "$id" webfor_disabled --format=json)" "marker JSON round-trips byte for byte"
fwp "$A" user meta get "$id" nosuchkey >/dev/null 2>/tmp/probe.err; rc=$?
assert_eq 1 "$rc" "missing meta exits 1"
perr="$(grep -v -E '^(PHP )?(Notice|Warning|Deprecated)' /tmp/probe.err | grep -v '^$')"
case "$perr" in ''|*"Could not find"*) ok "missing meta is silent or says 'Could not find'" ;; *) bad "missing meta stderr: $perr" ;; esac

NOMAIL='WP_CLI::add_wp_hook("send_email_change_email","__return_false");WP_CLI::add_wp_hook("send_password_change_email","__return_false");'
fwp "$A" user update "$id" --user_pass=probe-pass-1 --exec="$NOMAIL" >/dev/null
assert_eq yes "$(auth_ok "$A" probe probe-pass-1)" "known password authenticates"
fwp "$A" user reset-password "$id" --skip-email >/dev/null 2>&1
assert_eq no "$(auth_ok "$A" probe probe-pass-1)" "reset-password --skip-email scrambles the password"

fwp "$A" user update "$id" --user_email="disabled+$id@webfor.invalid" --exec="$NOMAIL" >/dev/null
assert_eq "disabled+$id@webfor.invalid" "$(fwp "$A" user get "$id" --field=user_email)" ".invalid email accepted"
assert_eq 0 "$(mail_count "$A")" "create, reset-password and (hook-suppressed) password/email updates send no mail"
id2="$(fwp "$A" user create probe2 probe2@webfor.com --role=subscriber --porcelain)"
fwp "$A" user update "$id2" --user_email="probe2b@webfor.com" >/dev/null
assert_eq 1 "$(mail_count "$A")" "unsuppressed email change DOES send a notice (deviation 2)"

fwp "$A" eval "WP_Session_Tokens::get_instance( $id )->create( time() + 3600 );"
fwp "$A" user session destroy "$id" --all >/dev/null
assert_eq '[]' "$(fwp "$A" user session list "$id" --format=json)" "session destroy --all empties sessions"

fwp "$A" user application-password delete "$id" --all >/dev/null 2>/tmp/probe.err; rc=$?
printf '  note: app-password delete --all with none existing -> rc=%s stderr=%s\n' "$rc" "$(head -1 /tmp/probe.err)"
pw="$(fwp "$A" user application-password create "$id" probe --porcelain)"
assert_eq yes "$(app_pw_ok "$A" probe "$pw")" "app password created and checkable"
fwp "$A" user application-password delete "$id" --all >/dev/null
assert_eq no "$(app_pw_ok "$A" probe "$pw")" "application-password delete --all revokes"

fwp "$A" user remove-role "$id" administrator >/dev/null
assert_eq '""' "$(fwp "$A" user get "$id" --field=roles --format=json)" "remove-role can leave no roles (empty JSON string)"
assert_eq '[]' "$(fwp "$A" eval "echo wp_json_encode( array_values( get_userdata( $id )->roles ) );")" "no roles as an exact JSON array via eval"
assert_eq "" "$(fwp "$A" user list-caps "$id" 2>/dev/null)" "no capabilities without roles"
assert_eq 1 "$(fwp "$A" user list --role=administrator --field=ID | grep -c .)" "list --role=administrator counts admins"

fwp app_multisite core is-installed --network; rc=$?
assert_eq 0 "$rc" "is-installed --network succeeds on multisite"
fwp "$A" core is-installed --network; rc=$?
assert_eq 1 "$rc" "is-installed --network fails on single site"
err="$(fwp app_notwp core is-installed 2>&1)"
assert_contains "$err" "does not seem to be a WordPress installation" "non-WordPress error text"
fwp app_broken core is-installed >/tmp/probe.out 2>/tmp/probe.err; rc=$?
printf '  note: broken-db is-installed -> rc=%s stderr=%s\n' "$rc" "$(head -1 /tmp/probe.err)"
fwp app_broken db query "SELECT 1" >/dev/null 2>&1; rc=$?
assert_eq 1 "$rc" "db query fails on bad credentials"

# roles_sorted: sorted, comma-joined, no spaces
rid="$(fwp "$A" user create rolesprobe rolesprobe@webfor.com --role=editor --porcelain)"
assert_eq "editor" "$(roles_sorted "$A" "$rid")" "roles_sorted: single role"
fwp "$A" user add-role "$rid" administrator >/dev/null
assert_eq "administrator,editor" "$(roles_sorted "$A" "$rid")" "roles_sorted: two roles sorted, no spaces"
fwp "$A" user remove-role "$rid" administrator >/dev/null
fwp "$A" user remove-role "$rid" editor >/dev/null
assert_eq "" "$(roles_sorted "$A" "$rid")" "roles_sorted: no roles is empty"

# fp: must be a real, discriminating, stable fingerprint
fpa="$(fp app_a)"; fpb="$(fp app_b)"
case "$fpa" in FP-ERROR*|'') bad "fp(app_a) returned '$fpa'" ;; *) ok "fp(app_a) returns a hash" ;; esac
[ "$fpa" != "$fpb" ] && ok "fp differs between app_a and app_b" || bad "fp(app_a) equals fp(app_b)"
assert_eq "$fpa" "$(fp app_a)" "fp is stable across consecutive calls with no write"
fwp "$A" user meta update "$rid" fp_probe 1 >/dev/null
[ "$fpa" != "$(fp app_a)" ] && ok "fp changes after a write" || bad "fp unchanged after a write"
fpbad="$(fp app_broken)"; rc=$?
assert_eq 1 "$rc" "fp fails (nonzero) when the query cannot run"
assert_contains "$fpbad" "FP-ERROR-app_broken" "fp emits a sentinel on failure"
