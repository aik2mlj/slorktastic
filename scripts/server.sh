#!/usr/bin/env bash

# turn wifi off
networksetup -setairportpower en0 off
cleanup() {
    echo -e "\nShutting down..."
    networksetup -setairportpower en0 on
    exit 0
}
trap cleanup SIGINT

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

# 3. launch autopatcher in background
./server-autopatch.py &
AUTOPATCH_PID=$!

sleep 2

trap 'kill $AUTOPATCH_PID $JACKTRIP_PID $JACKD_PID 2>/dev/null' EXIT

# 4. run chuck in foreground so ctrl-c stops everything cleanly
chuck --adc:"Existential Audio Inc.: BlackHole 16ch" --dac:"Existential Audio Inc.: BlackHole 16ch" -c16 server.ck

# turn wifi back on
networksetup -setairportpower en0 on
