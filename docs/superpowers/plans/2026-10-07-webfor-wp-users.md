# Webfor WP Users Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `webfor-wp-users`, a bash tool that adds, disables, and restores one Webfor employee across the WordPress applications on a Cloudways server using WP-CLI, tested end to end in a Docker sandbox.

**Architecture:** One bash entry point (`bin/webfor-wp-users`) sources small libraries under `lib/`. All WP-CLI invocation and output parsing lives in `lib/wp.sh`. Each operation is one function per site (`op_add_site`, `op_disable_site`, `op_restore_site`) that records exactly one result through `lib/report.sh`. A Docker Compose sandbox (MariaDB + `wordpress:cli`) builds fixture applications laid out like Cloudways and runs a bash test suite against the real tool.

**Tech Stack:** bash (4.4+; the Docker image and Cloudways have it), WP-CLI, Docker Compose, MariaDB 10.11. No other dependencies.

**Spec:** `docs/superpowers/specs/2026-10-07-webfor-wp-users-design.md`

## Global Constraints

- Never delete a WordPress user or content. The string `user delete` must not appear in `bin/` or `lib/` (a test enforces it).
- Dry run is the default. Writes require `--execute`.
- Every `wp` call uses `--path=<public_html> --skip-plugins --skip-themes` and `</dev/null`.
- Applications are discovered under `/home/master/applications/*/public_html` (override with `--apps-root`).
- Default `--allowed-domain` is `webfor.com`. Usernames match `^[a-z0-9._-]+$` and are not all digits.
- Disabled-account email is exactly `disabled+<ID>@webfor.invalid`. The marker usermeta key is exactly `webfor_disabled`.
- Disable steps in order: 1 write marker (`state=in_progress`), 2 scramble password via `wp user reset-password --skip-email` (output discarded), 3 `wp user session destroy --all`, 4 `wp user application-password delete --all`, 5 remove every role, 6 swap email, 7 marker `state=complete`.
- Statuses: add = `CREATED`, `WOULD CREATE`, `ALREADY EXISTS`, `EMAIL CONFLICT`, `USERNAME CONFLICT`; disable = `DISABLED`, `WOULD DISABLE`, `ALREADY DISABLED`, `NOT FOUND`, `EMAIL MISMATCH`, `LAST ADMIN`; restore = `RESTORED`, `WOULD RESTORE`, `NOT DISABLED`, `NOT FOUND`, `EMAIL MISMATCH`, `EMAIL CONFLICT`; any op = `FAILED`, `SKIPPED`. Review statuses (shown as `- REVIEW REQUIRED`, exit code 1): `EMAIL CONFLICT`, `USERNAME CONFLICT`, `EMAIL MISMATCH`, `LAST ADMIN`.
- Exit codes: `0` no `FAILED` and no review status, `1` at least one, `2` usage error.
- Logs: `<log-dir>/YYYYMMDD-HHMMSS_<server>_<op>.log` plus sibling `.tsv`, mode 600, never containing passwords. The console prints a line `Log: <path>`.
- No plugin is installed, enabled, or configured. WP 2FA is never touched.
- Commit trailer on every commit: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.

## Review Focus

These are inputs the spec implies but a straight reading of the tasks would not exercise. Each has a named test in the task that owns the code.

1. Folder names with path traversal or odd characters in `--sites` / `--exclude` (`../etc`, `.`, `a;b`) must be rejected with exit 2, never reach the filesystem (Task 2).
2. Email case differences (`Jane.Doe@Webfor.com` vs stored `jane.doe@webfor.com`) must still match as the same account for `add` and for the `disable` guard (Tasks 3, 4).
3. Running `add` again after `disable` must say `ALREADY EXISTS - DISABLED, use restore`, not `USERNAME CONFLICT` (the swapped email hides the account) (Task 4).
4. A user with more than one role must get all roles back on restore (Task 5).
5. A hung WP-CLI call on one site must time out as `FAILED`, and the run must continue with the next site (Task 6).

---

## File Structure

```
bin/webfor-wp-users            # CLI entry: arg parsing, targeting, main loop
lib/common.sh                  # usage errors, logging, input validation
lib/wp.sh                      # wpx wrappers, user/marker helpers, try_step
lib/report.sh                  # per-site result state, table, totals, TSV, exit code
lib/discover.sh                # app discovery, site validation
lib/op_add.sh                  # op_add_site
lib/op_disable.sh              # op_disable_site
lib/op_restore.sh              # op_restore_site
tests/run.sh                   # host entry: runs the suite in Docker
tests/suite.sh                 # in-container runner
tests/docker/{Dockerfile,compose.yml}
tests/lib/assert.sh            # ok/bad/assert_*
tests/lib/fixtures.sh          # fixture apps, run_tool, helpers
tests/lib/wp-shim.sh           # WP-CLI test double: injected failures / hangs
tests/t_00_probe.sh            # verifies the WP-CLI behaviours lib/wp.sh relies on
tests/t_10_framework.sh        # validation, discovery, reporting
tests/t_20_add.sh
tests/t_30_disable.sh
tests/t_40_restore.sh
tests/t_50_safety.sh
tests/example_report.sh        # generates docs/example-report.md
docs/{runbook,limitations,example-report,pilot-results}.md
```

---

### Task 1: Sandbox harness and WP-CLI behaviour probe

**Files:**
- Create: `.gitignore`, `tests/docker/Dockerfile`, `tests/docker/compose.yml`, `tests/run.sh`, `tests/suite.sh`, `tests/lib/assert.sh`, `tests/lib/fixtures.sh`, `tests/t_00_probe.sh`

**Interfaces:**
- Produces (in `tests/lib/fixtures.sh`, used by every later test): variables `ROOT`, `FX_ROOT`, `LOGS`, `APPS_WP`, arrays `ADD`, `DIS`, `RST`; functions `fwp APP wp-args…`, `fixtures_build`, `fixtures_reset`, `fp APP`, `all_fp`, `mail_count APP`, `run_tool OP args…` (sets `OUT`, `RC`, `TSV`), `status_of FOLDER`, `detail_of FOLDER`, `warn_of FOLDER`, `roles_sorted APP USER`, `user_count APP`, `auth_ok APP LOGIN PW` (yes/no), `app_pw_ok APP LOGIN PW` (yes/no).
- Produces (in `tests/lib/assert.sh`): `ok LABEL`, `bad LABEL`, `assert_eq EXPECTED ACTUAL LABEL`, `assert_contains HAYSTACK NEEDLE LABEL`, `assert_not_contains HAYSTACK NEEDLE LABEL`, `assert_summary`.
- Fixture application folders under `/fixtures/applications`: `app_a`, `app_b` (plain), `app_exists` (jane.doe already an administrator), `app_emailtaken` (editor `someone` owns jane.doe@webfor.com), `app_usertaken` (editor `jane.doe` with other@client-e.test), `app_soleadmin` (jane.doe is the only administrator), `app_notwp` (empty `public_html`), `app_nopublic` (no `public_html`), `app_broken` (wrong DB password), `app_multisite`.

- [ ] **Step 1: Initialize the repository and ignore files**

The folder is not yet under git.

```bash
cd /path/to/cloudways-bulk-users
git init
printf 'logs/\ngraft/\n.DS_Store\n' > .gitignore
mkdir -p bin lib tests/lib tests/docker docs
```

- [ ] **Step 2: Write the Docker files**

`tests/docker/Dockerfile`:

```dockerfile
FROM wordpress:cli
USER root
RUN apk add --no-cache bash coreutils \
 && mkdir -p /fixtures \
 && chown www-data:www-data /fixtures
USER www-data
WORKDIR /work
```

`tests/docker/compose.yml`:

```yaml
services:
  db:
    image: mariadb:10.11
    environment:
      MARIADB_ROOT_PASSWORD: sandbox-root
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 3s
      timeout: 3s
      retries: 40
  runner:
    build: .
    depends_on:
      db:
        condition: service_healthy
    environment:
      DB_HOST: db
      DB_ROOT_PASSWORD: sandbox-root
      WP_ENVIRONMENT_TYPE: local
      WP_CLI_CACHE_DIR: /tmp/wpcache
    volumes:
      - ../..:/work
      - fixtures:/fixtures
    working_dir: /work
volumes:
  fixtures:
```

`WP_ENVIRONMENT_TYPE: local` is required: WordPress only allows application passwords over HTTPS unless the environment type is `local`, and the sandbox has no TLS.

- [ ] **Step 3: Write the host runner and in-container runner**

`tests/run.sh`:

```bash
#!/usr/bin/env bash
# Run the sandbox suite in Docker. Usage: tests/run.sh [name-fragment]
# e.g. tests/run.sh add   -> only tests/t_*add*.sh
set -eu
cd "$(dirname "$0")/.."
trap 'docker compose -f tests/docker/compose.yml down >/dev/null 2>&1 || true' EXIT
docker compose -f tests/docker/compose.yml run --rm --build runner bash tests/suite.sh "$@"
```

`tests/suite.sh`:

```bash
#!/usr/bin/env bash
# Runs inside the sandbox container: build fixtures once, then each tests/t_*.sh.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT/tests/lib/assert.sh"
. "$ROOT/tests/lib/fixtures.sh"

fixtures_build
shopt -s nullglob
for t in "$ROOT"/tests/t_*"${1:-}"*.sh; do
  echo "== $(basename "$t")"
  . "$t"
done
assert_summary
```

```bash
chmod +x tests/run.sh tests/suite.sh
```

- [ ] **Step 4: Write the assertion library**

`tests/lib/assert.sh`:

