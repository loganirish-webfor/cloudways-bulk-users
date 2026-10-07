# Runbook: webfor-wp-users

Adds, disables, or restores one Webfor employee across the WordPress
applications on a Cloudways server. **Run it on the server over SSH as the
master user.** Nothing is installed on client sites. The tool never deletes a
WordPress user or any content.

Read `docs/limitations.md` before the first live run, and use
`docs/pilot-results.md` to record the Server 3 pilot.

## Install

The `bin` and `lib` folders must stay side by side.

```bash
ssh <you>@<server> 'mkdir -p ~/webfor-wp-users'
scp -r bin lib <you>@<server>:~/webfor-wp-users/
ssh <you>@<server>
chmod +x ~/webfor-wp-users/bin/webfor-wp-users
```

Check WP-CLI works for your user: `wp --info`. The tool calls `wp` from your
`PATH` (set `WP_BIN=/path/to/wp` to use another binary). It was tested with
bash 5.3, WP-CLI 2.12.0 and WordPress 7.1.3 in the Docker sandbox, not on a
Cloudways server (see the Server 3 pilot).

Print the built-in help at any time: `bin/webfor-wp-users --help`.

## The two rules

1. **Dry run is the default.** Nothing changes unless you add `--execute`.
2. **Always dry-run first, read the table, then re-run the same command with
   `--execute`.** For the pilot, always use `--sites`, never `--all`. Do not run
   across a whole server until Jason has approved the pilot results.

A dry run still starts WP-CLI on each site (it only runs read commands) and
still writes a log file. The tool writes nothing to any WordPress database in a
dry run; the sandbox suite checks this by comparing database fingerprints before
and after.

## Choosing applications

Every command needs exactly one of:

| Option | Meaning |
|---|---|
| `--sites a,b,c` | Application folder names under `/home/master/applications`. Find them with `ls /home/master/applications`. Site URLs are not accepted. |
| `--all` | Every folder under the applications root. With `--execute` the tool stops and asks you to type `ALL`; anything else aborts with exit code 2 and no change. |
| `--exclude a,b` | Optional, with either form: skip these folders. |

An unknown folder in `--sites` is reported as `SKIPPED - no such application
folder`. Sites are processed one after another; one site failing never stops
the run.

Before touching a site the tool checks that the folder has a `public_html`,
that WordPress is installed there, and that it is not multisite. Anything else
is reported (see Reading results) and left alone.

## Add an employee

```bash
cd ~/webfor-wp-users
bin/webfor-wp-users add --username logan.irish --email logan.irish@webfor.com \
  --first-name Logan --last-name Irish --display-name "Logan Irish" \
  --sites <app-folder-1>,<app-folder-2>                # dry run
bin/webfor-wp-users add --username logan.irish --email logan.irish@webfor.com \
  --first-name Logan --last-name Irish --display-name "Logan Irish" \
  --sites <app-folder-1>,<app-folder-2> --execute      # live
```

`--role` defaults to `administrator`. Another role is accepted only if the site
has it, and roles that a plugin registers (for example `shop_manager`) are not
visible to the tool, so it reports `FAILED - role '...' does not exist on this
site` for them (see limitations).

Per site the tool looks the account up by username and by email first:

| Result | Meaning |
|---|---|
| `WOULD CREATE` | Dry run only. The account would be created. |
| `CREATED - user #N` | Account created with the role, names and display name given. |
| `ALREADY EXISTS` | The username and email already belong to the same account. Nothing changed. The detail shows `(role: X, expected administrator)` if the role differs, or `DISABLED, use restore` if this tool disabled it. |
| `EMAIL CONFLICT` | Another account holds the email. Review by hand. |
| `USERNAME CONFLICT` | The username exists with a different email. Review by hand. |

### Password behaviour

No password is passed. WordPress generates one that nobody sees (the tool
discards the output) and **no email is sent**. The employee sets their own
password with **Lost your password?** on each site's login page, which emails a
reset link to their address. That needs the site's outbound email to work, so
check it during the pilot.

`--send-email` makes WordPress send its standard new-user mails instead. WordPress
sends **two**: a "New User Registration" notice to the site's admin email address
and a "Login Details" mail to the employee. The admin notice goes to the client's
admin address, so avoid `--send-email` on client sites unless that is acceptable.

The tool never configures 2FA or touches plugins. Once the employee can log in,
set up 2FA per the Webfor onboarding standard.

## Disable an employee (offboarding)

```bash
bin/webfor-wp-users disable --username logan.irish --email logan.irish@webfor.com --all             # dry run
bin/webfor-wp-users disable --username logan.irish --email logan.irish@webfor.com --all --execute   # asks you to type ALL
```

With `--sites` instead of `--all` there is no prompt. Per application, in this
order (the step numbers appear in `PARTIAL` failure messages):

1. Saves the original roles and email in user meta `webfor_disabled`, marked
   `in_progress`. If this fails, nothing else is changed.
2. Replaces the password with a random one nobody knows (no email is sent).
3. Destroys every session.
4. Deletes the user's application passwords (these log in to the REST API
   without the account password).
5. Removes all roles.
6. Changes the email to `disabled+<ID>@webfor.invalid` (`<ID>` is the user ID on
   that site), so "Lost your password?" for that account goes nowhere. WordPress's
   "Email Changed" notice to the old address is switched off for the tool's calls,
   so the employee's real mailbox receives nothing.
7. Marks the meta `complete`.

The user record, ID, username, posts, orders and comments stay. Nothing is
deleted. Account deletion is a separate manual process.

