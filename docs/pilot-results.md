# Pilot results

The blanks below are intentional. Whoever runs the pilot fills them in, then
a second person reviews the file before the tool is used on more than the pilot sites.
Follow `docs/runbook.md`. Use `--sites` for every command, never `--all`.

## Initial live test (already done): one site, throwaway Editor account

Date: 2026-10-08. Tool code: commit `099968f` (later commits change only docs).
The tool was copied to `/tmp` and run over SSH as an application user, not
`master`. Everything below happened on one live WordPress site with 12 users, all
Administrators, running an SMTP plugin, Jetpack and WP 2FA. The server had WP-CLI
2.12.0, bash 5.2.15 and `timeout`.

The test account was a throwaway Editor (`tool.test`) on a `+tooltest` address in
the tester's own mailbox. No existing user was changed and no Administrator was
created, disabled or demoted.

| Step | Result |
|---|---|
| `add` dry run | `WOULD CREATE` |
| `add --execute` | `CREATED - user #16`. Users went from 12 to 13. A fingerprint of the other 12 users (ID, login, email, roles) was identical before and after. The tester's own Administrator account was unchanged. |
| `add` again | `ALREADY EXISTS`. Nothing created. |
| `disable` dry run, then live | `WOULD DISABLE`, then `DISABLED` with no warnings. |
| Server state after `disable` | No roles, no capabilities, email `disabled+<ID>@webfor.invalid`, 0 login sessions (was 1), the saved note holds the original role and email, and a reset key requested before the disable was gone. |
| `disable` again | `ALREADY DISABLED`. Nothing changed. |
| Browser: old password | Rejected. |
| Browser: reset link saved before the disable (clicked before requesting a new one) | Invalid. |
| Browser: window that was logged in | Signed out. WordPress showed its standard "log in again" box over the old page. |
| New reset request after the disable | WordPress showed "Check your email for the confirmation link", and no email arrived. The server addressed the reset to the `.invalid` address. |
| Real mailbox | No "Email Changed" or "Password Changed" notice. |
| `restore` dry run, then live | `WOULD RESTORE`, then `RESTORED`. Role and email back, saved note removed, password still unusable (as designed). |
| Cleanup | Tool removed from the server. The throwaway account was deleted by hand in wp-admin. The user count (12) and the fingerprint matched the baseline taken before the test. The password manager did not save the account. |

What the live test found:

- Cloudways' `wp-config.php` loads `wp-salt.php` by a relative path, so WP-CLI failed
  on every site until the tool was changed to run from inside the site folder.
  Fixed (commit `099968f`, test in `tests/t_12_cwd.sh`).
- Application-user logins have a read-only home folder and a silent `scp`. The
  runbook now explains how to copy the tool through `/tmp`.
- In the first round of the disable test, an email arrived after the disable. A
  second round, run in a stricter order and in a truly private window, produced
  none. The cause of the first email was not confirmed. The tester suspects the
  second window in round 1 was a normal window of the same browser, not a private
  one, so it shared the logged-in cookies and the emails and links from the two
  requests could have been mixed up. Delayed mail from a reset requested before the
  disable is another possibility, because the site sends mail through an SMTP
  plugin. The server did record a reset after the disable in round 1, so a
  post-disable email cannot be ruled out. Watch for this during the pilot.

Not covered by that first live test: the Administrator role, more than one site in
a run, `--all`, accounts whose username differs from the one given, sites with
single sign-on plugins, and a `master` login. The sections below cover some of
these. Dry runs only were done on a second server.

## Whole-server dry run (already done): one server, master login, no changes

Date: 2026-10-09. Tool code: commit `d5a0147` (before the two fixes below). Run from
the Cloudways browser terminal as the master user, because SSH from a laptop was
refused (see the runbook). `add` for an existing staff account with `--all`, no
`--execute`: nothing was changed. 62 folders, 59 processed, finished in a few minutes.