```bash
PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }
assert_eq() { # EXPECTED ACTUAL LABEL
  if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (expected '$1', got '$2')"; fi
}
assert_contains() { # HAYSTACK NEEDLE LABEL
  case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2')" ;; esac
}
assert_not_contains() { # HAYSTACK NEEDLE LABEL
  case "$1" in *"$2"*) bad "$3 (found '$2')" ;; *) ok "$3" ;; esac
}
assert_summary() {
  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ]
}
```

- [ ] **Step 5: Write the fixtures library**

`tests/lib/fixtures.sh`:

```bash
FX_ROOT=/fixtures/applications
CORE=/fixtures/.core
SNAP=/fixtures/snap
LOGS=/tmp/wwu-logs
DBH="${DB_HOST:-db}"
DBP="${DB_ROOT_PASSWORD:-sandbox-root}"
APPS_WP="app_a app_b app_exists app_emailtaken app_usertaken app_soleadmin"

ADD=(add --username jane.doe --email jane.doe@webfor.com --first-name Jane --last-name Doe --display-name "Jane Doe")
DIS=(disable --username jane.doe --email jane.doe@webfor.com)
RST=(restore --username jane.doe --email jane.doe@webfor.com)

fwp() { local app="$1"; shift; wp --path="$FX_ROOT/$app/public_html" "$@"; }

install_mailtrap() { # public_html dir. Logs wp_mail() calls instead of sending.
  mkdir -p "$1/wp-content/mu-plugins"
  cat > "$1/wp-content/mu-plugins/mailtrap.php" <<'PHP'
<?php
add_filter( 'pre_wp_mail', function ( $pre, $atts ) {
	$to = is_array( $atts['to'] ) ? implode( ',', $atts['to'] ) : $atts['to'];
	file_put_contents( WP_CONTENT_DIR . '/mail.log', $to . ' | ' . $atts['subject'] . "\n", FILE_APPEND );
	return true;
}, 10, 2 );
PHP
}

fx_install() { # APP ADMIN_USER ADMIN_EMAIL
  local app="$1" dir="$FX_ROOT/$1/public_html"
  mkdir -p "$dir"
  cp -R "$CORE/." "$dir/"
  wp --path="$dir" config create --dbhost="$DBH" --dbname="wwu_$app" --dbuser=root --dbpass="$DBP" --skip-check >/dev/null
  wp --path="$dir" db drop --yes >/dev/null 2>&1
  wp --path="$dir" db create >/dev/null
  wp --path="$dir" core install --url="https://$app.test" --title="$app" --admin_user="$2" \
    --admin_email="$3" --admin_password="sandbox-pass-$app" --skip-email >/dev/null
  install_mailtrap "$dir"
}

fixtures_build() {
  echo "building fixtures (about a minute)..." >&2
  rm -rf "$FX_ROOT" "$SNAP"
  mkdir -p "$FX_ROOT" "$SNAP" "$LOGS"
  if [ ! -f "$CORE/wp-load.php" ]; then
    mkdir -p "$CORE"
    wp core download --path="$CORE" >/dev/null
  fi
  fx_install app_a admin admin@client-a.test
  fx_install app_b admin admin@client-b.test
  fx_install app_exists admin admin@client-c.test
  fwp app_exists user create jane.doe jane.doe@webfor.com --role=administrator \
    --first_name=Jane --last_name=Doe --porcelain >/dev/null
  fx_install app_emailtaken admin admin@client-d.test
  fwp app_emailtaken user create someone jane.doe@webfor.com --role=editor --porcelain >/dev/null
  fx_install app_usertaken admin admin@client-e.test
  fwp app_usertaken user create jane.doe other@client-e.test --role=editor --porcelain >/dev/null
  fx_install app_soleadmin jane.doe jane.doe@webfor.com
  mkdir -p "$FX_ROOT/app_notwp/public_html" "$FX_ROOT/app_nopublic"
  fx_install app_multisite admin admin@client-g.test
  fwp app_multisite core multisite-convert --title=network >/dev/null
  fx_install app_broken admin admin@client-f.test
  sed -i "s/define( 'DB_PASSWORD', '[^']*' )/define( 'DB_PASSWORD', 'wrong' )/" \
    "$FX_ROOT/app_broken/public_html/wp-config.php"
  local a
  for a in $APPS_WP; do fwp "$a" db export "$SNAP/$a.sql" >/dev/null; done
}

fixtures_reset() {
  local a
  for a in $APPS_WP; do
    fwp "$a" db import "$SNAP/$a.sql" >/dev/null
    rm -f "$FX_ROOT/$a/public_html/wp-content/mail.log"
  done
  rm -rf "$LOGS"; mkdir -p "$LOGS"
}

fp() { # APP -> fingerprint of users, usermeta, posts, and non-transient options
  fwp "$1" db query "SELECT * FROM wp_users ORDER BY ID; SELECT * FROM wp_usermeta ORDER BY umeta_id; SELECT ID,post_author,post_title,post_status FROM wp_posts ORDER BY ID; SELECT option_name,option_value FROM wp_options WHERE option_name NOT LIKE '%transient%' AND option_name <> 'cron' ORDER BY option_name;" 2>/dev/null | sha256sum | cut -d' ' -f1
}
all_fp() { local a out=""; for a in $APPS_WP; do out="$out$(fp "$a")"; done; printf '%s' "$out"; }

mail_count() { local f="$FX_ROOT/$1/public_html/wp-content/mail.log"; if [ -f "$f" ]; then wc -l < "$f" | tr -d ' '; else echo 0; fi; }
user_count() { fwp "$1" user list --format=count; }
roles_sorted() { fwp "$1" user get "$2" --field=roles --format=json | tr -d '[]"' | tr ',' '\n' | sort | paste -sd, -; }

run_tool() { # OP args... ; sets OUT RC TSV. Stdin comes from $TOOL_STDIN.
  local op="$1"; shift
  OUT="$(printf '%s\n' "${TOOL_STDIN:-}" | bash "$ROOT/bin/webfor-wp-users" "$op" \
    --apps-root "$FX_ROOT" --log-dir "$LOGS" --server testsrv "$@" 2>&1)"
  RC=$?
  TSV="$(printf '%s\n' "$OUT" | sed -n 's/^Log: //p' | head -1)"
  TSV="${TSV%.log}.tsv"
}
tsv_col() { awk -F'\t' -v f="$1" -v c="$2" '$2 == f { print $c }' "$TSV"; }
status_of() { tsv_col "$1" 7; }
detail_of() { tsv_col "$1" 8; }
warn_of()   { tsv_col "$1" 9; }

auth_ok() { # APP LOGIN PASSWORD -> yes|no
  WWU_L="$2" WWU_PW="$3" fwp "$1" eval 'echo is_wp_error( wp_authenticate( getenv( "WWU_L" ), getenv( "WWU_PW" ) ) ) ? "no" : "yes";' 2>/dev/null
}
app_pw_ok() { # APP LOGIN APP_PASSWORD -> yes|no
  WWU_L="$2" WWU_PW="$3" fwp "$1" eval '$u = get_user_by( "login", getenv( "WWU_L" ) ); $r = "no"; foreach ( WP_Application_Passwords::get_user_application_passwords( $u->ID ) as $p ) { if ( wp_check_password( getenv( "WWU_PW" ), $p["password"], $u->ID ) ) { $r = "yes"; } } echo $r;' 2>/dev/null
}
```

If `wp db create` reports an SSL error from the mariadb client, add `--skip-ssl` to the `db create`, `db drop`, `db export`, `db import`, and `db query` calls in this file and re-run.

- [ ] **Step 6: Write the probe test**

This pins the WP-CLI behaviours `lib/wp.sh` will parse. If an assertion here fails, fix the matching helper in Task 2 (all parsing lives in `lib/wp.sh`), not the test.

`tests/t_00_probe.sh`:

```bash
# Verifies the WP-CLI behaviours lib/wp.sh relies on (spec section 10).
fixtures_reset
A=app_a
id="$(fwp "$A" user create probe probe@webfor.com --role=administrator --porcelain)"
case "$id" in ''|*[!0-9]*) bad "create --porcelain prints only the id (got '$id')" ;; *) ok "create --porcelain prints only the id" ;; esac

assert_eq '["administrator"]' "$(fwp "$A" user get probe --field=roles --format=json)" "roles field as JSON"
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

fwp "$A" user update "$id" --user_pass=probe-pass-1 >/dev/null
assert_eq yes "$(auth_ok "$A" probe probe-pass-1)" "known password authenticates"
fwp "$A" user reset-password "$id" --skip-email >/dev/null 2>&1
assert_eq no "$(auth_ok "$A" probe probe-pass-1)" "reset-password --skip-email scrambles the password"

fwp "$A" user update "$id" --user_email="disabled+$id@webfor.invalid" >/dev/null
assert_eq "disabled+$id@webfor.invalid" "$(fwp "$A" user get "$id" --field=user_email)" ".invalid email accepted"
assert_eq 0 "$(mail_count "$A")" "create, reset-password and email change send no mail"

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
assert_eq '[]' "$(fwp "$A" user get "$id" --field=roles --format=json)" "remove-role can leave no roles"
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
```

- [ ] **Step 7: Run the probe**

Run: `chmod +x tests/run.sh && tests/run.sh probe`
Expected: fixtures build, then all probe lines print `ok`; summary `N passed, 0 failed`. The two `note:` lines are informational. If any line fails, record the actual WP-CLI behaviour in a comment at the top of the probe file and adapt the matching helper when writing `lib/wp.sh` in Task 2.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "test: Docker sandbox, fixtures, and WP-CLI behaviour probe" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Framework: CLI, discovery, validation, reporting

**Files:**
- Create: `bin/webfor-wp-users`, `lib/common.sh`, `lib/wp.sh`, `lib/report.sh`, `lib/discover.sh`, `tests/t_10_framework.sh`

