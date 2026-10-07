#!/usr/bin/env bash
# Test double for WP-CLI: injects failures, hangs or a canary password leak, otherwise passes through.
if [ -n "${SHIM_SLEEP:-}" ]; then sleep "$SHIM_SLEEP"; fi
if [ -n "${SHIM_FAIL:-}" ]; then
  case " $* " in
    *" $SHIM_FAIL "*) echo "Error: injected failure for $SHIM_FAIL" >&2; exit 1 ;;
  esac
fi
# Canary leak: mimic WP-CLI printing a password to stdout on reset-password / create.
if [ -n "${SHIM_LEAK:-}" ]; then
  case " $* " in
    *" reset-password "*|*" create "*) echo "Password: CANARY-$SHIM_LEAK" ;;
  esac
fi
exec wp "$@"
