# Runbook: webfor-wp-users

Adds, disables, or restores one Webfor employee across the WordPress
applications on a Cloudways server. **Run it on the server over SSH as the
master user.** Nothing is installed on client sites. The tool never deletes a
WordPress user or any content.

Read `docs/limitations.md` before the first live run, and use
`docs/pilot-results.md` to record the pilot (a first trial of the tool on
2-3 Webfor-managed sites on a Cloudways server, reviewed by a second person before any
wider use).

## Install

The `bin` and `lib` folders must stay side by side.

```bash
ssh <you>@<server> 'mkdir -p ~/webfor-wp-users'
scp -r bin lib <you>@<server>:~/webfor-wp-users/
ssh <you>@<server>
chmod +x ~/webfor-wp-users/bin/webfor-wp-users
```

Check WP-CLI works for your user: `wp --info`. The tool calls `wp` from your
`PATH` (set `WP_BIN=/path/to/wp` to use another binary). It was tested in the
Docker sandbox (GNU bash 5.3.9, WP-CLI 2.12.0, WordPress 7.1.3) and in dry runs
(no changes) on two live Cloudways servers, bash 5.2.15 and WP-CLI 2.12.0, logged
in as an application user. Live `--execute` runs have not been tried on a real
server yet. Check the server with `bash --version`; other bash versions are
untested.

Print the built-in help at any time: `bin/webfor-wp-users --help`.

### If you log in as an application user (not `master`)

On two Cloudways servers the SSH login was an application user (its name is also
the folder name of one app, for example `abcdefghij`), not `master`. There:

- The home folder is not writable, so `mkdir ~/webfor-wp-users` fails.
- `scp` finished without an error but copied nothing. Plain `ssh` commands work.
- `/tmp` is writable and is not served by the website.
- `/home/master/applications` was readable, so the tool listed every app, but the
  dry runs were done only on the app the login owns. Whether the tool can read the
  other apps from that login is untested; expect `FAILED` or `SKIPPED` rows there
  and read them.

Copy the tool through `ssh` and `tar` into `/tmp` instead. On macOS the
`COPYFILE_DISABLE=1` part keeps `tar` from adding Apple metadata:

```bash
COPYFILE_DISABLE=1 tar czf - bin lib | ssh <you>@<server> 'mkdir -p /tmp/webfor-wp-users && tar xzf - -C /tmp/webfor-wp-users'
```

Run it with `bash`, so no `chmod` is needed, and keep the logs in `/tmp` too:

```bash
ssh <you>@<server> 'cd /tmp/webfor-wp-users && bash bin/webfor-wp-users add --username jane.doe --email jane.doe@webfor.com --first-name Jane --last-name Doe --display-name "Jane Doe" --sites <your-app-folder> --log-dir /tmp/webfor-wp-users/logs'
```

Copy the `logs` folder back to your computer when you finish, because `/tmp` is
cleared from time to time, then remove the tool from the server:

```bash
ssh <you>@<server> 'rm -rf /tmp/webfor-wp-users'
```

The tool runs every WP-CLI call from inside the site's folder. Cloudways'
`wp-config.php` loads `wp-salt.php` by a relative path, and WP-CLI fails with
`Failed opening required 'wp-salt.php'` when it starts anywhere else. You do not
need to do anything for this; it is built in.

## Before you start

On the server, as the user that will run the tool:

- `wp --version`. The tool relies on `wp user application-password`, on `--exec`
  with `WP_CLI::add_wp_hook` (to switch off WordPress's "Email Changed" and
  "Password Changed" notices) and on `wp core is-installed --network`. The sandbox
  used WP-CLI 2.12.0; older releases may lack these.
- `command -v timeout`. Without it WP-CLI calls have no time limit (see Options).
- `bash --version`. The sandbox ran GNU bash 5.3.9; no other version has been
  tested.
- Run the first dry run on **one** site (`--sites <one-folder>`), read the table,
  and only then widen the list.

## The two rules

1. **Dry run is the default.** Nothing changes unless you add `--execute`.
2. **Always dry-run first, read the table, then re-run the same command with
   `--execute`.** For the pilot, always use `--sites`, never `--all`. Do not run
   across a whole server until a second person has approved the pilot results.

A dry run still starts WP-CLI on each site (the tool issues only read
commands in a dry run) and still writes a log file. The test suite checks this by
comparing a fingerprint of users, usermeta, posts and options before and after.

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
bin/webfor-wp-users add --username jane.doe --email jane.doe@webfor.com \
  --first-name Jane --last-name Doe --display-name "Jane Doe" \
  --sites <app-folder-1>,<app-folder-2>                # dry run