**Interfaces:**
- Consumes: Task 1 test helpers.
- Produces (shell globals set by the CLI, used by ops): `OPERATION`, `USERNAME`, `EMAIL`, `FIRST_NAME`, `LAST_NAME`, `DISPLAY_NAME`, `ROLE`, `EXECUTE` (0/1), `SEND_EMAIL`, `SERVER_NAME`, `APPS_ROOT`, `MODE`.
- Produces (per-site state set before each op): `SITE_FOLDER`, `SITE_PATH`, `SITE_LABEL`; result fields `R_WP`, `R_EXISTS`, `R_ROLE`, `R_ACTION`, `R_WARN`.
- Produces functions: `wpx ARGS…`; `wpx_try ARGS…` (sets `WP_OUT`, `WP_ERR`, `WP_RC`); `wpx_nostdout ARGS…` (same but stdout discarded, `WP_OUT=""`); `err_clean`; `err_reason`; `lookup_user IDENT` (sets `U_FOUND` 0/1, `U_ID`; rc 0 ok, 2 error); `user_field ID FIELD` (sets `UF`); `user_roles ID` (sets `UROLES`, comma-separated); `has_role LIST ROLE`; `marker_read ID` (rc 0 present, 1 absent, 2 error; sets `MK_STATE MK_AT MK_SERVER MK_ROLES MK_EMAIL`); `marker_write ID STATE`; `try_step N DESC CMD…` (appends to `step_ok` / `step_fail`); `record_result STATUS [DETAIL]`; `is_review_status STATUS`.
- Dispatch contract: `process_site` calls `op_${OPERATION}_site` with no arguments; the op must call `record_result` exactly once.

- [ ] **Step 1: Write the failing framework test**

`tests/t_10_framework.sh`:

```bash
fixtures_reset

# --- usage errors exit 2 and touch nothing -------------------------------
run_tool add --username jane.doe --email jane.doe@webfor.com --first-name L --last-name I --display-name "L I"
assert_eq 2 "$RC" "no targeting -> exit 2"
run_tool add --username jane.doe --email jane.doe@webfor.com --first-name L --last-name I --display-name "L I" --all --sites app_a
assert_eq 2 "$RC" "--all and --sites together -> exit 2"
run_tool add --username Jane --email jane.doe@webfor.com --first-name L --last-name I --display-name "L I" --all
assert_eq 2 "$RC" "uppercase username rejected"
run_tool add --username 12345 --email jane.doe@webfor.com --first-name L --last-name I --display-name "L I" --all
assert_eq 2 "$RC" "all-digit username rejected"
run_tool add --username jane.doe --email jane@client.com --first-name L --last-name I --display-name "L I" --all
assert_eq 2 "$RC" "email outside allowed domain rejected"
run_tool add --username jane.doe --email jane.doe@webfor.com --display-name "L I" --all
assert_eq 2 "$RC" "add without first/last name rejected"
run_tool disable --username jane.doe --email jane.doe@webfor.com --sites ../etc
assert_eq 2 "$RC" "path traversal in --sites rejected"
run_tool disable --username jane.doe --email jane.doe@webfor.com --sites .
assert_eq 2 "$RC" "dot folder rejected"
run_tool disable --username jane.doe --email jane.doe@webfor.com --sites 'a;b'
assert_eq 2 "$RC" "odd characters in --sites rejected"
run_tool disable --username jane.doe --email jane.doe@webfor.com --all --exclude ../x
assert_eq 2 "$RC" "path traversal in --exclude rejected"
run_tool bogus --username x
assert_eq 2 "$RC" "unknown operation rejected"

# --- discovery and validation (op-independent statuses) -------------------
run_tool disable --username jane.doe --email jane.doe@webfor.com --all
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

run_tool disable --username jane.doe --email jane.doe@webfor.com --sites app_nope
assert_eq SKIPPED "$(status_of app_nope)" "unknown folder -> SKIPPED row, not a crash"
assert_contains "$(detail_of app_nope)" "no such application folder" "reason: no such folder"

run_tool disable --username jane.doe --email jane.doe@webfor.com --all --exclude app_a,app_b,app_exists,app_emailtaken,app_usertaken,app_soleadmin,app_notwp,app_nopublic,app_multisite,app_broken
assert_eq 1 "$RC" "zero targets after --exclude -> exit 1"
assert_contains "$OUT" "no applications" "zero-target message"

mkdir -p /tmp/wwu-empty-root
run_tool disable --username jane.doe --email jane.doe@webfor.com --all --apps-root /tmp/wwu-empty-root
assert_eq 1 "$RC" "empty apps root -> exit 1"

run_tool disable --username jane.doe --email jane.doe@webfor.com --all --exclude app_a
assert_eq "" "$(status_of app_a)" "--exclude removes a folder from the run"

# --- logging ---------------------------------------------------------------
LOGF="${TSV%.tsv}.log"
assert_eq 600 "$(stat -c %a "$LOGF")" "log file mode 600"
assert_contains "$(cat "$LOGF")" "server=testsrv" "log records the server"
assert_contains "$(cat "$LOGF")" "jane.doe" "log records the username"
```

- [ ] **Step 2: Run to verify it fails**

Run: `tests/run.sh framework`
Expected: FAIL (the tool does not exist; every `assert_eq 2 "$RC"` reports a different code).

- [ ] **Step 3: Write `lib/common.sh`**

```bash
#!/usr/bin/env bash
# Shared helpers: usage errors, logging, input validation.

die_usage() { printf 'error: %s\n' "$*" >&2; exit 2; }

lower() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }

log_line() {
  [ -n "${LOG_FILE:-}" ] || return 0
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

# say: print to the console and the log.
say() { printf '%s\n' "$*"; log_line "$*"; }

valid_username() { [[ "$1" =~ ^[a-z0-9._-]+$ ]] && [[ ! "$1" =~ ^[0-9]+$ ]]; }
valid_email() {
  local re='^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
  [[ "$1" =~ $re ]]
}
valid_slug()   { [[ "$1" =~ ^[a-z0-9_-]+$ ]]; }
valid_folder() { [[ "$1" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]*$ ]]; }
email_in_domain() { [ "$(lower "${1##*@}")" = "$(lower "$2")" ]; }
tsv_clean() { printf '%s' "$1" | tr '\t\n\r' '   '; }
```

- [ ] **Step 4: Write `lib/wp.sh`**

```bash
#!/usr/bin/env bash
# WP-CLI access for one site (SITE_PATH). All parsing of WP-CLI output lives
# here, so a WP-CLI behaviour change has exactly one place to fix.

WP_BIN="${WP_BIN:-wp}"
WP_TIMEOUT="${WP_TIMEOUT:-120}"
TIMEOUT_BIN=""
command -v timeout >/dev/null 2>&1 && TIMEOUT_BIN="timeout"
MARKER_KEY="webfor_disabled"

wpx() {
  if [ -n "$TIMEOUT_BIN" ]; then
    "$TIMEOUT_BIN" "$WP_TIMEOUT" "$WP_BIN" --path="$SITE_PATH" --skip-plugins --skip-themes "$@" </dev/null
  else
    "$WP_BIN" --path="$SITE_PATH" --skip-plugins --skip-themes "$@" </dev/null
  fi
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

user_roles() { # ID -> UROLES (comma-separated slugs, empty if none)
  wpx_try user get "$1" --field=roles --format=json || return 2
  UROLES="$(printf '%s' "$WP_OUT" | tr -d '[]" ')"
}

has_role() { case ",$1," in *",$2,"*) return 0 ;; esac; return 1; }

json_str() { printf '%s' "$1" | sed -n "s/.*\"$2\":\"\([^\"]*\)\".*/\1/p"; }

# marker_read ID -> rc 0 present, 1 absent, 2 error. Sets MK_*.
# A missing key makes `wp user meta get` exit 1 with no message (or "Could not find").
marker_read() {
  MK_STATE=""; MK_AT=""; MK_SERVER=""; MK_ROLES=""; MK_EMAIL=""
  if ! wpx_try user meta get "$1" "$MARKER_KEY" --format=json; then
    if [ -z "$(err_clean)" ] || [[ "$WP_ERR" == *"Could not find"* ]]; then return 1; fi
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
```

- [ ] **Step 5: Write `lib/report.sh`**

