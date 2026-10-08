# Webfor WP Users: bulk employee access for Cloudways WordPress sites

Status: approved 2026-10-07; amended 2026-10-08 to match the built tool
(disable also looks up the email, and the password-reset key is cleared).
Date: 2026-10-07.

## 1. Purpose

Onboard and offboard Webfor employees across every WordPress application on a
Cloudways server, using WP-CLI only. No management platform (ManageWP etc.).
Individual accounts stay in place for accountability. Nothing is ever deleted.

Three operations:

| Operation | Effect |
|---|---|
| `add` | Create the employee as an Administrator on each site, unless the account already exists. |
| `disable` | Cut the employee's access on each site immediately, without deleting the user or any content. |
| `restore` | Reverse a `disable` for an account that was disabled by this tool. |

Success means: a pilot on 2-3 sites of Server 3 behaves exactly as specified,
Jason reviews the pilot results, and only then is the tool considered for
server-wide use. This spec covers building and sandbox-testing the tool and
the pilot procedure. Running the pilot and the production-readiness
recommendation (deliverables 8 and 9) need Server 3 access and happen after
the build.

## 2. Hard constraints

1. Never delete a WordPress user or content. `wp user delete` must not appear
   in the source (enforced by a test).
2. Dry run is the default. Writes require an explicit `--execute`.
3. Check before create. Skip sites where the change is unnecessary.
4. One site failing never stops the run.
5. Never modify client users or unrelated administrators.
6. Never run WP-CLI against a directory that has not been verified as a real,
   installed, single-site WordPress.
7. Never log, print, or store passwords or other credentials.
8. Do not install, enable, or configure WP 2FA or any other plugin.
9. Do not run across a whole server until Jason approves the pilot results.

## 3. Execution model

- The tool is a bash script run **on the Cloudways server over SSH as the
  master user**, where `wp` is already installed. It is copied to the server;
  nothing is installed on client sites.
- Applications are discovered under `/home/master/applications/*/public_html`
  (overridable with `--apps-root` for testing).
- Every `wp` call uses `--path=<public_html> --skip-plugins --skip-themes`
  (a broken plugin cannot crash the run, and no plugin hook can send mail or
  alter users) and never reads from stdin.
- Each site is processed inside its own error boundary. Failures are
  recorded and the loop continues.

## 4. CLI

```
webfor-wp-users add     --username U --email E --first-name F --last-name L
                        --display-name D [--role administrator]
                        <targeting> [--execute] [--send-email]
webfor-wp-users disable --username U --email E <targeting> [--execute]
webfor-wp-users restore --username U --email E <targeting> [--execute]

targeting (exactly one required):
  --sites a,b,c     app folder names under the apps root
  --all             every discovered application; with --execute, requires
                    typing ALL at a prompt
  [--exclude a,b]   optional, applies to either form

common:
  --apps-root DIR   default /home/master/applications
  --log-dir DIR     default ./logs
  --allowed-domain  default webfor.com; the email must be in this domain
  --allow-any-domain  disable the domain guard (not recommended)
  --server NAME     label recorded in the log; default `hostname`
```

- No `--execute` means dry run, labelled `DRY RUN` on every output line group.
- `--role` for `add` defaults to `administrator`. Roles other than
  `administrator` are accepted only if they exist on the target site.
- Argument validation runs before any site is touched. The username must
  match `^[a-z0-9._-]+$`, the email must be valid and inside
  `--allowed-domain`, and the targeting form must be given.
- Exit codes: `0` all sites ended in a success or no-change status,
  `1` at least one `FAILED` or `REVIEW REQUIRED`, `2` usage error.

## 5. Site discovery and validation

For each directory under the apps root:

1. `public_html` exists and is readable, else `SKIPPED - no public_html`.
2. `wp core is-installed` succeeds, else `SKIPPED - not WordPress` (or
   `FAILED - WP-CLI error: <first line>` when WP-CLI itself errors, e.g. a bad
   `wp-config.php` or database connection, so these surface for manual review).
3. Multisite (`wp core is-installed --network` succeeds, or `is_multisite`) is
   `SKIPPED - multisite, handle manually`. Network users and super admin
   semantics are out of scope.
4. The site label is `wp option get siteurl` plus the folder name, e.g.
   `https://example.com (app: abcdefghij)`.

Discovery is read-only and is the first phase of every run, dry or live.

## 6. `add`

Per site, after validation, two read-only lookups:

- by username: `wp user get <username>`
- by email: `wp user list --search=<email> --search-columns=user_email`
  with an exact-match filter on the result

