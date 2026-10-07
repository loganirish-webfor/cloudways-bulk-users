FX_ROOT=/fixtures/applications
CORE=/fixtures/.core
SNAP=/fixtures/snap
LOGS=/tmp/wwu-logs
DBH="${DB_HOST:-db}"
DBP="${DB_ROOT_PASSWORD:-sandbox-root}"
APPS_WP="app_a app_b app_exists app_emailtaken app_usertaken app_soleadmin"

ADD=(add --username logan.irish --email logan.irish@webfor.com --first-name Logan --last-name Irish --display-name "Logan Irish")
DIS=(disable --username logan.irish --email logan.irish@webfor.com)
RST=(restore --username logan.irish --email logan.irish@webfor.com)

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
  fwp app_exists user create logan.irish logan.irish@webfor.com --role=administrator \
    --first_name=Logan --last_name=Irish --porcelain >/dev/null
  fx_install app_emailtaken admin admin@client-d.test
  fwp app_emailtaken user create someone logan.irish@webfor.com --role=editor --porcelain >/dev/null
  fx_install app_usertaken admin admin@client-e.test
  fwp app_usertaken user create logan.irish other@client-e.test --role=editor --porcelain >/dev/null
  fx_install app_soleadmin logan.irish logan.irish@webfor.com
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
  # WP 7.x stores app passwords with a fast hash wp_check_password() cannot verify; use core's own check.
  WWU_L="$2" WWU_PW="$3" fwp "$1" eval 'add_filter( "application_password_is_api_request", "__return_true" ); $r = wp_authenticate_application_password( null, getenv( "WWU_L" ), getenv( "WWU_PW" ) ); echo ( $r instanceof WP_User ) ? "yes" : "no";' 2>/dev/null
}