```bash
#!/usr/bin/env bash
# Per-site result state, console report, TSV, totals, exit code.

RES_LABEL=(); RES_FOLDER=(); RES_WP=(); RES_EXISTS=(); RES_ROLE=()
RES_ACTION=(); RES_STATUS=(); RES_DETAIL=(); RES_WARN=()

reset_site_state() {
  SITE_PATH=""; SITE_LABEL=""
  R_WP="-"; R_EXISTS="-"; R_ROLE="-"; R_ACTION="-"; R_WARN=""
  step_ok=""; step_fail=""
}

is_review_status() {
  case "$1" in
    "EMAIL CONFLICT"|"USERNAME CONFLICT"|"EMAIL MISMATCH"|"LAST ADMIN") return 0 ;;
  esac
  return 1
}

# record_result STATUS [DETAIL] : the one place a site's outcome is stored.
record_result() {
  local status="$1" detail="${2:-}" label="${SITE_LABEL:-(app: $SITE_FOLDER)}"
  RES_LABEL+=("$label"); RES_FOLDER+=("$SITE_FOLDER"); RES_WP+=("$R_WP")
  RES_EXISTS+=("$R_EXISTS"); RES_ROLE+=("$R_ROLE"); RES_ACTION+=("$R_ACTION")
  RES_STATUS+=("$status"); RES_DETAIL+=("$detail"); RES_WARN+=("$R_WARN")
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(tsv_clean "$label")" "$SITE_FOLDER" "$R_WP" "$R_EXISTS" "$(tsv_clean "$R_ROLE")" \
    "$R_ACTION" "$status" "$(tsv_clean "$detail")" "$(tsv_clean "$R_WARN")" >> "$TSV_FILE"
  log_line "RESULT $SITE_FOLDER: $status${detail:+ - $detail}"
  [ "$status" = FAILED ] && log_line "ERROR $SITE_FOLDER: $detail"
  return 0
}

display_status() { # index
  local s="${RES_STATUS[$1]}" d="${RES_DETAIL[$1]}"
  is_review_status "$s" && s="$s - REVIEW REQUIRED"
  [ -n "$d" ] && s="$s - $d"
  printf '%s' "$s"
}

print_report() {
  local i n=${#RES_STATUS[@]} s found=0
  say ""
  say "$MODE RESULTS: $OPERATION $USERNAME <$EMAIL> server=$SERVER_NAME"
  say "SITE | WP | USER EXISTS | ROLE | ACTION | RESULT | WARNINGS"
  for ((i = 0; i < n; i++)); do
    say "${RES_LABEL[$i]} | ${RES_WP[$i]} | ${RES_EXISTS[$i]} | ${RES_ROLE[$i]} | ${RES_ACTION[$i]} | $(display_status "$i") | ${RES_WARN[$i]:--}"
  done
  say ""
  say "Totals:"
  printf '%s\n' "${RES_STATUS[@]}" | sort | uniq -c | while read -r c s; do say "  $s: $c"; done
  say "  Applications processed: $n"
  for ((i = 0; i < n; i++)); do
    s="${RES_STATUS[$i]}"
    if [ "$s" = FAILED ] || [ "$s" = SKIPPED ] || is_review_status "$s"; then
      if [ "$found" -eq 0 ]; then say ""; say "Needs manual review:"; found=1; fi
      say "  - ${RES_LABEL[$i]}: $(display_status "$i")"
    fi
  done
  if [ "$EXECUTE" -ne 1 ]; then say ""; say "DRY RUN: no changes were made."; fi
}

# run_exit_code: 1 if any FAILED or review status, else 0.
run_exit_code() {
  local s
  for s in "${RES_STATUS[@]}"; do
    if [ "$s" = FAILED ] || is_review_status "$s"; then return 1; fi
  done
  return 0
}
```

- [ ] **Step 6: Write `lib/discover.sh`**

```bash
#!/usr/bin/env bash
# Application discovery and per-site validation. Read-only.

discover_apps() {
  local d
  for d in "$APPS_ROOT"/*/; do
    [ -d "$d" ] || continue
    basename "$d"
  done | sort
}

# validate_site: needs SITE_FOLDER. rc 0 usable (sets SITE_PATH, SITE_LABEL, R_WP).
# rc 1 unusable (sets V_STATUS, V_DETAIL).
validate_site() {
  local dir="$APPS_ROOT/$SITE_FOLDER"
  V_STATUS=""; V_DETAIL=""
  SITE_LABEL="(app: $SITE_FOLDER)"
  if [ ! -d "$dir" ]; then V_STATUS=SKIPPED; V_DETAIL="no such application folder"; return 1; fi
  SITE_PATH="$dir/public_html"
  if [ ! -d "$SITE_PATH" ]; then R_WP="No"; V_STATUS=SKIPPED; V_DETAIL="no public_html"; return 1; fi
  if ! wpx_try core is-installed; then
    R_WP="No"
    case "$WP_ERR" in
      *"does not seem to be a WordPress installation"*)
        V_STATUS=SKIPPED; V_DETAIL="not WordPress" ;;
      *)
        if [ "$WP_RC" -eq 1 ] && [ -z "$(err_clean)" ]; then
          # Silent exit 1: either WordPress is not installed, or the database is unreachable.
          if wpx_try db query "SELECT 1"; then
            V_STATUS=SKIPPED; V_DETAIL="WordPress files found but not installed"
          else
            V_STATUS=FAILED; V_DETAIL="database not reachable: $(err_reason)"
          fi
        else
          V_STATUS=FAILED; V_DETAIL="WP-CLI error: $(err_reason)"
        fi ;;
    esac
    return 1
  fi
  R_WP="Yes"
  if wpx_try core is-installed --network; then
    V_STATUS=SKIPPED; V_DETAIL="multisite, handle manually"; return 1
  fi
  if wpx_try option get siteurl && [ -n "$WP_OUT" ]; then SITE_LABEL="$WP_OUT (app: $SITE_FOLDER)"; fi
  return 0
}
```

- [ ] **Step 7: Write the CLI `bin/webfor-wp-users`**

```bash
#!/usr/bin/env bash
# webfor-wp-users: add, disable, or restore a Webfor employee across the
# WordPress applications on a Cloudways server. Dry run unless --execute.
# See docs/runbook.md.
set -u
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for f in common wp report discover; do
  # shellcheck disable=SC1090
  . "$ROOT_DIR/lib/$f.sh"
done
for f in op_add op_disable op_restore; do
  # shellcheck disable=SC1090
  [ -f "$ROOT_DIR/lib/$f.sh" ] && . "$ROOT_DIR/lib/$f.sh"
done

usage() {
  cat <<'EOF'
Usage:
  webfor-wp-users add     --username U --email E --first-name F --last-name L --display-name D
                          [--role administrator] <targeting> [--execute] [--send-email]
  webfor-wp-users disable --username U --email E <targeting> [--execute]
  webfor-wp-users restore --username U --email E <targeting> [--execute]

Targeting (exactly one):
  --sites a,b,c      application folder names under the apps root
  --all              every application (with --execute, asks you to type ALL)
  [--exclude a,b]    optional, with either form

Options:
  --apps-root DIR      default /home/master/applications
  --log-dir DIR        default ./logs
  --allowed-domain D   default webfor.com; --email must be in this domain
  --allow-any-domain   turn the domain guard off (not recommended)
  --server NAME        label recorded in the log (default: hostname)
  --execute            make changes. Without it, nothing is changed (dry run).
EOF
}

OPERATION=""; USERNAME=""; EMAIL=""; FIRST_NAME=""; LAST_NAME=""; DISPLAY_NAME=""
ROLE="administrator"; SITES=""; ALL=0; EXCLUDE=""; EXECUTE=0; SEND_EMAIL=0
APPS_ROOT="/home/master/applications"; LOG_DIR="./logs"
ALLOWED_DOMAIN="webfor.com"; ANY_DOMAIN=0; SERVER_NAME="$(hostname)"
TARGETS=(); LOG_FILE=""; TSV_FILE=""; MODE="DRY RUN"

need_val() { [ $# -ge 2 ] || die_usage "$1 needs a value"; }

parse_args() {
  [ $# -ge 1 ] || { usage >&2; exit 2; }
  case "$1" in
    -h|--help) usage; exit 0 ;;
    add|disable|restore) OPERATION="$1"; shift ;;
    *) die_usage "unknown operation: $1" ;;
  esac
  while [ $# -gt 0 ]; do
    case "$1" in
      --username)     need_val "$@"; USERNAME="$2"; shift 2 ;;
      --email)        need_val "$@"; EMAIL="$2"; shift 2 ;;
      --first-name)   need_val "$@"; FIRST_NAME="$2"; shift 2 ;;
      --last-name)    need_val "$@"; LAST_NAME="$2"; shift 2 ;;
      --display-name) need_val "$@"; DISPLAY_NAME="$2"; shift 2 ;;
      --role)         need_val "$@"; ROLE="$2"; shift 2 ;;
      --sites)        need_val "$@"; SITES="$2"; shift 2 ;;
      --exclude)      need_val "$@"; EXCLUDE="$2"; shift 2 ;;
      --apps-root)    need_val "$@"; APPS_ROOT="$2"; shift 2 ;;
      --log-dir)      need_val "$@"; LOG_DIR="$2"; shift 2 ;;
      --allowed-domain) need_val "$@"; ALLOWED_DOMAIN="$2"; shift 2 ;;
      --server)       need_val "$@"; SERVER_NAME="$2"; shift 2 ;;
      --all)          ALL=1; shift ;;
      --execute)      EXECUTE=1; shift ;;
      --send-email)   SEND_EMAIL=1; shift ;;
      --allow-any-domain) ANY_DOMAIN=1; shift ;;
      -h|--help)      usage; exit 0 ;;
      *) die_usage "unknown option: $1" ;;
    esac
  done
}

check_folder_list() { # label list
  local item
  [ -z "$2" ] && return 0
  IFS=',' read -r -a _items <<< "$2"
  for item in "${_items[@]}"; do
    valid_folder "$item" || die_usage "invalid folder name in $1: '$item'"
  done
}

validate_args() {
  [ -n "$USERNAME" ] || die_usage "--username is required"
  valid_username "$USERNAME" || die_usage "--username must match [a-z0-9._-]+ and not be all digits"
  [ -n "$EMAIL" ] || die_usage "--email is required"
  valid_email "$EMAIL" || die_usage "--email is not a valid email address"
  if [ "$ANY_DOMAIN" -ne 1 ] && ! email_in_domain "$EMAIL" "$ALLOWED_DOMAIN"; then
    die_usage "--email must be in @$ALLOWED_DOMAIN (or pass --allow-any-domain)"
  fi
  if [ "$OPERATION" = add ]; then
    [ -n "$FIRST_NAME" ] && [ -n "$LAST_NAME" ] && [ -n "$DISPLAY_NAME" ] \
      || die_usage "add requires --first-name, --last-name and --display-name"
    valid_slug "$ROLE" || die_usage "--role must be a role slug"
  elif [ "$SEND_EMAIL" -eq 1 ]; then
    die_usage "--send-email only applies to add"
  fi
  if [ "$ALL" -eq 1 ] && [ -n "$SITES" ]; then die_usage "use either --sites or --all, not both"; fi
  if [ "$ALL" -ne 1 ] && [ -z "$SITES" ]; then die_usage "one of --sites or --all is required"; fi
  check_folder_list --sites "$SITES"
  check_folder_list --exclude "$EXCLUDE"
  [ "$EXECUTE" -eq 1 ] && MODE="EXECUTE"
  return 0
}

select_targets() {
  local d t x skip out=()
  TARGETS=()
  if [ "$ALL" -eq 1 ]; then
    while IFS= read -r d; do TARGETS+=("$d"); done < <(discover_apps)
  else
    IFS=',' read -r -a _sel <<< "$SITES"
    for d in "${_sel[@]}"; do TARGETS+=("$d"); done
  fi
  if [ -n "$EXCLUDE" ]; then
    IFS=',' read -r -a _exc <<< "$EXCLUDE"
    for t in ${TARGETS[@]+"${TARGETS[@]}"}; do
      skip=0
      for x in "${_exc[@]}"; do [ "$t" = "$x" ] && skip=1; done
      [ "$skip" -eq 0 ] && out+=("$t")
    done
    if [ ${#out[@]} -eq 0 ]; then TARGETS=(); else TARGETS=("${out[@]}"); fi
  fi
}

confirm_all() {
  [ "$ALL" -eq 1 ] && [ "$EXECUTE" -eq 1 ] || return 0
  local ans=""
  printf 'About to %s %s on ALL %d applications on %s. Type ALL to continue: ' \
    "$OPERATION" "$USERNAME" "${#TARGETS[@]}" "$SERVER_NAME" >&2
  read -r ans || true
  [ "$ans" = "ALL" ] || { echo "aborted." >&2; exit 2; }
}

init_run() {
  umask 077
  mkdir -p "$LOG_DIR" || die_usage "cannot create log dir $LOG_DIR"
  local stamp server n=1
  stamp="$(date '+%Y%m%d-%H%M%S')"
  server="$(printf '%s' "$SERVER_NAME" | tr -c 'A-Za-z0-9._-' '_')"
  LOG_FILE="$LOG_DIR/${stamp}_${server}_${OPERATION}.log"
  while [ -e "$LOG_FILE" ]; do n=$((n + 1)); LOG_FILE="$LOG_DIR/${stamp}_${server}_${OPERATION}-$n.log"; done
  TSV_FILE="${LOG_FILE%.log}.tsv"
  : > "$LOG_FILE"; : > "$TSV_FILE"
}

process_site() {
  SITE_FOLDER="$1"
  reset_site_state
  local before=${#RES_STATUS[@]}
  if ! validate_site; then record_result "$V_STATUS" "$V_DETAIL"; return; fi
  if declare -F "op_${OPERATION}_site" >/dev/null; then
    "op_${OPERATION}_site"
  else
    record_result FAILED "operation '$OPERATION' is not implemented"
  fi
  [ ${#RES_STATUS[@]} -gt "$before" ] || record_result FAILED "internal error: no result recorded"
}

main() {
  parse_args "$@"
  validate_args
  select_targets
  if [ ${#TARGETS[@]} -eq 0 ]; then echo "error: no applications to process" >&2; exit 1; fi
  confirm_all
  init_run
  say "$MODE: $OPERATION $USERNAME <$EMAIL> server=$SERVER_NAME"
  say "Applications to process: ${#TARGETS[@]}"
  say "Log: $LOG_FILE"
  local i=0 n=${#TARGETS[@]} f
  for f in "${TARGETS[@]}"; do
    i=$((i + 1)); printf '[%d/%d] %s\n' "$i" "$n" "$f" >&2
    process_site "$f"
  done
  print_report
  run_exit_code
  exit $?
}

main "$@"
```