| Condition | Status | Action |
|---|---|---|
| Neither exists | `CREATED` | `wp user create` with role, names, display name; no password given |
| Username and email resolve to the same account | `ALREADY EXISTS` | none. The report notes the current role, and `(role: X, expected administrator)` if different |
| Same account, but it carries the `webfor_disabled` marker | `ALREADY EXISTS - DISABLED, use restore` | none |
| Email belongs to a different account | `EMAIL CONFLICT - REVIEW REQUIRED` | none |
| Username exists with a different email | `USERNAME CONFLICT - REVIEW REQUIRED` | none |
| `wp user create` errors | `FAILED - <reason>` | none |

Password behavior: no password is passed, so WordPress generates one that is
never displayed. No welcome email is sent unless `--send-email` is given. The
employee sets credentials with "Lost your password?" on the site, which
requires that site's outbound email to work. The pilot documents this
exactly (see section 11). Nothing is stored or logged.

## 7. `disable`

### 7.1 Guards (per site, before any write)

| Condition | Status |
|---|---|
| Username not found, and `--email` is not on any account | `NOT FOUND` (no change) |
| Username not found, but `--email` belongs to an account with a different username | `EMAIL FOUND UNDER OTHER USERNAME - REVIEW REQUIRED` (no change) |
| Username exists, email differs from `--email` | `EMAIL MISMATCH - REVIEW REQUIRED` |
| Marker already present with `state=complete` | `ALREADY DISABLED` (no change) |
| Target is the only user with the administrator role | `LAST ADMIN - REVIEW REQUIRED` |

The email guard means the tool only ever acts on the account that matches
both identifiers, never on a client account that happens to share a
username.

### 7.2 Steps

Ordered so access is cut before cosmetic changes, and so a mid-run failure
can be resumed:

1. Write usermeta `webfor_disabled` (JSON: timestamp, server, original roles,
   original email, `state=in_progress`). If this fails, stop; nothing else is
   changed.
2. Scramble the password: `wp user reset-password <id> --skip-email`
   with output discarded, then `wp_set_password()` with a second random
   password generated inside PHP. The result is a random hash nobody knows,
   and any password-reset key requested before the disable is cleared.
3. `wp user session destroy <id> --all`.
4. `wp user application-password delete <id> --all` (these authenticate to
   the REST API independently of the login password). If the site's
   WordPress predates application passwords, record a warning and continue.
5. Remove every role from the user (`wp user remove-role`). The user ends
   with no capabilities. Any capabilities granted directly to the user
   (rare) are listed in the report as a warning.
6. Replace the email with `disabled+<ID>@webfor.invalid` (reserved TLD,
   undeliverable). This closes the "Lost your password?" path: a reset
   link for the account goes nowhere. WP-CLI suppresses core's
   email-change notice; verified in the sandbox (section 10).
7. Update the marker to `state=complete`.

Final status: `DISABLED`. If any of steps 2-6 fails: `FAILED - PARTIAL
(completed: 1,2,3; failed: 4: <reason>)`. Re-running `disable` resumes: it
sees `state=in_progress` and repeats the steps idempotently.

### 7.3 What this does and does not do

Covers: login by password, existing sessions, REST access via application
passwords, password-reset takeover, administrative capability. Preserves:
the user row, ID, login name, authorship of posts and pages, WooCommerce
orders and customer records, comments.

Does not cover:
- SSO, magic-link, or social-login plugins that authenticate by other
  means. Documented limitation; a must-use plugin that hard-blocks login is
  a possible later layer and is out of scope for v1.
- Anyone who already has the employee's other credentials (hosting, SFTP,
  database). Those are separate offboarding steps.
- Multisite (skipped).

## 8. `restore`

Per site:

| Condition | Status |
|---|---|
| Username not found | `NOT FOUND` (no change) |
| No `webfor_disabled` marker | `NOT DISABLED` (no change; the tool never guesses roles) |
| Original email now belongs to another account | `EMAIL CONFLICT - REVIEW REQUIRED` |
| Otherwise | `RESTORED` |

Restore steps: put the original email back, re-add the stored roles, delete
the marker. The password remains scrambled, so the employee must use "Lost
your password?" to set a new one. No old credential is ever reinstated.
`--execute` and dry-run behave the same as the other operations.

## 9. Output

### 9.1 Console and report

For each site, one line: `<label>: <STATUS>[ - detail]`, preceded in dry-run
mode by the dry-run table fields:

```
DRY RUN: add logan.irish <logan.irish@webfor.com>  server=server3
SITE                              WP   USER EXISTS  ROLE  PROPOSED ACTION   WARNINGS
https://a.example (app: ab12)     Yes  No           -     CREATE
https://b.example (app: cd34)     Yes  Yes          admin NONE (already)
https://c.example (app: ef56)     Yes  No           -     CREATE
(app: gh78)                       No   -            -     SKIP              not WordPress
https://d.example (app: ij90)     Yes  email taken  -     REVIEW            email on user #7

Totals: CREATED 0  ALREADY EXISTS 1  REVIEW REQUIRED 1  SKIPPED 1  FAILED 0  (would create: 2)
```