bin/webfor-wp-users add --username jane.doe --email jane.doe@webfor.com \
  --first-name Jane --last-name Doe --display-name "Jane Doe" \
  --sites <app-folder-1>,<app-folder-2> --execute      # live
```

`--role` defaults to `administrator`. Another role is accepted only if the site
has it, and a role that a plugin registers only at runtime (not stored in the
database) is not visible to the tool, so it reports `FAILED - role '...' does not exist on this
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

No password is passed. WordPress generates one that nobody sees (the tool uses
`--porcelain`, so no password is ever printed) and **no email is sent**. The employee sets their own
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
bin/webfor-wp-users disable --username jane.doe --email jane.doe@webfor.com --sites <apps>             # dry run
bin/webfor-wp-users disable --username jane.doe --email jane.doe@webfor.com --sites <apps> --execute   # live
```

After the pilot has been approved, `--all` replaces `--sites <apps>`; with
`--execute` it asks you to type `ALL`. With `--sites` there is no prompt. Per application, in this
order (the step numbers appear in `PARTIAL` failure messages):

1. Saves the original roles and email in user meta `webfor_disabled`, marked
   `in_progress`. If this fails, nothing else is changed.
2. Replaces the password with a random one nobody knows (no email is sent): `wp
   user reset-password --skip-email` with its output discarded, then
   `wp_set_password()` with a second random password generated inside PHP (never on
   the command line or in output). `wp_set_password()` also clears the account's
   password-reset key, so a "Lost your password?" link requested before the
   disable cannot be used afterwards. In the sandbox (WordPress 7.1.3, WP-CLI
   2.12.0) `reset-password` alone already invalidated such a key; the second call
   is there in case other versions behave differently (untested).
3. Destroys every session.
4. Deletes the user's application passwords (these log in to the REST API
   without the account password).
5. Removes all roles.
6. Changes the email to `disabled+<ID>@webfor.invalid` (`<ID>` is the user ID on
   that site), so "Lost your password?" for that account goes nowhere. WordPress's
   "Email Changed" notice to the old address is switched off for the tool's calls,
   so the employee's real mailbox receives nothing.
7. Marks the meta `complete`.

The user record, ID, username, posts, orders and comments stay. No user or
content is deleted (only the application passwords, step 4). Account deletion is a separate manual process.

| Result | Meaning |
|---|---|
| `WOULD DISABLE` | Dry run only. |
| `DISABLED` | All steps succeeded. |
| `ALREADY DISABLED` | Marker says complete. Nothing changed. |
| `NOT FOUND` | No account has that username and none has that email. Nothing changed. Exit code stays 0, so if a whole run says `NOT FOUND` read the table: it may mean a wrong username. |
| `EMAIL FOUND UNDER OTHER USERNAME` | No account has that username, but a different account holds `--email` (USER EXISTS shows `Email under other login`, the detail gives the user id). Nothing changed. The person may still have access under that login: review by hand. |
| `EMAIL MISMATCH` | The account has that username but another email (or the stored original email differs from `--email`). Not touched. |
| `LAST ADMIN` | The account is the only user with the administrator role on the site. Not touched. |
| `FAILED - unusual role name '...'; handle manually` | A stored role name contains unexpected characters. Nothing is changed. |
| `FAILED - marker not written, nothing changed: reason` | Step 1 failed. The site is untouched; fix the cause and run again. |
| `FAILED - access removed but marker not finalised: reason` | Steps 2 to 6 succeeded but step 7 failed. Re-run `disable`; it resumes and finishes. |
| `FAILED - PARTIAL (completed: 1,2,3; failed: 4 (...): reason); re-run disable to resume` | Access may be partly removed. |

The account must match both `--username` and `--email`, so a client account that
happens to share the username is never touched. `--email` must be in
`@webfor.com` for every operation unless you pass `--allowed-domain` or
`--allow-any-domain`.

If a run reports `FAILED - PARTIAL`, fix the reported cause and **re-run the same
command**: it sees the `in_progress` marker and repeats the steps (they are safe
to repeat). The `LAST ADMIN` check is skipped on a resume. In the table a
resumed site shows ACTION `DISABLE (resume)`.

### Checking a disable in a browser

The disable only counts once a real browser confirms it. A few things from the
first live test will save you confusion:

- **Use two windows.** Keep your normal window logged in as the test account. Use
  a private window (Chrome "Incognito", Safari "Private", Edge "InPrivate") for the
  reset email and the saved link. In the logged-in window WordPress skips the
  "Lost your password?" page and goes straight to the dashboard.
- **Order matters.** WordPress keeps only one reset key per account, and any new
  reset request replaces it. Request a reset *before* the disable and keep that
  email. After the disable, click that saved link **first**. It should say the link
  is invalid or expired. Only then request a new reset. If you request a new one
  first, the old link is dead anyway and the test proves nothing.
- **"Check your email for the confirmation link" is not a failure.** WordPress
  shows it for every reset request, even for accounts that do not exist or cannot
  receive mail, so strangers cannot tell which accounts exist. The real check is
  whether an email arrives. For a disabled account none should, because the
  address is `disabled+<ID>@webfor.invalid`.
- **A logged-in tab shows a login box after the disable.** An already-open wp-admin
  tab shows WordPress's standard "log in again" box over the old page. That box
  gives no access. Reload the tab and you land on the login screen.
- **Mail can be late.** If a site sends mail through an SMTP plugin, an email from
  a reset requested before the disable can arrive after it. Give it ten minutes
  and look at the time on the email before you call it a failure.
- **Do not let your password manager save the test account.** Choose "Not now" when
  it offers.
- **Usernames differ between sites.** Your own account may be called `logan` on one
  site and `logan.irish` on another. The tool matches the username and the email
  together, so a different username is reported as `EMAIL CONFLICT` (for `add`) or
  `EMAIL FOUND UNDER OTHER USERNAME` (for `disable`) and nothing is changed. Use
  the username the site actually has.

## Restore an employee

```bash
bin/webfor-wp-users restore --username jane.doe --email jane.doe@webfor.com --sites <apps>             # dry run
bin/webfor-wp-users restore --username jane.doe --email jane.doe@webfor.com --sites <apps> --execute   # live
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
| `FAILED - access restored but marker not removed: ...` | Email and roles are back but the marker is still there. Re-run `restore` to finish. |