Notes: zero-target runs print to stderr and exit 1 before any log is created, so the test reads the message from `OUT`. `"no applications"` matches `error: no applications to process`.

```bash
chmod +x bin/webfor-wp-users
```

- [ ] **Step 8: Run the framework test**

Run: `tests/run.sh framework`
Expected: all `ok`, `0 failed`. If a status assertion fails because WP-CLI behaves differently than the probe notes recorded, adjust `validate_site` in `lib/discover.sh` and re-run.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: CLI framework, discovery, validation, reporting" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `add` operation

**Files:**
- Create: `lib/op_add.sh`, `tests/t_20_add.sh`

**Interfaces:**
- Consumes: everything from Task 2.
- Produces: `op_add_site` (no args; records one result); `add_report_existing ID`.

- [ ] **Step 1: Write the failing test**

`tests/t_20_add.sh`:

```bash
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
assert_eq "jane.doe@webfor.com" "$(fwp app_a user get jane.doe --field=user_email)" "email correct"
assert_eq '["administrator"]' "$(fwp app_a user get jane.doe --field=roles --format=json)" "role is administrator"
assert_eq "Jane Doe" "$(fwp app_a user get jane.doe --field=display_name)" "display name"
assert_eq "Jane" "$(fwp app_a user meta get "$(fwp app_a user get jane.doe --field=ID)" first_name)" "first name"
assert_eq "$admin_email_before" "$(fwp app_a user get admin --field=user_email)" "existing admin untouched"
assert_eq 0 "$(mail_count app_a)" "no email sent on create"
assert_not_contains "$OUT" "Password:" "no password printed"
assert_not_contains "$(cat "${TSV%.tsv}.log")" "Password:" "no password logged"

# --- duplicate protection ----------------------------------------------------
registered="$(fwp app_a user get jane.doe --field=user_registered)"
run_tool "${ADD[@]}" --sites app_a,app_b --execute
assert_eq "ALREADY EXISTS" "$(status_of app_a)" "second run: ALREADY EXISTS"
assert_eq "$((users_before + 1))" "$(user_count app_a)" "no duplicate created"
assert_eq "$registered" "$(fwp app_a user get jane.doe --field=user_registered)" "existing account unchanged"

# --- review focus 2: email case-insensitivity -------------------------------
run_tool add --username jane.doe --email Jane.Doe@Webfor.com --first-name Jane --last-name Doe --display-name "Jane Doe" --sites app_a --execute
assert_eq "ALREADY EXISTS" "$(status_of app_a)" "mixed-case email still the same account"

# --- conflicts are never modified --------------------------------------------
c_before="$(fp app_emailtaken)$(fp app_usertaken)"
run_tool "${ADD[@]}" --sites app_emailtaken,app_usertaken --execute
assert_eq "$c_before" "$(fp app_emailtaken)$(fp app_usertaken)" "conflict sites unchanged on a live run"
assert_eq 1 "$RC" "conflicts exit 1"

# --- role note when the existing account is not an administrator -------------
fwp app_exists user set-role jane.doe editor >/dev/null
run_tool "${ADD[@]}" --sites app_exists
assert_contains "$(detail_of app_exists)" "role: editor, expected administrator" "role mismatch noted, not changed"
assert_eq '["editor"]' "$(fwp app_exists user get jane.doe --field=roles --format=json)" "role not modified"

# --- a role that does not exist on the site ----------------------------------
run_tool add --username new.person --email new.person@webfor.com --first-name New --last-name Person --display-name "New Person" --role nosuchrole --sites app_a --execute
assert_eq FAILED "$(status_of app_a)" "unknown role -> FAILED"
assert_contains "$(detail_of app_a)" "does not exist" "unknown role reason"
```

- [ ] **Step 2: Run to verify it fails**

Run: `tests/run.sh add`
Expected: FAIL (`FAILED - operation 'add' is not implemented`).

- [ ] **Step 3: Write `lib/op_add.sh`**

