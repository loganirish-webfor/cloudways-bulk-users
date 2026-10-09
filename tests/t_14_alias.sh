# Cloudways lists every site twice under the apps root: the real folder (random id)
# and a friendly-name symlink to it. Found on a live server (29 of 62 entries were
# symlinks). One site must be processed once, however it is named.
fixtures_reset
ln -s app_a "$FX_ROOT/alias_a"
rows() { awk -F'\t' -v f="$1" '$2 == f' "$TSV" | wc -l | tr -d ' '; }

run_tool "${ADD[@]}" --all
assert_eq "WOULD CREATE" "$(status_of app_a)" "alias: the real folder is processed"
assert_eq "" "$(status_of alias_a)" "alias: the symlink to it is not processed as a second site"
assert_eq 1 "$(rows app_a)" "alias: the site has exactly one row"
assert_contains "$OUT" "Applications processed: 10" "alias: the count is real sites, not folder entries"
assert_contains "$OUT" "alias_a" "alias: the skipped alias is named in the output"
assert_contains "$(cat "${TSV%.tsv}.log")" "alias_a" "alias: the skipped alias is recorded in the log"

run_tool "${ADD[@]}" --sites alias_a,app_a
assert_contains "$OUT" "Applications processed: 1" "alias: --sites naming both the alias and the folder processes the site once"

run_tool "${ADD[@]}" --sites alias_a
assert_eq "WOULD CREATE" "$(status_of alias_a)" "alias: --sites with only the alias still works, under the name given"

run_tool "${ADD[@]}" --all --exclude alias_a
assert_eq "" "$(status_of app_a)" "alias: excluding the alias excludes the site"
assert_eq "" "$(status_of alias_a)" "alias: excluding the alias leaves no alias row"

# A symlink that points outside the apps root is not a duplicate of anything: keep it.
mkdir -p /tmp/wwu-empty-root
ln -s /tmp/wwu-empty-root "$FX_ROOT/link_out"
run_tool "${ADD[@]}" --all
assert_eq SKIPPED "$(status_of link_out)" "alias: a symlink to some other folder is kept (and reported), not hidden"
rm -f "$FX_ROOT/link_out" "$FX_ROOT/alias_a"
