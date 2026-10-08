# Cloudways Bulk Users

Add, disable, and restore one employee's WordPress login across every site on a Cloudways server, from one command.

Say you manage 40 WordPress sites on a Cloudways server and a new person joins your team. Logging in to each site and creating their account takes an afternoon. When someone leaves, you have to remove their access from all 40 sites, fast, without deleting anything they wrote. This tool does both jobs in a few minutes. It runs on the server itself and uses WP-CLI, the command-line tool that ships with Cloudways.

The command is called `webfor-wp-users`. It was built for Webfor's setup, and it works for any team that runs WordPress on Cloudways and has SSH access to the server.

> **Status:** The tool passes its full test suite (318 checks) in a Docker sandbox. Dry runs (which change nothing) have worked on two live Cloudways servers, and a real `--execute` run (add, disable, restore with a throwaway Editor account) worked on one live site. Administrator accounts and multi-site runs are not yet tried live. The next step is a small pilot on two or three sites. See [Running the pilot](#running-the-pilot).

---

## Contents

1. [What it does](#what-it-does)
2. [What it will never do](#what-it-will-never-do)
3. [What you need](#what-you-need)
4. [Install](#install)
5. [Two rules to remember](#two-rules-to-remember)
6. [Your first run, step by step](#your-first-run-step-by-step)
7. [Choosing which sites to change](#choosing-which-sites-to-change)
8. [Add an employee](#add-an-employee)
9. [Disable an employee](#disable-an-employee)
10. [Restore an employee](#restore-an-employee)
11. [How to read the results](#how-to-read-the-results)
12. [All the options](#all-the-options)
13. [Logs and exit codes](#logs-and-exit-codes)
14. [When something goes wrong](#when-something-goes-wrong)
15. [What the tool cannot do](#what-the-tool-cannot-do)
16. [Running the pilot](#running-the-pilot)
17. [Running the tests](#running-the-tests)
18. [What is in this repository](#what-is-in-this-repository)

---

## What it does

The tool has three commands. Each one works on one employee at a time, across as many sites as you choose.

| Command | What happens on each site |
|---|---|
| `add` | Creates the employee as an Administrator, unless the account already exists. |
| `disable` | Locks the employee out right away. Their account stays on the site, so their posts, pages, and orders keep their author. |
| `restore` | Undoes a `disable`. The employee gets their role and email back and sets a new password. |

For every run you get a table with one row per site, a count of each result, and a short list of the sites that need a human to look at them. The tool also writes the same information to a log file.

## What it will never do

- **It never deletes a user or any content.** The command for deleting users is not in the code, and a test checks for that.
- **It never changes anything unless you say so.** Every command is a practice run (a "dry run") until you add `--execute`.
- **It never touches client accounts.** To act on an account, the username and the email must both match the employee you named. It also refuses to disable the only administrator on a site.
- **It never runs on a folder it cannot verify.** Before touching a site, it checks that WordPress is installed there and that the site is not a multisite network.
- **It never stops because one site has a problem.** A broken site gets a `FAILED` row and the tool moves on to the next one.
- **It never prints or stores a password.** WordPress generates passwords, and the tool throws them away without looking at them.
- **It never sets up 2FA or touches plugins.** It leaves both alone.

## What you need

- A Cloudways server where you can log in over SSH as the **master user**.
- WP-CLI on that server. Cloudways installs it. Check with `wp --version`.
- `bash`. Every Cloudways server has it. The tool was tested with bash 5.3.9.
- Optional: the `timeout` command (`command -v timeout` shows whether you have it). With it, a site that hangs gives up after 120 seconds. Without it, a hung site waits forever.
- Optional: Docker, only if you want to run the test suite.

The email you give the tool must be on an allowed domain. The default is `webfor.com`. If your team uses a different domain, add `--allowed-domain yourcompany.com` to every command. This rule stops you from changing the account of someone outside your company by accident.

## Install

The tool is a folder of shell scripts. Copy the `bin` and `lib` folders to the server and keep them side by side.

From your own computer, in this repository's folder:

```bash
ssh <you>@<server> 'mkdir -p ~/webfor-wp-users'
```

```bash
scp -r bin lib <you>@<server>:~/webfor-wp-users/
```

Then log in to the server and make the script runnable:

```bash
ssh <you>@<server>
```

```bash
chmod +x ~/webfor-wp-users/bin/webfor-wp-users
```

Run a quick check of the tools it depends on:

```bash
wp --version && command -v timeout && bash --version | head -1
```

Some Cloudways logins are application users, not `master`. Their home folder is not writable and `scp` may copy nothing. If that happens to you, the runbook has a section ([If you log in as an application user](docs/runbook.md#if-you-log-in-as-an-application-user-not-master)) that copies the tool into `/tmp` with `tar` over SSH.

The tool needs a WP-CLI version that has the `application-password` command. The tests used WP-CLI 2.12.0, and older versions may not work.

To see the built-in help at any time:

```bash
~/webfor-wp-users/bin/webfor-wp-users --help
```

## Two rules to remember

1. **A dry run happens first, every time.** Without `--execute`, the tool only reads. It tells you what it would do. Read the table, and if it looks right, run the same command again with `--execute` on the end.
2. **While you are testing, always use `--sites`.** That option names the exact sites to change. The `--all` option means every site on the server. Save `--all` for after you trust the tool.

## Your first run, step by step

This walkthrough adds an employee named Jane Doe to one site. Use any test site you like.

**Step 1. Find the folder name of your site.** Cloudways names each site's folder with a random string:

```bash
ls /home/master/applications
```

You see something like `abcdefghij  klmnopqrst`. Pick one folder to start.

**Step 2. Do a dry run.**

```bash
cd ~/webfor-wp-users
```

```bash
bin/webfor-wp-users add --username jane.doe --email jane.doe@webfor.com --first-name Jane --last-name Doe --display-name "Jane Doe" --sites abcdefghij
```

The tool prints something like this (a real example, trimmed):

```text
DRY RUN: add jane.doe <jane.doe@webfor.com> server=testsrv
Applications to process: 1

SITE | WP | USER EXISTS | ROLE | ACTION | RESULT | WARNINGS
https://app_a.test (app: app_a) | Yes | No | - | CREATE | WOULD CREATE | -

Totals:
  WOULD CREATE: 1
  Applications processed: 1

DRY RUN: no changes were made.
```

The site's web address appears at the start of each row. Check that it is the site you meant. `WOULD CREATE` means the account does not exist yet and the tool would create it.

**Step 3. Run it for real.** Repeat the same command and add `--execute` at the end:

```bash
bin/webfor-wp-users add --username jane.doe --email jane.doe@webfor.com --first-name Jane --last-name Doe --display-name "Jane Doe" --sites abcdefghij --execute
```

The result column now says `CREATED - user #2` (the number is the new account's ID on that site).

**Step 4. Check the site.** Open the site's WordPress admin and go to Users. You should see Jane Doe, with the right email and the Administrator role.

**Step 5. Run it a second time.** The result is `ALREADY EXISTS`, and nothing changes. You can run `add` as often as you like without making duplicates.

## Choosing which sites to change

Every command needs exactly one of these:

| Option | What it means |
|---|---|
| `--sites a,b,c` | A comma-separated list of folder names under `/home/master/applications`. Site web addresses do not work here, only folder names. |
| `--all` | Every folder on the server. If you also add `--execute`, the tool stops and asks you to type `ALL` before it does anything. Any other answer cancels the run. |
| `--exclude a,b` | Optional. Skip these folders. Works with either of the above. |

If you name a folder that does not exist, you get a `SKIPPED - no such application folder` row. The run carries on with the other sites.

## Add an employee

```bash
bin/webfor-wp-users add --username jane.doe --email jane.doe@webfor.com --first-name Jane --last-name Doe --display-name "Jane Doe" --sites <folders>
```

Add `--execute` to make it real. The role defaults to Administrator. Use `--role editor` (or another role) if you want a different one.

For each site, the tool looks for the username and for the email before it creates anything:

| Result | What it means |
|---|---|
| `WOULD CREATE` | Dry run only. The account would be created. |
| `CREATED - user #N` | The account now exists. |
| `ALREADY EXISTS` | The username and email already belong to the same account. Nothing changed. If the role is different from what you asked for, the row says so. If this tool disabled the account earlier, the row says `DISABLED, use restore`. |
| `EMAIL CONFLICT` | A different account on that site already uses the email. The tool changed nothing. Look at it by hand. |
| `USERNAME CONFLICT` | The username exists on that site with a different email. The tool changed nothing. Look at it by hand. |

### How the employee gets a password

The tool does not choose a password. WordPress generates one that nobody sees, and **no email goes out**. The employee opens the site's login page, clicks **Lost your password?**, and WordPress emails them a reset link. They do this once per site. That only works if the site can send email, so check that during your first test.

If you add `--send-email`, WordPress sends its normal new-user emails instead. It sends two: a "Login Details" message to the employee and a "New User Registration" notice to the site's admin email address. On a client site the admin address is often the client's, so use `--send-email` with care.

The tool does not set up 2FA. Do that after the employee can log in.

## Disable an employee

Use this when someone leaves.

```bash
bin/webfor-wp-users disable --username jane.doe --email jane.doe@webfor.com --sites <folders>
```

Add `--execute` to make it real. WordPress has no "disabled" switch for a user, and changing a role to Subscriber still lets the person log in. So the tool takes seven steps on each site, in this order:

1. **Saves a note on the account** with the employee's original roles and email. This note is what lets `restore` work later. If this step fails, the tool changes nothing else.
2. **Replaces the password** with a random one that nobody knows. It also cancels any "Lost your password?" link the person requested earlier.
3. **Ends every login session**, so a browser that is already signed in gets signed out.
4. **Deletes the account's application passwords.** Those are extra passwords that apps use to talk to the site, and they work without the normal password.
5. **Removes all roles.** The account can no longer do anything.
6. **Changes the email** to `disabled+<ID>@webfor.invalid`. The `.invalid` ending can never receive mail, so a password-reset email sent to this account goes nowhere. The tool also switches off WordPress's "your email changed" notice, so the employee's real mailbox gets nothing.
7. **Marks the note as complete.**

The account itself stays on the site. Their posts, pages, orders, and comments keep the same author. Deleting the account is a separate job that you do by hand later, when you are sure.

### Safety checks for disable

- The username and the email must both match. If the username exists with a different email, you get `EMAIL MISMATCH` and the tool leaves the account alone.
- If the username does not exist but the email belongs to an account with a different username, you get `EMAIL FOUND UNDER OTHER USERNAME`. The tool changes nothing. The person may still have access under that other login, so look at it by hand.
- If the account is the only administrator on a site, you get `LAST ADMIN` and the tool leaves it alone.

| Result | What it means |
|---|---|
| `WOULD DISABLE` | Dry run only. |
| `DISABLED` | All seven steps worked. |
| `ALREADY DISABLED` | The account was disabled earlier. Nothing changed. |
| `NOT FOUND` | No account has that username or that email. Nothing changed. If every site says this, check that you typed the username correctly. The exit code stays 0, so read the table. |
| `EMAIL MISMATCH`, `LAST ADMIN`, `EMAIL FOUND UNDER OTHER USERNAME` | Review by hand. The tool changed nothing. |
| `FAILED - PARTIAL (...)` | Some steps worked and one failed. Fix the cause the message names, then run the same command again. It picks up where it stopped. |

## Restore an employee

Use this if you disabled the wrong person, or someone comes back.

```bash
bin/webfor-wp-users restore --username jane.doe --email jane.doe@webfor.com --sites <folders>
```

Add `--execute` to make it real. The tool reads the note it saved during `disable`, puts the original email back, gives back every role, and removes the note.

The password stays unusable. The employee clicks **Lost your password?** and sets a new one. The tool never brings back an old password, and it does not recreate application passwords or sessions.

| Result | What it means |
|---|---|
| `WOULD RESTORE` | Dry run only. |
| `RESTORED` | Done. |
| `NOT DISABLED` | This tool did not disable the account, so there is no note to read. The tool will not guess the roles. Nothing changed. |
| `EMAIL CONFLICT` | Another account now uses the original email. Nothing changed. |
| `EMAIL MISMATCH` | The email you gave does not match the saved one. Nothing changed. |

## How to read the results

Each run prints, in this order:

1. A header line that says `DRY RUN` or `EXECUTE`, the operation, the employee, and the server.
2. A table with one row per site: the site address, whether WordPress was found, whether the account exists, its role, the action, the result, and any warnings.
3. **Totals**: how many sites got each result.
4. **Needs manual review**: every site with a `FAILED`, `SKIPPED`, conflict, mismatch, or `LAST ADMIN` result, with the reason.

A few results come before the employee lookup. The tool uses them when it cannot work on a site at all:

| Result | What it means |
|---|---|
| `SKIPPED - no public_html` | The folder has no website in it. |
| `SKIPPED - not WordPress` | The folder does not contain WordPress. |
| `SKIPPED - WordPress files found but not installed` | The files exist but WordPress was never set up. |
| `SKIPPED - multisite, handle manually` | A WordPress multisite network. The tool does not handle those. |
| `FAILED - ...` | Something broke, such as a database error or a WP-CLI call that timed out. The reason follows the word FAILED. |

**Read the WARNINGS column on every row.** A warning does not change the exit code and does not add the site to the review list. Two warnings matter most:

- `user still has direct capabilities` (on disable). The account had permissions attached directly, not through a role. The tool removed the roles but not those permissions. Check the account by hand.
- `application passwords unavailable on this site` (on disable). WordPress said it could not manage application passwords for this site, so the tool did not delete them. Check the user's profile by hand and revoke any that exist.

## All the options

| Option | Default | What it does |
|---|---|---|
| `--username` | none | The employee's WordPress username. Lowercase letters, digits, `.`, `_`, `-`. It cannot start with `-` or be only digits. |
| `--email` | none | The employee's email. It must be on the allowed domain. |
| `--first-name`, `--last-name`, `--display-name` | none | Required for `add` only. |
| `--role` | `administrator` | The role for `add`. |
| `--sites` / `--all` / `--exclude` | none | Which sites to work on. You must give `--sites` or `--all`. |
| `--execute` | off | Make the changes. Without it, the run is a dry run. |
| `--send-email` | off | For `add`: let WordPress send its new-user emails. |
| `--apps-root` | `/home/master/applications` | Where the site folders live. |
| `--log-dir` | `./logs` | Where the log files go. |
| `--server` | the server's hostname | A label for the log. |
| `--allowed-domain` | `webfor.com` | The email domain the tool accepts. |
| `--allow-any-domain` | off | Turn the domain check off. Not recommended. |

Two environment variables also exist. `WP_TIMEOUT` sets the number of seconds the tool waits for each WP-CLI call (default 120). `WP_BIN` sets the path of the `wp` program (default `wp`).

## Logs and exit codes

Every run, practice or real, writes two files in the log folder: `<date>-<time>_<server>_<operation>.log` and a matching `.tsv` file with one row per site. Only you can read them (permissions 600). They hold the employee's username and email and the site addresses. They never hold a password.

When the tool finishes, it returns an exit code:

| Code | What it means |
|---|---|
| 0 | No site failed and none needs review. Skipped sites and warnings do not change this, so read the table. |
| 1 | At least one site failed or needs review, or there were no sites to work on. |
| 2 | The command was wrong, you did not type `ALL` when asked, or the tool could not create its log files. Nothing was changed. |

## When something goes wrong

- **A `FAILED - PARTIAL` result.** Fix the cause in the message and run the same command again. The tool finds its saved note and finishes the job.
- **You disabled the wrong person.** Run `restore` with the same username, email, and sites.
- **A restore fails partway.** Run the same `restore` command again. The tool keeps its note until every step works.
- **A restore keeps failing because a role no longer exists on the site.** Create that role again by hand, then rerun `restore`. As a last resort, restore the roles and email with WP-CLI yourself, then delete the note so the tool stops treating the account as disabled. The runbook has the exact command.
- **You want to see the saved note for an account:**

  ```bash
  wp --path=/home/master/applications/<folder>/public_html --skip-plugins --skip-themes user meta get <user-id> webfor_disabled --format=json
  ```

- **A site hangs.** The tool stops waiting after 120 seconds (if `timeout` exists), marks that site `FAILED`, and goes on to the next.

## What the tool cannot do

The full list is in [docs/limitations.md](docs/limitations.md). The ones that matter most:

- **Login plugins.** A single-sign-on, magic-link, or social-login plugin on a site might let a disabled account in some other way. The tool cannot see those plugins, because it runs with plugins turned off.
- **Credentials that plugins hold.** Tools such as WooCommerce API keys are tied to the user's ID and stay in place. They only reach a user with no roles, but review them on sites where the employee used them.
- **Other logins.** The tool does not touch SSH, SFTP, database, hosting-panel, or third-party accounts. Those are separate steps in your offboarding list.
- **Multisite networks and WordPress in a subfolder** (like `public_html/blog`). The tool skips both and tells you.
- **Plugin-defined roles.** If `add --role` names a role that a plugin creates only while it runs, the tool reports that the role does not exist. Create the user as an Administrator or Editor and change the role by hand.
- **Accounts the tool did not disable.** `restore` only works on accounts that `disable` saved a note for.

## Running the pilot

Before you use the tool across a whole server, run it on two or three sites and check the results with your own eyes. [docs/pilot-results.md](docs/pilot-results.md) is a checklist you can fill in as you go. [docs/runbook.md](docs/runbook.md) has the full operating guide.

The short version:

1. Pick two or three low-risk sites where email works.
2. Add the employee (dry run, then `--execute`). Check the users in WordPress.
3. Have the employee set a password, log in, and stay logged in with a browser.
4. Ask for a "Lost your password?" email and keep the link.
5. Disable the employee. Confirm the browser is signed out, the old password fails, the saved reset link is dead, and no reset email arrives.
6. Restore. Confirm the role and email came back and a new password works.
7. Keep the log files and the filled-in checklist.

The sandbox tests cannot open a real browser, so step 5 is the first time anyone checks that part for real.

## Running the tests

The tests need Docker. They build a throwaway WordPress and MariaDB setup, create ten fake sites (some healthy, some deliberately broken), and run the tool against them. Nothing touches a real server.

```bash
tests/run.sh
```

The first run downloads images and takes several minutes. To run one group of tests, add part of a file name:

```bash
tests/run.sh disable
```

The groups are `probe`, `framework`, `add`, `disable`, `restore`, and `safety`. A passing run ends with `N passed, 0 failed`.

## What is in this repository

```
bin/webfor-wp-users      the command you run
lib/                     the code it uses
  common.sh                checks on what you type, logging
  wp.sh                    every call to WP-CLI, in one place
  report.sh                the results table, totals, and exit code
  discover.sh              finding and checking site folders
  op_add.sh                the add command
  op_disable.sh            the disable command
  op_restore.sh            the restore command
tests/                   the Docker test suite
docs/
  runbook.md               the full operating guide
  limitations.md           everything the tool cannot do
  example-report.md        real output from the test sandbox
  pilot-results.md         the checklist for the first live trial
  superpowers/             the design spec and build plan
```

The design spec ([docs/superpowers/specs](docs/superpowers/specs/2026-10-07-webfor-wp-users-design.md)) explains why the tool works the way it does.

## License

MIT. See [LICENSE](LICENSE). This tool changes user accounts on live websites, so test it on a few sites before you rely on it, as described in [Running the pilot](#running-the-pilot).