```bash
#!/usr/bin/env bash
# op_add_site: create the employee on the current site unless they, or a
# conflicting account, already exist.

add_report_existing() { # ID of the account that already is the employee
  local id="$1" detail="" rc
  R_EXISTS="Yes"; R_ACTION="NONE"
  user_roles "$id" || { record_result FAILED "role lookup: $(err_reason)"; return; }
  R_ROLE="${UROLES:--}"
  marker_read "$id"; rc=$?
  if [ "$rc" -eq 2 ]; then record_result FAILED "marker lookup: $(err_reason)"; return; fi
  if [ "$rc" -eq 0 ]; then record_result "ALREADY EXISTS" "DISABLED, use restore"; return; fi
  has_role "$UROLES" "$ROLE" || detail="(role: ${UROLES:-none}, expected $ROLE)"
  record_result "ALREADY EXISTS" "$detail"
}

op_add_site() {
  local found_l id_l found_e id_e rc
  R_WP="Yes"
  lookup_user "$USERNAME" || { record_result FAILED "username lookup: $(err_reason)"; return; }
  found_l="$U_FOUND"; id_l="$U_ID"
  lookup_user "$EMAIL" || { record_result FAILED "email lookup: $(err_reason)"; return; }
  found_e="$U_FOUND"; id_e="$U_ID"

  if [ "$found_l" -eq 1 ] && [ "$found_e" -eq 1 ] && [ "$id_l" = "$id_e" ]; then
    add_report_existing "$id_l"; return
  fi
  if [ "$found_l" -eq 1 ] && [ "$found_e" -eq 0 ]; then
    # An account this tool disabled has its email swapped; recognise it by its marker.
    marker_read "$id_l"; rc=$?
    if [ "$rc" -eq 0 ] && [ "$(lower "$MK_EMAIL")" = "$(lower "$EMAIL")" ]; then
      add_report_existing "$id_l"; return
    fi
    R_EXISTS="Yes (other email)"; R_ACTION="NONE"
    record_result "USERNAME CONFLICT" "username exists on user #$id_l with a different email"
    return
  fi
  if [ "$found_e" -eq 1 ]; then
    R_EXISTS="Email taken"; R_ACTION="NONE"
    if [ "$found_l" -eq 1 ]; then
      record_result "EMAIL CONFLICT" "email on user #$id_e; username on user #$id_l"
    else
      record_result "EMAIL CONFLICT" "email on user #$id_e"
    fi
    return
  fi

  R_EXISTS="No"
  if ! wpx_try role exists "$ROLE"; then
    record_result FAILED "role '$ROLE' does not exist on this site"; return
  fi
  R_ACTION="CREATE"
  if [ "$EXECUTE" -ne 1 ]; then record_result "WOULD CREATE" ""; return; fi

  local args=(user create "$USERNAME" "$EMAIL" --role="$ROLE" --first_name="$FIRST_NAME"
              --last_name="$LAST_NAME" --display_name="$DISPLAY_NAME" --porcelain)
  [ "$SEND_EMAIL" -eq 1 ] && args+=(--send-email)
  if wpx_try "${args[@]}"; then
    # WP_OUT is the numeric id with --porcelain. Never echo it unless it is purely digits.
    case "$WP_OUT" in ''|*[!0-9]*) record_result CREATED "" ;; *) record_result CREATED "user #$WP_OUT" ;; esac
  else
    record_result FAILED "$(err_reason)"
  fi
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `tests/run.sh add`
Expected: `0 failed`. (Also run `tests/run.sh` with no argument once to confirm Tasks 1-2 still pass; expected `0 failed`.)

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add operation with conflict and duplicate protection" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `disable` operation

**Files:**
- Create: `lib/op_disable.sh`, `tests/t_30_disable.sh`
- Modify: `tests/lib/fixtures.sh` (append `prep_jane`)

**Interfaces:**
- Consumes: `marker_read/marker_write`, `try_step`, `wpx_nostdout`, `user_roles`, `lookup_user`, `user_field`, `has_role`, `err_reason`, `record_result`, globals `UROLES`, `MK_*`.
- Produces: `op_disable_site`; `disable_steps ID RESUME ORIG_EMAIL`; `app_passwords_delete_all ID`; `remove_all_roles ID`.
- Test helper produced: `prep_jane` (resets fixtures; creates jane.doe on `app_a` and `app_b` via the tool; sets known password `known-pass-1`; creates a published post authored by him; one application password in `APP_PW_<app>`; one session; gives him an extra `editor` role on `app_b`; stores his ids in `LID_app_a` / `LID_app_b`).

- [ ] **Step 1: Append `prep_jane` to `tests/lib/fixtures.sh`**

```bash
prep_jane() {
  local a id
  fixtures_reset
  run_tool "${ADD[@]}" --sites app_a,app_b --execute
  for a in app_a app_b; do
    id="$(fwp "$a" user get jane.doe --field=ID)"
    printf -v "LID_$a" '%s' "$id"
    fwp "$a" user update "$id" --user_pass=known-pass-1 >/dev/null   # sandbox-only test value
    fwp "$a" post create --post_author="$id" --post_title="Jane post" --post_status=publish --porcelain >/dev/null
    printf -v "APP_PW_$a" '%s' "$(fwp "$a" user application-password create "$id" probe --porcelain)"
    fwp "$a" eval "WP_Session_Tokens::get_instance( $id )->create( time() + 3600 );"
  done
  fwp app_b user add-role "$LID_app_b" editor >/dev/null
}
```

- [ ] **Step 2: Write the failing test**

`tests/t_30_disable.sh`:

```bash
prep_jane
assert_eq yes "$(auth_ok app_a jane.doe known-pass-1)" "precondition: password works"
assert_eq yes "$(app_pw_ok app_a jane.doe "$APP_PW_app_a")" "precondition: app password works"

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
  assert_eq no "$(auth_ok "$a" jane.doe known-pass-1)" "$a: old password rejected"
  assert_eq no "$(app_pw_ok "$a" jane.doe "$pw")" "$a: application password revoked"
  assert_eq '[]' "$(fwp "$a" user session list "$id" --format=json)" "$a: sessions destroyed"
  assert_eq '[]' "$(fwp "$a" user get "$id" --field=roles --format=json)" "$a: no roles"
  assert_eq "" "$(fwp "$a" user list-caps "$id")" "$a: no capabilities"
  assert_eq "disabled+$id@webfor.invalid" "$(fwp "$a" user get "$id" --field=user_email)" "$a: email neutralised"
  assert_eq "$id" "$(fwp "$a" user get jane.doe --field=ID)" "$a: user record kept"
  assert_eq 1 "$(fwp "$a" post list --post_author="$id" --post_status=any --format=count)" "$a: authored content kept"
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
prep_jane
run_tool disable --username jane.doe --email JANE.DOE@WEBFOR.COM --sites app_a --execute
assert_eq DISABLED "$(status_of app_a)" "mixed-case --email still matches the account"

# --- email mismatch on an already-disabled account is refused -------------------
run_tool disable --username jane.doe --email other.person@webfor.com --sites app_a --execute
assert_eq "EMAIL MISMATCH" "$(status_of app_a)" "disable with the wrong email is refused"
```

- [ ] **Step 3: Run to verify it fails**

Run: `tests/run.sh disable`
Expected: FAIL (`operation 'disable' is not implemented`).

- [ ] **Step 4: Write `lib/op_disable.sh`**

```bash
#!/usr/bin/env bash
# op_disable_site: revoke the employee's access on the current site without
# deleting anything. Reversible with op_restore_site via the marker usermeta.

app_passwords_delete_all() { # ID. rc 0 also when none exist or the feature is unavailable.
  wpx_nostdout user application-password delete "$1" --all && return 0
  case "$WP_ERR" in
    *"not available"*|*"not a registered"*)
      R_WARN="${R_WARN:+$R_WARN; }application passwords unavailable on this site"; return 0 ;;
    *"No application passwords"*|*"no application passwords"*) return 0 ;;
  esac
  return 1
}

