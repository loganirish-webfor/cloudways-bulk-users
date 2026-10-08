#!/usr/bin/env bash
# WP-CLI access for one site (SITE_PATH). All parsing of WP-CLI output lives
# here, so a WP-CLI behaviour change has exactly one place to fix.

WP_BIN="${WP_BIN:-wp}"
WP_TIMEOUT="${WP_TIMEOUT:-120}"
TIMEOUT_BIN=""
command -v timeout >/dev/null 2>&1 && TIMEOUT_BIN="timeout"
MARKER_KEY="webfor_disabled"

# `wp user update --user_email/--user_pass` send "Email Changed"/"Password Changed"
# notices to the user's OLD address (WP-CLI 2.12 / WP 7.1, measured in
# tests/t_00_probe.sh). Switch both off on every call. --exec runs before
# WordPress loads, so add_filter() would fatal; WP_CLI::add_wp_hook is correct.
WPX_EXEC='WP_CLI::add_wp_hook("send_email_change_email","__return_false");WP_CLI::add_wp_hook("send_password_change_email","__return_false");'

# Cloudways' wp-config.php loads wp-salt.php by a RELATIVE path (require('wp-salt.php')),
# which only resolves when the current folder is the site root (found on two live
# servers; see tests/t_12_cwd.sh). So every call runs from inside the site folder.
# The subshell leaves the caller's own folder unchanged.
wpx() {
  (
    cd "$SITE_PATH" || exit 126
    if [ -n "$TIMEOUT_BIN" ]; then
      "$TIMEOUT_BIN" "$WP_TIMEOUT" "$WP_BIN" --path="$SITE_PATH" --skip-plugins --skip-themes --exec="$WPX_EXEC" "$@" </dev/null
    else
      "$WP_BIN" --path="$SITE_PATH" --skip-plugins --skip-themes --exec="$WPX_EXEC" "$@" </dev/null
    fi
  )
}

# wpx_try: run, capture stdout in WP_OUT, stderr in WP_ERR, status in WP_RC.
wpx_try() {
  local errf; errf="$(mktemp)"
  WP_OUT="$(wpx "$@" 2>"$errf")"; WP_RC=$?
  WP_ERR="$(cat "$errf")"; rm -f "$errf"
  return "$WP_RC"
}

# wpx_nostdout: like wpx_try but stdout is discarded (used where WP-CLI could
# print a generated password). WP_OUT stays empty.
wpx_nostdout() {
  local errf; errf="$(mktemp)"
  wpx "$@" >/dev/null 2>"$errf"; WP_RC=$?
  WP_OUT=""; WP_ERR="$(cat "$errf")"; rm -f "$errf"
  return "$WP_RC"
}

# err_clean: WP_ERR without PHP notices/warnings/deprecations and blank lines.
err_clean() { printf '%s\n' "$WP_ERR" | grep -v -E '^(PHP )?(Notice|Warning|Deprecated)' | grep -v '^$'; }

err_reason() {
  local r
  if [ "${WP_RC:-0}" -eq 124 ]; then printf 'timed out after %ss' "$WP_TIMEOUT"; return; fi
  r="$(err_clean | grep -i -m1 '^error')"
  [ -n "$r" ] || r="$(err_clean | sed -n '1p')"
  r="${r#Error: }"
  r="${r:-exit ${WP_RC:-?} with no message}"
  printf '%s' "${r:0:200}"
}

# lookup_user IDENT -> U_FOUND (0/1), U_ID. rc 0 ok, 2 WP-CLI error (WP_ERR set).
# `wp user get` accepts an ID, email, or login. If IDENT is an email and no
# account has that email, WP-CLI falls back to a login equal to that string;
# that is treated as "found" (the conservative answer).
lookup_user() {
  U_FOUND=0; U_ID=""
  if wpx_try user get "$1" --field=ID; then
    case "$WP_OUT" in ''|*[!0-9]*) WP_ERR="Error: unexpected user id output"; return 2 ;; esac
    U_FOUND=1; U_ID="$WP_OUT"
    return 0
  fi
  case "$WP_ERR" in *"Invalid user"*) return 0 ;; esac
  return 2
}

user_field() { # ID FIELD -> UF
  wpx_try user get "$1" --field="$2" || return 2
  UF="$WP_OUT"
}

# Roles come back as a JSON *string* with ", " separators ("administrator, editor"),
# not an array. Delete [ ] " and turn ", " into ","; spaces inside a slug are kept
# (a slug like "weird role" is legal in WordPress and is refused later by valid_slug).
user_roles() { # ID -> UROLES (comma-separated slugs, empty if none)
  wpx_try user get "$1" --field=roles --format=json || return 2
  UROLES="$(printf '%s' "$WP_OUT" | tr -d '[]"' | sed 's/, /,/g')"
}

has_role() { case ",$1," in *",$2,"*) return 0 ;; esac; return 1; }

json_str() { printf '%s' "$1" | sed -n "s/.*\"$2\":\"\([^\"]*\)\".*/\1/p"; }

# marker_read ID -> rc 0 present, 1 absent, 2 error. Sets MK_*.
# A missing key makes `wp user meta get` exit 1 with no message (or "Could not find").
# Only exit status 1 counts as "absent"; a timeout (124), SIGKILL (137), PHP fatal
# (255) etc. are errors even when stderr is empty, or "absent" would hide a marker.
marker_read() {
  MK_STATE=""; MK_AT=""; MK_SERVER=""; MK_ROLES=""; MK_EMAIL=""
  if ! wpx_try user meta get "$1" "$MARKER_KEY" --format=json; then
    if [ "$WP_RC" -eq 1 ] && { [ -z "$(err_clean)" ] || [[ "$WP_ERR" == *"Could not find"* ]]; }; then return 1; fi
    return 2
  fi
  [ -n "$WP_OUT" ] || return 1
  MK_STATE="$(json_str "$WP_OUT" state)"
  MK_AT="$(json_str "$WP_OUT" at)"
  MK_SERVER="$(json_str "$WP_OUT" server)"
  MK_EMAIL="$(json_str "$WP_OUT" email)"
  MK_ROLES="$(printf '%s' "$WP_OUT" | sed -n 's/.*"roles":\[\([^]]*\)\].*/\1/p' | tr -d '"')"
  if [ -z "$MK_STATE" ]; then WP_ERR="Error: marker present but unreadable"; WP_RC=1; return 2; fi
  return 0
}

# marker_write ID STATE (uses MK_AT MK_SERVER MK_ROLES MK_EMAIL).
marker_write() {
  local roles_json json
  roles_json="$(printf '%s' "$MK_ROLES" | awk -F, '{ for (i = 1; i <= NF; i++) if ($i != "") printf "%s\"%s\"", (n++ ? "," : ""), $i }')"
  json="{\"at\":\"$MK_AT\",\"server\":\"$MK_SERVER\",\"roles\":[$roles_json],\"email\":\"$MK_EMAIL\",\"state\":\"$2\"}"
  wpx_nostdout user meta update "$1" "$MARKER_KEY" "$json" --format=json
}

# try_step N DESCRIPTION CMD... : run, record success or failure, never abort.
try_step() {
  local n="$1" desc="$2"; shift 2
  if "$@"; then step_ok="${step_ok:+$step_ok,}$n"; return 0; fi
  step_fail="${step_fail:+$step_fail; }$n ($desc): $(err_reason)"
  return 1
}
