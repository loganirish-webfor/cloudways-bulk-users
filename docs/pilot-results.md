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

Not covered yet: the Administrator role live (including `LAST ADMIN`), more than
one site in a run, `--all`, accounts whose username differs from the one given,
sites with single sign-on plugins, and a server where the login is `master`.
Dry runs only were done on a second server.

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
