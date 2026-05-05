#!/usr/bin/env bash
set -euo pipefail

SLOT="${1:?usage: $0 <slot>   e.g. 0, 1, or 2}"

jackd -d coreaudio -d '~:AMS2_Aggregate:0' &
JACKD_PID=$!

sleep 2

jacktrip -C cheese.local -J "$SLOT" &
JACKTRIP_PID=$!

sleep 2

trap 'kill $JACKTRIP_PID $JACKD_PID 2>/dev/null' EXIT
./client-autopatch.py