Restore steps run in this order: email (step 1), roles (step 2), marker removal
(step 3). If the email step fails the roles step still runs, so for a moment the
account can have its roles back with the neutralised email. The marker is kept
until every step has succeeded, so **re-run the same restore command** to finish.
Restore also works on an account whose disable stopped halfway.

**Restore stuck in `PARTIAL` because a stored role no longer exists** on the site
(the roles step fails every time): create the role again by hand, or fix the
role name, and re-run `restore`. As a last resort, restore the roles and email by
hand (`wp user add-role`, `wp user update --user_email=...`), then delete the
marker so the tool stops treating the account as disabled:
`wp --path=<site>/public_html --skip-plugins --skip-themes user meta delete <ID> webfor_disabled`.
Use this only after confirming by hand that the account is back to its intended state.

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
`EMAIL CONFLICT`, `USERNAME CONFLICT`, `EMAIL MISMATCH`, `LAST ADMIN` and
`EMAIL FOUND UNDER OTHER USERNAME` site with
its reason. `docs/example-report.md` shows real output from the sandbox.

`SKIPPED` reasons: `no such application folder`, `no public_html`, `not
WordPress`, `WordPress files found but not installed`, `multisite, handle
manually`. A site whose database or `wp-config.php` is broken is `FAILED`, not
`SKIPPED`. The WP column reads `No` whenever WordPress could not be confirmed,
which includes a real WordPress site whose database is down (that row is `FAILED`).

**Read the WARNINGS column on every row.** Warnings do not change the exit code
and do not put a site in the review list: a site with a warning is still reported
`DISABLED` (or `RESTORED`) and the run can exit 0.

Warnings you may see:

- `user still has direct capabilities` (disable): capabilities granted to the
  user directly, not through a role, were not removed. Check the account by hand.
- `application passwords unavailable on this site` (disable): WordPress reported
  application passwords as unavailable, either because the site is older than 5.6
  or because the feature is turned off for the site ("Application passwords are
  not available for this site"). The step is treated as a warning, not a failure,
  but **the user's application passwords were NOT deleted**. Check the user's
  profile (or `wp user application-password list <id>`) by hand and revoke them.
- `account had no roles when disabled` (restore).

**Exit codes**

| Code | Meaning |
|---|---|
| 0 | No site `FAILED` and none needs review. `SKIPPED` sites are listed in the review list but do not change the exit code, and warnings affect neither, so read the list and the WARNINGS column. |
| 1 | At least one `FAILED`, `EMAIL CONFLICT`, `USERNAME CONFLICT`, `EMAIL MISMATCH`, `LAST ADMIN` or `EMAIL FOUND UNDER OTHER USERNAME`; or there were no applications to process. |
| 2 | Bad arguments, the `ALL` confirmation was not given, or the log files could not be created (for example an unwritable `--log-dir`). Nothing is changed in any of these cases. |

### Logs

Every run, dry or live, writes `logs/<YYYYMMDD-HHMMSS>_<server>_<op>.log` and a
sibling `.tsv` (one row per site) in the `--log-dir` (default `./logs`, relative
to where you run the tool). If a file for the same second already exists the name
gets a `-2` (`-3`, ...) suffix before the extension. Both are mode 600 and hold no credentials; they do
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
