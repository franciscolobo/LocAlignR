#!/usr/bin/env bash
set -euo pipefail

# Fail if any tracked file contains CRLF
bad=$(git grep -IUl $'\r' -- . ':!*.png' ':!*.jpg' ':!*.pdf' || true)
if [[ -n "$bad" ]]; then
  echo "CRLF detected in:"
  echo "$bad"
  exit 1
fi
