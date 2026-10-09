# A stale Object Cache Pro drop-in prints "objectcache.critical: Failed to locate and
# load object cache API" to stderr on EVERY WP-CLI call, including ones that work.
# `wp user meta get` for a missing key exits 1 with no message, so that line made
# marker_read report an error and four live sites came back FAILED. Found on a live
# server. The exact noise line must be ignored; any other stderr output must not be.
fixtures_reset
SHIM="$ROOT/tests/lib/wp-shim.sh"
NOISE='objectcache.critical: Failed to locate and load object cache API'

mk_rc_noise() { # NOISE-LINE -> marker_read rc for user 1 in app_a
  ( export WP_BIN="$SHIM" SHIM_NOISE="$1"
    . "$ROOT/lib/common.sh"; . "$ROOT/lib/wp.sh"
    SITE_PATH="$FX_ROOT/app_a/public_html"
    marker_read 1; echo $? )
}
assert_eq 1 "$(mk_rc_noise "$NOISE")" "noise: marker_read still sees 'no marker' (rc 1) through the known drop-in line"
assert_eq 2 "$(mk_rc_noise 'objectcache.critical: some other failure')" "noise: a different stderr line is still an error (rc 2)"
assert_eq 2 "$(mk_rc_noise 'Error: database is on fire')" "noise: a real error line is still an error (rc 2)"

WP_BIN="$SHIM" SHIM_NOISE="$NOISE" run_tool "${ADD[@]}" --sites app_exists,app_a,app_emailtaken
assert_eq "ALREADY EXISTS" "$(status_of app_exists)" "noise: add on a site that has the user -> ALREADY EXISTS, not FAILED"
assert_eq "WOULD CREATE" "$(status_of app_a)" "noise: add on a site without the user -> WOULD CREATE"
assert_eq "EMAIL CONFLICT" "$(status_of app_emailtaken)" "noise: conflict detection unchanged"

WP_BIN="$SHIM" SHIM_NOISE="$NOISE" run_tool "${DIS[@]}" --sites app_exists
assert_eq "WOULD DISABLE" "$(status_of app_exists)" "noise: disable dry run -> WOULD DISABLE, not FAILED"
WP_BIN="$SHIM" SHIM_NOISE="$NOISE" run_tool "${RST[@]}" --sites app_exists
assert_eq "NOT DISABLED" "$(status_of app_exists)" "noise: restore on a never-disabled user -> NOT DISABLED, not FAILED"

# The whole live cycle with the noise on every call.
prep_jane
WP_BIN="$SHIM" SHIM_NOISE="$NOISE" run_tool "${DIS[@]}" --sites app_a --execute
assert_eq DISABLED "$(status_of app_a)" "noise: live disable completes"
assert_eq "" "$(warn_of app_a)" "noise: live disable has no warnings from the noise"
WP_BIN="$SHIM" SHIM_NOISE="$NOISE" run_tool "${DIS[@]}" --sites app_a --execute
assert_eq "ALREADY DISABLED" "$(status_of app_a)" "noise: disable again -> ALREADY DISABLED"
WP_BIN="$SHIM" SHIM_NOISE="$NOISE" run_tool "${RST[@]}" --sites app_a --execute
assert_eq RESTORED "$(status_of app_a)" "noise: live restore completes"

# A site with an object-cache drop-in gets a visible warning after a live change: the tool
# skips plugins, so it cannot reach or flush that cache. The stand-in below defines nothing,
# which is what Object Cache Pro does when it cannot find its plugin.
prep_jane
printf '<?php\n// test stand-in for an object-cache drop-in\n' > "$FX_ROOT/app_a/public_html/wp-content/object-cache.php"
run_tool "${DIS[@]}" --sites app_a,app_b --execute
assert_eq DISABLED "$(status_of app_a)" "drop-in: live disable still completes"
assert_contains "$(warn_of app_a)" "object-cache drop-in present" "drop-in: disable warns about the cache"
assert_eq DISABLED "$(status_of app_b)" "drop-in: a site without the drop-in is disabled too"
assert_not_contains "$(warn_of app_b)" "object-cache" "drop-in: no cache warning on a site without the drop-in"
run_tool "${RST[@]}" --sites app_a,app_b --execute
assert_eq RESTORED "$(status_of app_a)" "drop-in: live restore still completes"
assert_contains "$(warn_of app_a)" "object-cache drop-in present" "drop-in: restore warns about the cache"
assert_not_contains "$(warn_of app_b)" "object-cache" "drop-in: no cache warning on restore without the drop-in"
rm -f "$FX_ROOT/app_a/public_html/wp-content/object-cache.php"
