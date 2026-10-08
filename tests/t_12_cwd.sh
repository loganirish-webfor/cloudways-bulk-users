# Cloudways' wp-config.php loads wp-salt.php by a RELATIVE path (require('wp-salt.php')),
# which only resolves when the current folder is the site root. Found on two live
# servers. The tool must work no matter which folder it is started from.
fixtures_reset
A="$FX_ROOT/app_a/public_html"
cp "$A/wp-config.php" "$A/wp-config.php.orig"
printf '<?php\n// stands in for the salts file\n' > "$A/wp-salt.php"
sed -i '1a require("wp-salt.php");' "$A/wp-config.php"

# Precondition: the relative require really does break WP-CLI when run from elsewhere.
here="$(pwd)"
cd /tmp
wp --path="$A" --skip-plugins --skip-themes core is-installed >/dev/null 2>&1
assert_eq 255 "$?" "setup: plain wp from another folder hits the relative require"
cd "$A" && wp --skip-plugins --skip-themes core is-installed >/dev/null 2>&1
assert_eq 0 "$?" "setup: the same wp from inside the site folder works"

# The tool, started from an unrelated folder.
cd /tmp
run_tool add --username jane.doe --email jane.doe@webfor.com --first-name Jane --last-name Doe --display-name "Jane Doe" --sites app_a
cd "$here"
assert_eq "WOULD CREATE" "$(status_of app_a)" "relative wp-salt.php config: tool still reads the site"
assert_eq 0 "$RC" "relative wp-salt.php config: exit 0"

mv "$A/wp-config.php.orig" "$A/wp-config.php"
rm -f "$A/wp-salt.php"
