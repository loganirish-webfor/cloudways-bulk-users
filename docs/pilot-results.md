# Pilot results

The blanks below are intentional. Whoever runs the pilot fills them in, then
A second person reviews the file before the tool is used on more than the pilot sites.
Follow `docs/runbook.md`. Use `--sites` for every command, never `--all`.

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
- [ ] BEFORE the disable: request "Lost your password?" for the employee's real address on each pilot site (a controlled test, you receive the mail) and keep the link. After the disable confirm the link is dead (it says the key is invalid or expired)
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
