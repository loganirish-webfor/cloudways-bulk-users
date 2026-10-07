# Example output

Generated from the Docker sandbox by `tests/example_report.sh`. Site names are
fixtures (`app_a`, `https://app_a.test`, and so on), the server label is `testsrv`, and the
log paths are sandbox paths. The `[n/N] folder` progress lines the tool prints to
stderr are left out. Each block is one run of the tool; blocks 2 to 6 follow on from
each other, starting from the same fresh fixtures as block 1.

### 1. Add: dry run on every application

```text
DRY RUN: add logan.irish <logan.irish@webfor.com> server=testsrv
Applications to process: 10
Log: /tmp/wwu-logs/20261007-204717_testsrv_add.log

DRY RUN RESULTS: add logan.irish <logan.irish@webfor.com> server=testsrv
SITE | WP | USER EXISTS | ROLE | ACTION | RESULT | WARNINGS
https://app_a.test (app: app_a) | Yes | No | - | CREATE | WOULD CREATE | -
https://app_b.test (app: app_b) | Yes | No | - | CREATE | WOULD CREATE | -
(app: app_broken) | No | - | - | - | FAILED - WP-CLI error: Error establishing a database connection. This either means that the username and password information in your `wp-config.php` file is incorrect or that contact with the database server at `db` could  | -
https://app_emailtaken.test (app: app_emailtaken) | Yes | Email taken | - | NONE | EMAIL CONFLICT - REVIEW REQUIRED - email on user #2 | -
https://app_exists.test (app: app_exists) | Yes | Yes | administrator | NONE | ALREADY EXISTS | -
(app: app_multisite) | Yes | - | - | - | SKIPPED - multisite, handle manually | -
(app: app_nopublic) | No | - | - | - | SKIPPED - no public_html | -
(app: app_notwp) | No | - | - | - | SKIPPED - not WordPress | -
https://app_soleadmin.test (app: app_soleadmin) | Yes | Yes | administrator | NONE | ALREADY EXISTS | -
https://app_usertaken.test (app: app_usertaken) | Yes | Yes (other email) | - | NONE | USERNAME CONFLICT - REVIEW REQUIRED - username exists on user #2 with a different email | -

Totals:
  ALREADY EXISTS: 2
  EMAIL CONFLICT: 1
  FAILED: 1
  SKIPPED: 3
  USERNAME CONFLICT: 1
  WOULD CREATE: 2
  Applications processed: 10

Needs manual review:
  - (app: app_broken): FAILED - WP-CLI error: Error establishing a database connection. This either means that the username and password information in your `wp-config.php` file is incorrect or that contact with the database server at `db` could 
  - https://app_emailtaken.test (app: app_emailtaken): EMAIL CONFLICT - REVIEW REQUIRED - email on user #2
  - (app: app_multisite): SKIPPED - multisite, handle manually
  - (app: app_nopublic): SKIPPED - no public_html
  - (app: app_notwp): SKIPPED - not WordPress
  - https://app_usertaken.test (app: app_usertaken): USERNAME CONFLICT - REVIEW REQUIRED - username exists on user #2 with a different email

DRY RUN: no changes were made.
```

### 2. Add: create on two sites

```text
EXECUTE: add logan.irish <logan.irish@webfor.com> server=testsrv
Applications to process: 2
Log: /tmp/wwu-logs/20261007-204723_testsrv_add.log

EXECUTE RESULTS: add logan.irish <logan.irish@webfor.com> server=testsrv
SITE | WP | USER EXISTS | ROLE | ACTION | RESULT | WARNINGS
https://app_a.test (app: app_a) | Yes | No | - | CREATE | CREATED - user #2 | -
https://app_b.test (app: app_b) | Yes | No | - | CREATE | CREATED - user #2 | -

Totals:
  CREATED: 2
  Applications processed: 2
```

### 3. Add again: duplicate protection

```text
EXECUTE: add logan.irish <logan.irish@webfor.com> server=testsrv
Applications to process: 2
Log: /tmp/wwu-logs/20261007-204725_testsrv_add.log

EXECUTE RESULTS: add logan.irish <logan.irish@webfor.com> server=testsrv
SITE | WP | USER EXISTS | ROLE | ACTION | RESULT | WARNINGS
https://app_a.test (app: app_a) | Yes | Yes | administrator | NONE | ALREADY EXISTS | -
https://app_b.test (app: app_b) | Yes | Yes | administrator | NONE | ALREADY EXISTS | -

Totals:
  ALREADY EXISTS: 2
  Applications processed: 2
```