Live runs print the same columns with real outcomes, then the totals block.
A final "needs manual review" list repeats every `FAILED`, `REVIEW REQUIRED`
and `SKIPPED` site with its reason.

### 9.2 Log files

Every run, dry or live, writes `<log-dir>/YYYYMMDD-HHMMSS_<server>_<op>.log`
and a sibling `.tsv` (one row per site). The log records: date/time, server,
operation, whether dry or live, username and email, each application
processed, result per application, errors, final totals. No passwords. Logs
are written with mode 600.

## 10. Testing

A Docker sandbox (WordPress + MariaDB + WP-CLI) hosts fixture applications
laid out like Cloudways (`<apps-root>/<id>/public_html`):

| Fixture | Purpose |
|---|---|
| normal x2 | `add` creates, second run `ALREADY EXISTS` |
| user already present | `ALREADY EXISTS` with role note |
| email owned by another user | `EMAIL CONFLICT` |
| username with different email | `USERNAME CONFLICT` |
| empty `public_html` | `SKIPPED - not WordPress` |
| bad DB credentials | `FAILED`, run continues |
| multisite | `SKIPPED - multisite` |
| target is the only admin | `LAST ADMIN` on disable |
| posts and an order-like CPT authored by the target | content untouched by disable and restore |

Test cases (a plain bash runner, no new dependencies):

1. Dry run of each operation leaves every database byte-identical (hash of
   `wp db export` before and after).
2. `add`, repeated `add`, `disable`, repeated `disable`, `restore`, in that
   order, with assertions after each.
3. After `disable`: login with the old password fails, an application
   password request fails, a session cookie is invalid, the user cannot reach
   `/wp-admin`, the user row and all authored content remain, other users are
   unchanged.
4. After `restore`: roles and email are back, the old password still does
   not work, and the reset-password flow sets a new one.
5. Failure isolation: a failing site does not stop the run, and totals add
   up.
6. The source contains no `wp user delete`, and no password appears in logs
   or console output.
7. A partial-failure injection at each disable step, then a resume run.

Behaviors to verify in the sandbox before relying on them: `wp user
reset-password --skip-email` produces no email and no useful stdout;
`wp user update --user_email` sends no change-notice email;
`wp user remove-role` can remove all roles; `session destroy` and
`application-password delete` behave as documented; `wp user list
--search-columns=user_email` matches exactly. Any that differ change the
steps in sections 6-8 and are recorded in the pilot notes.

## 11. Server 3 pilot procedure

Performed by someone with SSH to Server 3 (not by this build). Jason reviews
the results before any wider use.

1. Copy the tool to the server; pick 2-3 Webfor-managed test sites.
2. `add` dry run for `logan.irish`; review each proposed action.
3. `add --execute --sites <the 2-3>`. Verify manually in wp-admin: the user
   exists, email and role are correct, no other user changed, content
   unaffected.
4. Exercise the password workflow ("Lost your password?"), record exactly
   what arrives and how it behaves, and note whether the site's outbound
   email works.
5. Re-run `add`: expect `ALREADY EXISTS`, no change.
6. `disable` dry run, then `--execute`. Verify: sessions ended, no
   wp-admin access, no admin capability, user row and content intact,
   others unaffected.
7. `restore`. Verify role and email return, the old password is dead, and
   reset works.

## 12. Deliverables (mapped to the request)

1. `bin/webfor-wp-users` and `lib/` (the script).
2. Run instructions: `docs/runbook.md`.
3. Dry-run instructions: same file.
4. Example output and report: `docs/example-report.md` (generated from the
   sandbox run).
5. Disable-mechanism explanation: section 7 carried into the runbook.
6. Restore instructions: section 8 carried into the runbook.
7. Limitations and edge cases: `docs/limitations.md`, seeded from sections
   7.3 and 10.
8. Server 3 pilot results: `docs/pilot-results.md`, a template now, filled in
   after the pilot.
9. Production-readiness recommendation: written after the pilot results.

## 13. Out of scope

Multisite and network users. Deleting or reassigning users. Configuring WP
2FA or any plugin. A must-use login-block plugin. Password distribution or
storage. Server-wide rollout (waits for Jason's approval).

## 14. Open items

- Decided: the swapped `disabled+<ID>@webfor.invalid` email is included. It
  changes what admin screens and Gravatar show for that user, and the
  runbook says so.
- `--sites` accepts folder names only in v1, not site URLs.
