#!/usr/bin/env bash
set -euo pipefail

SLOT="${1:?usage: $0 <slot>   e.g. 0, 1, or 2}"

jackd -d coreaudio -d '~:AMS2_Aggregate:0' &
JACKD_PID=$!

sleep 2

CHEESE_IP="$(dscacheutil -q host -a name cheese.local | awk '/^ip_address:/ {print $2; exit}')"
: "${CHEESE_IP:?failed to resolve cheese.local}"
echo "cheese.local -> $CHEESE_IP"

jacktrip -C "$CHEESE_IP" -K "$SLOT" -n 1 &
JACKTRIP_PID=$!

sleep 2

trap 'kill $JACKTRIP_PID $JACKD_PID 2>/dev/null' EXIT
./client-autopatch.py
