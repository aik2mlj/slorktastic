#!/usr/bin/env bash
set -euo pipefail

# 1. start jackd
jackd -d coreaudio -d 'BlackHole16ch_UID' &
JACKD_PID=$!

# wait for jackd to be ready (jack_wait blocks until the server responds)
jack_wait -w

# 2. start jacktrip hub server, no auto-patch
jacktrip -S -p5 &
JACKTRIP_PID=$!

# small grace period so jacktrip registers as a client before the patcher starts
sleep 1

# 3. launch autopatcher in foreground so ctrl-c stops everything cleanly
trap 'kill $JACKTRIP_PID $JACKD_PID 2>/dev/null' EXIT
./server-autopatch.py