### 4. Disable: dry run

```text
DRY RUN: disable logan.irish <logan.irish@webfor.com> server=testsrv
Applications to process: 10
Log: /tmp/wwu-logs/20261007-204727_testsrv_disable.log

DRY RUN RESULTS: disable logan.irish <logan.irish@webfor.com> server=testsrv
SITE | WP | USER EXISTS | ROLE | ACTION | RESULT | WARNINGS
https://app_a.test (app: app_a) | Yes | Yes | administrator | DISABLE | WOULD DISABLE - roles: administrator | -
https://app_b.test (app: app_b) | Yes | Yes | administrator | DISABLE | WOULD DISABLE - roles: administrator | -
(app: app_broken) | No | - | - | - | FAILED - WP-CLI error: Error establishing a database connection. This either means that the username and password information in your `wp-config.php` file is incorrect or that contact with the database server at `db` could  | -
https://app_emailtaken.test (app: app_emailtaken) | Yes | No | - | NONE | NOT FOUND | -
https://app_exists.test (app: app_exists) | Yes | Yes | administrator | DISABLE | WOULD DISABLE - roles: administrator | -
(app: app_multisite) | Yes | - | - | - | SKIPPED - multisite, handle manually | -
(app: app_nopublic) | No | - | - | - | SKIPPED - no public_html | -
(app: app_notwp) | No | - | - | - | SKIPPED - not WordPress | -
https://app_soleadmin.test (app: app_soleadmin) | Yes | Yes | administrator | NONE | LAST ADMIN - REVIEW REQUIRED - only administrator on this site | -
https://app_usertaken.test (app: app_usertaken) | Yes | Yes | editor | NONE | EMAIL MISMATCH - REVIEW REQUIRED - username exists with a different email | -

Totals:
  EMAIL MISMATCH: 1
  FAILED: 1
  LAST ADMIN: 1
  NOT FOUND: 1
  SKIPPED: 3
  WOULD DISABLE: 3
  Applications processed: 10

Needs manual review:
  - (app: app_broken): FAILED - WP-CLI error: Error establishing a database connection. This either means that the username and password information in your `wp-config.php` file is incorrect or that contact with the database server at `db` could 
  - (app: app_multisite): SKIPPED - multisite, handle manually
  - (app: app_nopublic): SKIPPED - no public_html
  - (app: app_notwp): SKIPPED - not WordPress
  - https://app_soleadmin.test (app: app_soleadmin): LAST ADMIN - REVIEW REQUIRED - only administrator on this site
  - https://app_usertaken.test (app: app_usertaken): EMAIL MISMATCH - REVIEW REQUIRED - username exists with a different email

DRY RUN: no changes were made.
```

### 5. Disable: live on the two sites

```text
EXECUTE: disable logan.irish <logan.irish@webfor.com> server=testsrv
Applications to process: 2
Log: /tmp/wwu-logs/20261007-204733_testsrv_disable.log

EXECUTE RESULTS: disable logan.irish <logan.irish@webfor.com> server=testsrv
SITE | WP | USER EXISTS | ROLE | ACTION | RESULT | WARNINGS
https://app_a.test (app: app_a) | Yes | Yes | administrator | DISABLE | DISABLED - roles removed: administrator; email neutralised | -
https://app_b.test (app: app_b) | Yes | Yes | administrator | DISABLE | DISABLED - roles removed: administrator; email neutralised | -

Totals:
  DISABLED: 2
  Applications processed: 2
```

### 6. Restore: live

```text
EXECUTE: restore logan.irish <logan.irish@webfor.com> server=testsrv
Applications to process: 2
Log: /tmp/wwu-logs/20261007-204738_testsrv_restore.log

EXECUTE RESULTS: restore logan.irish <logan.irish@webfor.com> server=testsrv
SITE | WP | USER EXISTS | ROLE | ACTION | RESULT | WARNINGS
https://app_a.test (app: app_a) | Yes | Yes | - | RESTORE | RESTORED - roles: administrator | password stays unusable; employee must use Lost your password
https://app_b.test (app: app_b) | Yes | Yes | - | RESTORE | RESTORED - roles: administrator | password stays unusable; employee must use Lost your password

Totals:
  RESTORED: 2
  Applications processed: 2
```