remove_all_roles() { # ID
  local id="$1" r
  user_roles "$id" || return 1
  for r in ${UROLES//,/ }; do
    wpx_nostdout user remove-role "$id" "$r" || return 1
  done
  wpx_try user list-caps "$id" || return 1
  [ -z "$WP_OUT" ] || R_WARN="${R_WARN:+$R_WARN; }user still has direct capabilities"
  return 0
}

disable_steps() { # ID RESUME ORIG_EMAIL
  local id="$1" resume="$2" orig_email="$3"
  if [ "$resume" -eq 0 ]; then
    MK_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    MK_SERVER="$(printf '%s' "$SERVER_NAME" | tr -c 'A-Za-z0-9._-' '_')"
    MK_ROLES="$UROLES"; MK_EMAIL="$orig_email"
    if ! marker_write "$id" in_progress; then
      record_result FAILED "marker not written, nothing changed: $(err_reason)"; return
    fi
  fi
  try_step 2 "password"             wpx_nostdout user reset-password "$id" --skip-email
  try_step 3 "sessions"             wpx_nostdout user session destroy "$id" --all
  try_step 4 "application passwords" app_passwords_delete_all "$id"
  try_step 5 "roles"                remove_all_roles "$id"
  try_step 6 "email"                wpx_nostdout user update "$id" --user_email="disabled+${id}@webfor.invalid"
  if [ -n "$step_fail" ]; then
    record_result FAILED "PARTIAL (completed: 1${step_ok:+,$step_ok}; failed: $step_fail); re-run disable to resume"
    return
  fi
  if ! marker_write "$id" complete; then
    record_result FAILED "access removed but marker not finalised: $(err_reason)"; return
  fi
  record_result DISABLED "roles removed: ${MK_ROLES:-none}; email neutralised"
}

op_disable_site() {
  local id rc resume=0 orig_email="" r n_admins
  R_WP="Yes"
  lookup_user "$USERNAME" || { record_result FAILED "user lookup: $(err_reason)"; return; }
  if [ "$U_FOUND" -ne 1 ]; then R_EXISTS="No"; R_ACTION="NONE"; record_result "NOT FOUND" ""; return; fi
  id="$U_ID"; R_EXISTS="Yes"
  user_roles "$id" || { record_result FAILED "role lookup: $(err_reason)"; return; }
  R_ROLE="${UROLES:--}"

  marker_read "$id"; rc=$?
  if [ "$rc" -eq 2 ]; then record_result FAILED "marker lookup: $(err_reason)"; return; fi
  if [ "$rc" -eq 0 ]; then
    if [ "$(lower "$MK_EMAIL")" != "$(lower "$EMAIL")" ]; then
      R_ACTION="NONE"; record_result "EMAIL MISMATCH" "stored email differs from --email"; return
    fi
    if [ "$MK_STATE" = "complete" ]; then R_ACTION="NONE"; record_result "ALREADY DISABLED" ""; return; fi
    resume=1
  else
    user_field "$id" user_email || { record_result FAILED "email lookup: $(err_reason)"; return; }
    orig_email="$UF"
    if [ "$(lower "$orig_email")" != "$(lower "$EMAIL")" ]; then
      R_ACTION="NONE"; record_result "EMAIL MISMATCH" "username exists with a different email"; return
    fi
    for r in ${UROLES//,/ }; do
      valid_slug "$r" || { R_ACTION="NONE"; record_result FAILED "unusual role name '$r'; handle manually"; return; }
    done
    if has_role "$UROLES" administrator; then
      wpx_try user list --role=administrator --field=ID || { record_result FAILED "administrator count: $(err_reason)"; return; }
      n_admins="$(printf '%s\n' "$WP_OUT" | grep -c .)"
      if [ "$n_admins" -le 1 ]; then
        R_ACTION="NONE"; record_result "LAST ADMIN" "only administrator on this site"; return
      fi
    fi
  fi

  R_ACTION="DISABLE"; [ "$resume" -eq 1 ] && R_ACTION="DISABLE (resume)"
  if [ "$EXECUTE" -ne 1 ]; then record_result "WOULD DISABLE" "roles: ${UROLES:-none}"; return; fi
  disable_steps "$id" "$resume" "$orig_email"
}
```

- [ ] **Step 5: Run to verify it passes**

Run: `tests/run.sh disable`
Expected: `0 failed`. If the `list-caps` or `session list` assertions fail, check the probe file's recorded behaviour and fix `remove_all_roles` accordingly.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: disable operation with guards, marker, and resumable steps" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: `restore` operation

**Files:**
- Create: `lib/op_restore.sh`, `tests/t_40_restore.sh`

**Interfaces:**
- Consumes: `marker_read`, `try_step`, `wpx_nostdout`, `lookup_user`, `valid_slug`, `record_result`, `MK_*`; test helper `prep_jane` (Task 4).
- Produces: `op_restore_site`; `restore_roles ID`.

- [ ] **Step 1: Write the failing test**

`tests/t_40_restore.sh`:

```bash
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
  assert_eq 1 "$(fwp "$a" post list --post_author="$id" --post_status=any --format=count)" "$a: content intact"
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `tests/run.sh restore`
Expected: FAIL (`operation 'restore' is not implemented`).

- [ ] **Step 3: Write `lib/op_restore.sh`**

```bash
#!/usr/bin/env bash
# op_restore_site: reverse a disable made by this tool, using the marker usermeta.
# The password stays scrambled; the employee sets a new one via "Lost your password?".

restore_roles() { # ID. Re-adds every stored role.
  local id="$1" r
  for r in ${MK_ROLES//,/ }; do
    if ! valid_slug "$r"; then WP_ERR="Error: unusual stored role '$r'"; WP_RC=1; return 1; fi
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
  lookup_user "$MK_EMAIL" || { record_result FAILED "email lookup: $(err_reason)"; return; }
  if [ "$U_FOUND" -eq 1 ] && [ "$U_ID" != "$id" ]; then
    R_ACTION="NONE"; record_result "EMAIL CONFLICT" "original email now on user #$U_ID"; return
  fi

  R_ACTION="RESTORE"
  if [ "$EXECUTE" -ne 1 ]; then record_result "WOULD RESTORE" "roles: ${MK_ROLES:-none}"; return; fi

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
```

- [ ] **Step 4: Run to verify it passes**

Run: `tests/run.sh restore`
Expected: `0 failed`. Then run `tests/run.sh` (everything); expected `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: restore operation" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Safety hardening tests (isolation, resume, timeout, secrets, no-delete)

**Files:**
- Create: `tests/lib/wp-shim.sh`, `tests/t_50_safety.sh`
- Modify: whichever `lib/` file a failing test points at (expected: none)

**Interfaces:**
- Consumes: `WP_BIN` and `WP_TIMEOUT` environment variables honoured by `lib/wp.sh`; `prep_jane`.
- Produces: `tests/lib/wp-shim.sh`, a WP-CLI test double controlled by `SHIM_FAIL` (a word that, when it appears in the arguments, makes the call fail with `Error: injected failure`) and `SHIM_SLEEP` (seconds to hang before running).

- [ ] **Step 1: Write the shim**

`tests/lib/wp-shim.sh`:

```bash
#!/usr/bin/env bash
# Test double for WP-CLI: injects failures or hangs, otherwise passes through.
if [ -n "${SHIM_SLEEP:-}" ]; then sleep "$SHIM_SLEEP"; fi
if [ -n "${SHIM_FAIL:-}" ]; then
  case " $* " in
    *" $SHIM_FAIL "*) echo "Error: injected failure for $SHIM_FAIL" >&2; exit 1 ;;
  esac
fi
exec wp "$@"
```

```bash
chmod +x tests/lib/wp-shim.sh
```

- [ ] **Step 2: Write the tests**

`tests/t_50_safety.sh`:

```bash
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
prep_jane
run_tool "${DIS[@]}" --sites app_a --execute
logs_text="$OUT$(cat "$LOGS"/*.log "$LOGS"/*.tsv)"
assert_not_contains "$logs_text" "known-pass-1" "known password never appears in output or logs"
assert_not_contains "$logs_text" "$APP_PW_app_a" "application password never appears in output or logs"
assert_not_contains "$logs_text" "Password:" "no 'Password:' line in output or logs"

# --- log content ------------------------------------------------------------------------------
LOGF="${TSV%.tsv}.log"
assert_contains "$(cat "$LOGF")" "EXECUTE: disable jane.doe <jane.doe@webfor.com> server=testsrv" "log header: mode, op, user, email, server"
assert_contains "$(cat "$LOGF")" "RESULT app_a: DISABLED" "log has the per-site result"
assert_contains "$(cat "$LOGF")" "Applications processed: 1" "log has totals"

# --- partial failure continues, then resume completes it ------------------------------
prep_jane
WP_BIN="$SHIM" SHIM_FAIL=application-password run_tool "${DIS[@]}" --sites app_a --execute
assert_eq FAILED "$(status_of app_a)" "step failure -> FAILED"
assert_contains "$(detail_of app_a)" "PARTIAL" "reported as PARTIAL"
assert_contains "$(detail_of app_a)" "4 (application passwords)" "names the failed step"
assert_contains "$(detail_of app_a)" "completed: 1,2,3,5,6" "later steps still ran"
assert_contains "$(fwp app_a user meta get "$LID_app_a" webfor_disabled --format=json)" '"state":"in_progress"' "marker left in_progress"
assert_eq no "$(auth_ok app_a jane.doe known-pass-1)" "password already scrambled despite the failure"
assert_eq '[]' "$(fwp app_a user get "$LID_app_a" --field=roles --format=json)" "roles already removed"
run_tool "${DIS[@]}" --sites app_a --execute
assert_eq DISABLED "$(status_of app_a)" "re-run resumes and finishes"
assert_contains "$(fwp app_a user meta get "$LID_app_a" webfor_disabled --format=json)" '"state":"complete"' "marker complete after resume"
assert_contains "$(fwp app_a user meta get "$LID_app_a" webfor_disabled --format=json)" '"roles":["administrator"]' "resume kept the original roles"
run_tool "${RST[@]}" --sites app_a --execute
assert_eq RESTORED "$(status_of app_a)" "a resumed disable can be restored"
assert_eq administrator "$(roles_sorted app_a jane.doe)" "roles back after resume then restore"

# --- review focus 5: a hung WP-CLI call times out and the run continues ---------------------
fixtures_reset
WP_BIN="$SHIM" SHIM_SLEEP=5 WP_TIMEOUT=2 run_tool "${ADD[@]}" --sites app_a,app_b
assert_eq FAILED "$(status_of app_a)" "hung site -> FAILED"
assert_contains "$(detail_of app_a)" "timed out" "reason mentions the timeout"
assert_eq FAILED "$(status_of app_b)" "next site was still attempted"
```

- [ ] **Step 3: Run**

Run: `tests/run.sh safety`
Expected: `0 failed`. These tests exercise code that already exists, so they should pass on the first run. If one fails, the failure is a real defect: fix the matching `lib/` file, re-run, and keep the test.

- [ ] **Step 4: Run the whole suite**

Run: `tests/run.sh`
Expected: `0 failed` across all test files.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "test: failure isolation, resume, timeout, secrets, and no-delete checks" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Documentation and example report

**Files:**
- Create: `tests/example_report.sh`, `docs/runbook.md`, `docs/limitations.md`, `docs/example-report.md` (generated), `docs/pilot-results.md`

**Interfaces:**
- Consumes: the finished tool and fixtures.
- Produces: the deliverables listed in the spec (items 2, 3, 4, 5, 6, 7, and the template for 8 and 9).

- [ ] **Step 1: Write the example-report generator**

`tests/example_report.sh` (runs in the container; emits Markdown on stdout, build noise goes to stderr):

```bash
#!/usr/bin/env bash
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/tests/lib/assert.sh"
. "$ROOT/tests/lib/fixtures.sh"
fixtures_build
fixtures_reset

block() { # title, then run the tool and print its output in a fence
  local title="$1"; shift
  run_tool "$@"
  printf '### %s\n\n```text\n%s\n```\n\n' "$title" "$(printf '%s\n' "$OUT" | grep -v '^\[' )"
}

echo "# Example output"
echo
echo "Generated from the Docker sandbox by \`tests/example_report.sh\`. Site names are fixtures."
echo
block "1. Add: dry run on every application" "${ADD[@]}" --all
block "2. Add: create on two sites" "${ADD[@]}" --sites app_a,app_b --execute
block "3. Add again: duplicate protection" "${ADD[@]}" --sites app_a,app_b --execute
block "4. Disable: dry run" "${DIS[@]}" --all
block "5. Disable: live on the two sites" "${DIS[@]}" --sites app_a,app_b --execute
block "6. Restore: live" "${RST[@]}" --sites app_a,app_b --execute
```

```bash
chmod +x tests/example_report.sh
docker compose -f tests/docker/compose.yml run --rm -T --build runner bash tests/example_report.sh > docs/example-report.md
docker compose -f tests/docker/compose.yml down >/dev/null 2>&1
```

Expected: `docs/example-report.md` contains six fenced blocks, each with a result table and totals. Open it and confirm there is no `Password:` text and no build noise.

- [ ] **Step 2: Write `docs/runbook.md`**

```markdown
# Runbook: webfor-wp-users

Adds, disables, or restores one Webfor employee across the WordPress
applications on a Cloudways server. **Run on the server over SSH as the master
user.** Nothing is installed on client sites.

## Install

```bash
scp -r bin lib <you>@<server>:~/webfor-wp-users/
ssh <you>@<server>
chmod +x ~/webfor-wp-users/bin/webfor-wp-users
```

Check WP-CLI works: `wp --info`.

## The two rules

1. **Dry run is the default.** Nothing changes unless you add `--execute`.
2. **Always dry-run first, read the table, then re-run the same command with
   `--execute`.** For pilots, always use `--sites`, never `--all`.

## Add an employee

```bash
cd ~/webfor-wp-users
bin/webfor-wp-users add --username jane.doe --email jane.doe@webfor.com \
  --first-name Jane --last-name Doe --display-name "Jane Doe" \
  --sites <app-folder-1>,<app-folder-2>             # dry run
bin/webfor-wp-users add ... --sites <app-folder-1>,<app-folder-2> --execute
```

Find an application's folder name with `ls /home/master/applications`.

Results: `CREATED`, `ALREADY EXISTS` (nothing changed), `EMAIL CONFLICT` and
`USERNAME CONFLICT` (another account is in the way; review by hand),
`SKIPPED` (not WordPress, multisite, or no `public_html`), `FAILED` (reason
shown).

### Password behaviour

No password is passed. WordPress generates one that nobody sees (the tool
discards it) and no email is sent. The employee sets their own with **Lost
your password?** on each site's login page, which emails a reset link to
their address. That requires the site's outbound email to work. `--send-email`
makes WordPress send its standard new-user email instead.

The tool never configures 2FA. Verify transactional email, then set up 2FA per
the Webfor onboarding standard.

## Disable an employee (offboarding)

```bash
bin/webfor-wp-users disable --username jane.doe --email jane.doe@webfor.com --all      # dry run
bin/webfor-wp-users disable --username jane.doe --email jane.doe@webfor.com --all --execute
```

`--all --execute` asks you to type `ALL`. Per application, in order:

1. Saves the original roles and email in user meta `webfor_disabled`.
2. Replaces the password with a random one nobody knows.
3. Destroys every session.
4. Deletes the user's application passwords (REST API logins).
5. Removes all roles.
6. Changes the email to `disabled+<ID>@webfor.invalid` so "Lost your password?"
   goes nowhere.
7. Marks the meta `complete`.

The user record, ID, username, posts, orders, and comments stay. Nothing is
deleted. Account deletion stays a separate manual process.

Safety guards: the account must match both `--username` and `--email`
(otherwise `EMAIL MISMATCH`); the only administrator on a site is never
disabled (`LAST ADMIN`); `--email` must be `@webfor.com`.

If a run reports `FAILED - PARTIAL`, access may be partly removed. Fix the
reported cause and **re-run the same command**: it resumes safely.

## Restore an employee

```bash
bin/webfor-wp-users restore --username jane.doe --email jane.doe@webfor.com --sites <apps>            # dry run
bin/webfor-wp-users restore --username jane.doe --email jane.doe@webfor.com --sites <apps> --execute
```

Puts back the original email and every original role, then removes the
marker. The password stays unusable, so the employee must use **Lost your
password?** again. Restore refuses accounts without the marker
(`NOT DISABLED`) and never guesses roles.

## Reading results

Each run prints a table, totals, and a "Needs manual review" list, and writes
`logs/<timestamp>_<server>_<op>.log` and a `.tsv` (mode 600, no credentials).
Exit code 0 = nothing needs attention; 1 = something `FAILED` or needs
review; 2 = bad arguments.

## Options

`--exclude a,b` skips folders. `--apps-root`, `--log-dir`, `--server`,
`--allowed-domain` change defaults. `WP_TIMEOUT=120` (seconds per WP-CLI call)
and `WP_BIN=wp` are environment variables.
```

- [ ] **Step 3: Write `docs/limitations.md`**

```markdown
# Limitations and edge cases

- **Login plugins.** SSO, magic-link, or social-login plugins on a site may
  admit a disabled account by other means. The tool cannot see them (it runs
  with plugins skipped). A must-use plugin that blocks login outright would
  close this and is out of scope for v1.
- **Other credentials.** SSH, SFTP, database, hosting-panel, and third-party
  accounts are separate offboarding steps.
- **Multisite** installs are skipped and reported. Handle manually.
- **Plugins are skipped during runs** (`--skip-plugins`). Plugin hooks that
  normally react to user creation (CRM sync, audit logs, welcome emails) do
  not fire. Must-use plugins still load.
- **The swapped email** changes what admin screens and Gravatar show for the
  disabled user. It is reversible.
- **Email lookup fallback.** `wp user get <email>` falls back to a login equal
  to that string. A user whose *login* equals the employee's email is treated
  as holding the email (reported as a conflict, never modified).
- **Direct capabilities.** A user with capabilities granted directly (not via
  roles) keeps them after role removal. The report warns when this happens.
- **Application passwords** need WordPress 5.6+. On older sites the report
  warns that the step was unavailable.
- **Only accounts this tool disabled** can be restored by it.
- **Username rules.** Usernames must match `[a-z0-9._-]+` and not be all
  digits.
- **Time.** About 4 to 12 WP-CLI loads per site. A hung call times out after
  `WP_TIMEOUT` seconds (default 120) and the site is reported `FAILED`.
- **Not tested in a browser.** The sandbox verifies authentication, sessions,
  capabilities, and application passwords through WordPress itself, not an
  HTTP request to `/wp-admin`. The pilot covers that.
```

- [ ] **Step 4: Write `docs/pilot-results.md`**

The blanks are intentional: they are filled in by whoever runs the pilot, then a second person reviews the file before any wider use.

```markdown
# Pilot results

Run by: ______  Date: ______  Tool version (git commit): ______
Sites used (2-3, Webfor-managed): ______

## Test 1: Add
- [ ] Dry run reviewed. Output saved at: ______
- [ ] Live run on only the pilot sites. Log: ______
- [ ] Jane Doe exists on each site
- [ ] Email is jane.doe@webfor.com
- [ ] Role is Administrator
- [ ] No other users changed; content unaffected
- Password workflow: "Lost your password?" email arrived? ___ Link worked? ___
  Site outbound email working? ___ Notes: ______

## Test 2: Duplicate protection
- [ ] Re-run reported ALREADY EXISTS for every site; nothing changed

## Test 3: Disable
- [ ] Dry run reviewed, then live
- [ ] Existing sessions ended (tested with a logged-in browser: ___)
- [ ] Cannot log in; cannot reach /wp-admin
- [ ] Administrator privileges gone
- [ ] User record remains; authored content intact
- [ ] No other users affected
- [ ] "Lost your password?" for the old login does not deliver mail to Jane

## Test 4: Restore
- [ ] Role and email restored
- [ ] Old password still rejected
- [ ] Reset flow sets a new password and login works

## Problems found
______

## Recommendation (to be written after the pilot)
Safe to use across an entire Cloudways server? ______
Conditions before wider use: ______
Reviewed by: ______  Date: ______
```

- [ ] **Step 5: Final full run and commit**

Run: `tests/run.sh`
Expected: `0 failed`.

```bash
git add -A
git commit -m "docs: runbook, limitations, example report, and pilot results template" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Self-review

**Spec coverage**

- §2 constraints: no delete (Task 6 grep test); dry-run default (Tasks 2-5 fingerprint tests); check before create (Task 3); failure isolation (Task 6); no client changes (Tasks 3-5 conflict/guard tests); WordPress verified before WP-CLI mutation (Task 2 `validate_site`); no secrets (Tasks 3, 6); no plugin/2FA changes (nothing in the code touches plugins); pilot gating (Task 7 template, runbook rule 2).
- §3 execution model: wpx flags and `</dev/null` (Task 2), folder-name validation (Task 2).
- §4 CLI: all flags, exit codes, domain guard, `--all` confirmation (Tasks 2, 6).
- §5 discovery: Task 2 (`validate_site`), including multisite and siteurl label.
- §6 add statuses: Task 3, including disabled recognition via marker.
- §7 disable: guards, steps 1-7, resume, partial reporting: Tasks 4, 6.
- §8 restore: Task 5.
- §9 output and logs: Tasks 2, 6 (`record_result`, `print_report`, mode 600, log content).
- §10 testing: fixtures cover every listed row; probe covers the "verify before relying" list (Task 1).
- §11 pilot procedure: documented in the runbook and `pilot-results.md` (Task 7); execution is outside this plan (needs access to the pilot server).
- §12 deliverables 1-7: Tasks 2-7. Deliverables 8-9: template only, intentionally.

**Deliberate refinements of the spec** (all consistent with it): the tool continues past a failed disable step and lists every failure; the "Totals" block is generated per status rather than a fixed list; `--sites` unknown folder yields a `SKIPPED` row.

**Placeholder scan:** none, apart from the intentional blanks in `docs/pilot-results.md`.

**Type consistency:** `try_step`, `step_ok`, `step_fail`, `MK_*`, `UROLES`, `U_FOUND/U_ID`, `UF`, `R_*`, `record_result`, `marker_read/marker_write`, `wpx_try/wpx_nostdout` are used with the same signatures across Tasks 2-5. TSV column order (label, folder, wp, exists, role, action, status, detail, warnings) matches `status_of` (col 7), `detail_of` (col 8), `warn_of` (col 9).

**Known fragilities, handled by the plan:** WP-CLI output assumptions (Task 1 probe pins them; parsing is isolated in `lib/wp.sh`); MariaDB client SSL (note in Task 1 Step 5); application-password availability needs `WP_ENVIRONMENT_TYPE=local` (compose file).