| Result | Folders |
|---|---|
| `ALREADY EXISTS` | 18 |
| `WOULD CREATE` | 28 |
| `EMAIL CONFLICT` | 2 (one site, the email sits on a different username) |
| `FAILED` | 8 |
| `SKIPPED` (not WordPress) | 3 |

It found two bugs, both fixed and covered by new tests:

- **Every site was processed twice.** 29 of the 62 entries were symlinks, the
  friendly-name alias of another folder, so 28 sites showed as 59 applications and
  each site's result appeared twice. Fixed: one entry per physical folder.
- **8 folders (4 sites) reported `FAILED - marker lookup`** although the user existed.
  A stale Object Cache Pro drop-in printed `objectcache.critical: Failed to locate and
  load object cache API` on every call, and the tool read that as an error. Fixed:
  that one line is ignored. A live `disable` or `restore` on a site with an
  object-cache drop-in now warns that cached user data may be stale. Whether Redis
  really serves the old user was not tested.

The fixed code (commit `02bc912`) was then dry-run on the same server: 30
applications instead of 59, no `FAILED` rows, and the four sites that had failed
now showed `ALREADY EXISTS`.

## First multi-site live run (already done): three sites, Administrator

Date: 2026-10-09. Tool code: commit `02bc912`. Master login, from the Cloudways
browser terminal. `add` of the tester's own staff account as an Administrator on
three client sites, named with `--sites` (never `--all`).

