#!/usr/bin/env bash
# Test double for WP-CLI: injects failures or hangs, otherwise passes through.
if [ -n "${SHIM_SLEEP:-}" ]; then sleep "$SHIM_SLEEP"; fi
if [ -n "${SHIM_FAIL:-}" ]; then
  case " $* " in
    *" $SHIM_FAIL "*) echo "Error: injected failure for $SHIM_FAIL" >&2; exit 1 ;;
  esac
fi
exec wp "$@"
