PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; }
assert_eq() { # EXPECTED ACTUAL LABEL
  if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (expected '$1', got '$2')"; fi
}
assert_contains() { # HAYSTACK NEEDLE LABEL
  case "$1" in *"$2"*) ok "$3" ;; *) bad "$3 (missing '$2')" ;; esac
}
assert_not_contains() { # HAYSTACK NEEDLE LABEL
  case "$1" in *"$2"*) bad "$3 (found '$2')" ;; *) ok "$3" ;; esac
}
assert_summary() {
  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ]
}