| Step | Result |
|---|---|
| Dry run of the three sites | `WOULD CREATE` on all three, exit 0. The live run was gated on a clean dry run. |
| `add --execute` | `CREATED` on all three (user IDs #21, #15, #14), exit 0. |
| Read-only check afterwards (run from inside each site's folder) | Role `administrator` and the right email on all three. The sites had 10, 4 and 6 users, of which 7, 4 and 6 were Administrators. |
| Browser | The tester set a password with "Lost your password?" on each site and logged in. No per-site timing of the reset email was recorded. |

Then a throwaway Administrator (`tool.admin`, a `+pilot` address in the tester's own
mailbox) was added to the same three sites with the same dry-run-first gate:
`CREATED` on all three, role `administrator`. The disable and restore test was
**not** run. The tester judged it unnecessary risk on client sites, and the account
was removed. The tool never deletes users, so it was deleted by hand with a
WP-CLI command that first checked the username, the email and that the account had
no posts. All three sites then answered `Invalid user` for `tool.admin`. It never had
a password and never logged in.

What this run showed:

- **My own check commands failed silently at first.** Cloudways' `wp-config.php`
  loads `wp-salt.php` by a relative path, so a bare `wp --path=...` printed nothing
  and counted 0 users. Run `wp` from inside the site folder, as the tool does.
  Because of this, the user counts from before the add were not captured, so
  "exactly one user created" rests on the tool's `CREATED` line (one per site), not
  on a before and after count.
- **A browser terminal needs care.** See the runbook section on the master login.
  Right-click Paste worked for long commands; Cmd+V on a Mac added a stray `v`.

Still not tested live: `disable` and `restore` of an Administrator, `LAST ADMIN`,
`--all` with `--execute`, the object-cache warning on a real site, and the alias
folder handling in a live run (it was covered by sandbox tests and a whole-server
dry run).

## Eleven-site live run (already done): same server, Administrator

Date: 2026-10-09, after the three-site run. Tool code: commit `02bc912`. Master login,
browser terminal. `add` of the tester's own staff account as an Administrator on the
11 remaining WordPress sites of that server that did not have it, named with `--sites`
(never `--all`). The live run was gated on a clean dry run.

| Step | Result |
|---|---|
| Dry run of the 11 sites | `WOULD CREATE` on all 11, exit 0, nothing changed. |
| `add --execute` | `CREATED` on all 11, exit 0, no warnings. |
| Read-only check afterwards | Role `administrator` on all 11. The check did not print the email (it kept only the last output line), so the email rests on the tool's own `CREATED` line and on the same check on the first three sites, which did show it. |
| Time | A minute or two for 11 sites. |

Server state afterwards: of the 28 WordPress sites on that server, 27 have the account.
The remaining one has the same email under a different username, so the tool reported
`EMAIL CONFLICT` and changed nothing; it needs a decision by hand. Two folders are not
WordPress and are skipped. Other servers were not touched.

This went beyond the 2-3 site pilot that the brief says a second person should review
first. The tester chose it, because it only adds their own account and changes nobody
else. `disable` and `restore` were not run at this scale.

Run by: ______  Date: ______  Tool version (git commit): ______
SSH login user (`master` or an application user): ______
Server: ______  WP-CLI version (`wp --version`): ______
Sites used (2-3, Webfor-managed, folder names): ______
WordPress version of each site: ______

For each step, save the console output or the log/tsv files from `./logs` and
note the path. A dry run and its live run are separate log files.

## Test 1: Add
- [ ] Dry run reviewed: every pilot site shows `WOULD CREATE` (or an explained other result). Log: ______
- [ ] Live run on only the pilot sites: `CREATED - user #N` on each. Log: ______ Exit code: ___
- [ ] Jane Doe exists on each site (check in wp-admin, Users)
- [ ] Email is jane.doe@webfor.com
- [ ] Role is Administrator
- [ ] No other users changed; content unaffected
- [ ] No unexpected email reached anyone (the live run without `--send-email` sends none)
- Password workflow: "Lost your password?" email arrived? ___ Link worked? ___
  Site outbound email working? ___ Notes: ______

## Test 2: Duplicate protection
- [ ] Re-run of the same live `add`: `ALREADY EXISTS` for every site; nothing changed. Log: ______

## Test 3: Disable
- [ ] BEFORE the disable: request "Lost your password?" for the employee's real address on each pilot site (a controlled test, you receive the mail) and keep the link (use a private window, see the runbook's "Checking a disable in a browser"). After the disable, click that saved link FIRST, before requesting any new reset, and confirm it is dead (it says the key is invalid or expired)
- [ ] Dry run reviewed: `WOULD DISABLE` on each pilot site. Log: ______
- [ ] Live run: `DISABLED` on each pilot site, no `FAILED`, no warnings (or warnings explained: ______). Log: ______
- [ ] Existing sessions ended (tested with a browser logged in as Jane before the run: ___)
- [ ] Cannot log in; cannot reach /wp-admin in a browser (the sandbox did not test this)
- [ ] Administrator privileges gone (user shows no role)
- [ ] User record remains, with email `disabled+<ID>@webfor.invalid`; authored content intact
- [ ] No other users affected
- [ ] "Lost your password?" for the old login does not deliver mail to Jane
- [ ] Jane's real mailbox received no "Email Changed" or "Password Changed" notice
- [ ] Re-run of the same live `disable`: `ALREADY DISABLED`, nothing changed

## Test 4: Restore
- [ ] Dry run reviewed: `WOULD RESTORE` on each pilot site
- [ ] Live run: `RESTORED` on each pilot site
- [ ] Role (Administrator) and email (jane.doe@webfor.com) restored
- [ ] Jane's real mailbox received no "Email Changed" notice
- [ ] Old password still rejected
- [ ] Reset flow ("Lost your password?") sets a new password and login works in a browser

## Other checks
- [ ] Log and tsv files exist for every run, are mode 600 (`ls -l logs`), and contain no passwords
- [ ] Time per site (from the log timestamps): ______
- [ ] Any `SKIPPED` or `FAILED` site on the pilot list, and why: ______

## Problems found
______

## Recommendation (to be written after the pilot)
Safe to use across an entire Cloudways server? ______
Conditions before wider use: ______
Reviewed by: ______  Date: ______