| Result | Meaning |
|---|---|
| `WOULD DISABLE` | Dry run only. |
| `DISABLED` | All steps succeeded. |
| `ALREADY DISABLED` | Marker says complete. Nothing changed. |
| `NOT FOUND` | No account with that username. Nothing changed. |
| `EMAIL MISMATCH` | The account has that username but another email (or the stored original email differs from `--email`). Not touched. |
| `LAST ADMIN` | The account is the only user with the administrator role on the site. Not touched. |
| `FAILED - unusual role name '...'; handle manually` | A stored role name contains unexpected characters. Nothing is changed. |
| `FAILED - PARTIAL (completed: 1,2,3; failed: 4 (...): reason); re-run disable to resume` | Access may be partly removed. |

The account must match both `--username` and `--email`, so a client account that
happens to share the username is never touched. `--email` must be in
`@webfor.com` for every operation unless you pass `--allowed-domain` or
`--allow-any-domain`.

If a run reports `FAILED - PARTIAL`, fix the reported cause and **re-run the same
command**: it sees the `in_progress` marker and repeats the steps (they are safe
to repeat). The `LAST ADMIN` check is skipped on a resume.

## Restore an employee

```bash
bin/webfor-wp-users restore --username logan.irish --email logan.irish@webfor.com --sites <apps>             # dry run
bin/webfor-wp-users restore --username logan.irish --email logan.irish@webfor.com --sites <apps> --execute   # live
```

Puts back the original email and every stored role, then removes the marker.
The password stays unusable, so the employee must use **Lost your password?**
again; no old credential is ever reinstated. Application passwords and sessions
that were destroyed are not recreated.

| Result | Meaning |
|---|---|
| `WOULD RESTORE` | Dry run only. |
| `RESTORED` | Done. The warning column repeats that the password stays unusable. |
| `NOT DISABLED` | No marker, so the tool does not know the roles and will not guess. Nothing changed. |
| `NOT FOUND` | No account with that username. |
| `EMAIL MISMATCH` | The stored original email differs from `--email`. |
| `EMAIL CONFLICT` | The original email now belongs to another account. Nothing changed. |
| `FAILED - unusual stored role name '...'; handle manually` | Refused before changing anything. |
| `FAILED - PARTIAL (completed: ...; failed: ...); marker kept, re-run restore` | See below. |

Restore steps run in this order: email (step 1), roles (step 2), marker removal
(step 3). If the email step fails the roles step still runs, so for a moment the
account can have its roles back with the neutralised email. The marker is kept
until every step has succeeded, so **re-run the same restore command** to finish.
Restore also works on an account whose disable stopped halfway.

In restore's report row the ROLE column shows the roles the account had *before*
the restore (normally `-`), not the restored ones. The restored roles are in the
result detail.

## Reading results

Each run prints progress lines (`[n/N] folder`, on stderr), then a table:

```
SITE | WP | USER EXISTS | ROLE | ACTION | RESULT | WARNINGS
```

followed by Totals (one line per result, plus `Applications processed`) and a
**Needs manual review** list. That list repeats every `FAILED`, `SKIPPED`,
`EMAIL CONFLICT`, `USERNAME CONFLICT`, `EMAIL MISMATCH` and `LAST ADMIN` site with
its reason. `docs/example-report.md` shows real output from the sandbox.

`SKIPPED` reasons: `no such application folder`, `no public_html`, `not
WordPress`, `WordPress files found but not installed`, `multisite, handle
manually`. A site whose database or `wp-config.php` is broken is `FAILED`, not
`SKIPPED`.

Warnings you may see:

- `user still has direct capabilities` (disable): capabilities granted to the
  user directly, not through a role, were not removed. Check the account by hand.
- `application passwords unavailable on this site` (disable): WordPress older than
  5.6 has no application passwords, so that step could not run. This is a warning,
  not a failure.
- `account had no roles when disabled` (restore).

**Exit codes**

| Code | Meaning |
|---|---|
| 0 | No site `FAILED` and none needs review. `SKIPPED` sites are listed in the review list but do not change the exit code, so read the list. |
| 1 | At least one `FAILED`, `EMAIL CONFLICT`, `USERNAME CONFLICT`, `EMAIL MISMATCH` or `LAST ADMIN`; or there were no applications to process. |
| 2 | Bad arguments, or the `ALL` confirmation was not given. |

### Logs

Every run, dry or live, writes `logs/<YYYYMMDD-HHMMSS>_<server>_<op>.log` and a
sibling `.tsv` (one row per site) in the `--log-dir` (default `./logs`, relative
to where you run the tool). Both are mode 600 and hold no credentials; they do
contain the employee's username and email and the site URLs. The report is
also copied into the log (the `[n/N]` progress lines are not).

## Options

| Option | Default | Notes |
|---|---|---|
| `--apps-root DIR` | `/home/master/applications` | |
| `--log-dir DIR` | `./logs` | |
| `--server NAME` | `hostname` | Label recorded in the log and file name. |
| `--allowed-domain D` | `webfor.com` | `--email` must be in this domain. |
| `--allow-any-domain` | off | Turns the domain guard off. Not recommended. |
| `--role R` | `administrator` | `add` only. |
| `--send-email` | off | `add` only. |

Environment variables: `WP_TIMEOUT` (seconds allowed per WP-CLI call, default
120) and `WP_BIN` (default `wp`). Where the system has no `timeout` command (for
example macOS) WP-CLI runs with no per-call limit.

## Checking the marker by hand

```bash
wp --path=/home/master/applications/<folder>/public_html --skip-plugins --skip-themes \
  user meta get <user-id> webfor_disabled --format=json
```

shows the stored time, server, original roles, original email and state
(`in_progress` or `complete`).
