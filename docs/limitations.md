# Limitations and edge cases

## What disable does not cover

- **Login plugins.** SSO, magic-link, or social-login plugins on a site may
  admit a disabled account by other means. The tool cannot see them (it runs
  with plugins skipped). A must-use plugin that blocks login outright would
  close this and is out of scope for v1.
- **Other credentials.** SSH, SFTP, database, hosting-panel, and third-party
  accounts are separate offboarding steps.
- **Multisite** installs are skipped and reported (`SKIPPED - multisite, handle
  manually`). Handle them by hand.
- **Direct capabilities.** A user with capabilities granted directly (not via
  roles) keeps them after role removal. The report warns `user still has direct
  capabilities` when this happens.
- **Application passwords** need WordPress 5.6+. On older sites the step cannot
  run; the report shows the warning `application passwords unavailable on this
  site` and the site is still marked `DISABLED`, not `FAILED`.
- **Only accounts this tool disabled** can be restored by it. Without the
  `webfor_disabled` marker the result is `NOT DISABLED` and the tool never
  guesses roles.

## What the tool changes on the site

- **The swapped email** (`disabled+<ID>@webfor.invalid`) changes what admin
  screens and Gravatar show for the disabled user. `restore` puts the original
  back.
- **Plugins and themes are skipped during runs** (`--skip-plugins
  --skip-themes`). Plugin hooks that normally react to user creation, such as CRM
  sync, audit logs and welcome emails, do not fire. Must-use plugins still load.
- **WordPress notices are suppressed.** WP-CLI 2.12 would send "Email Changed"
  and "Password Changed" mail to the employee's old or real address when the
  tool swaps the email on `disable` or puts it back on `restore`. The tool
  passes `--exec` hooks that turn those two notices off, so the employee's real
  mailbox receives nothing from `disable` or `restore`. A manual `wp user update`
  outside the tool would still send them.
- **`add --send-email` sends two mails.** WordPress sends an admin "New User
  Registration" notice (to the site's admin email address, usually the client)
  and the user's "Login Details" mail. Without `--send-email` nothing is sent.

## Roles

- **Plugin-defined roles are invisible to `add --role`.** Role lookups run with
  plugins skipped, so a role such as `shop_manager` (WooCommerce) reports
  `FAILED - role 'shop_manager' does not exist on this site`. The default
  `administrator` role is unaffected. Create the user with a built-in role and
  change it by hand if needed.
- **Unusual stored role names.** If a user's role name contains anything other
  than lowercase letters, digits, `_` or `-`, `disable` refuses with `FAILED -
  unusual role name '...'; handle manually` and changes nothing. `restore`
  likewise refuses (`FAILED - unusual stored role name`) before changing
  anything.
- **`LAST ADMIN`** counts users who hold the `administrator` role. It is checked
  on a fresh `disable` only, not when resuming a partial one.

## Lookups

- **Email lookup fallback.** `wp user get <email>` falls back to a login equal to
  that string. A user whose *login* equals the employee's email address is
  therefore treated as holding that email: `add` reports a conflict and the
  account is never modified.
- **Case.** Email comparison against the stored values is case-insensitive.
  Usernames must be lowercase and match `[a-z0-9._-]+`, must not start with `-`,
  and must not be all digits.
- **`--sites` takes folder names only**, not site URLs.

## Failure and recovery

- **Partial disable.** If any of steps 2 to 6 fails, the result is `FAILED -
  PARTIAL (...)`. Fix the cause and re-run `disable`; the `in_progress` marker
  makes it resume.
- **Partial restore.** If `restore` fails after the email step, re-run it. The
  marker is kept until all steps succeed. A failed email step does not stop the
  roles step, so the account can briefly have its roles back with the
  neutralised email; the retry fixes it.
- **Restore's report row** shows the ROLE column as the state before the restore
  (normally `-`). The restored roles appear in the result detail. This is cosmetic.
- **Long error messages** are cut at 200 characters in the report.

## Environment

- **Time.** Roughly 7 to 20 WP-CLI loads per site (a live disable or restore is at the
  high end). A hung call is stopped after
  `WP_TIMEOUT` seconds (default 120) and the site is reported `FAILED`. Sites are
  processed one at a time.
- **No `timeout` command.** On hosts without `timeout` (macOS, for example) WP-CLI
  runs with no per-call time limit. Cloudways Linux servers have it.
- **Exit code and `SKIPPED`.** `SKIPPED` sites appear in the manual-review list
  but do not make the exit code 1. Read the list; do not rely on the exit code
  alone.
- **Tested versions.** Behaviour was measured against WP-CLI 2.12.0 and
  WordPress 7.1.3 in the Docker sandbox with bash 5.3 (see the header of
  `tests/t_00_probe.sh`). It has not been run on a Cloudways server yet; other
  WP-CLI or WordPress versions may differ in the details the tool parses.
- **Not tested in a browser.** The sandbox verifies authentication, sessions,
  capabilities, and application passwords through WordPress itself, not an HTTP
  request to `/wp-admin`. The Server 3 pilot must check browser access, including
  that an already logged-in browser is signed out.
