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

SLOT="${1:?usage: $0 <slot>   e.g. 0, 1, or 2}"

JACKD_LIST=$(jackd -d coreaudio -l 2>&1 || true)
POTATO_DEV=$(printf '%s\n' "$JACKD_LIST" | awk -F"'" '$4 == "Potato" {print $6; exit}')
if [[ -z "$POTATO_DEV" ]]; then
    echo "could not find coreaudio device named 'Potato'. jackd -l output:" >&2
    echo "$JACKD_LIST" >&2
    exit 1
fi
echo "Potato -> $POTATO_DEV"

jackd -d coreaudio -d "$POTATO_DEV" &
JACKD_PID=$!

sleep 1

CHEESE_IP="$(dscacheutil -q host -a name cheese.local | awk '/^ip_address:/ {print $2; exit}')"
: "${CHEESE_IP:?failed to resolve cheese.local}"
echo "cheese.local -> $CHEESE_IP"

jacktrip -C "$CHEESE_IP" -K "$SLOT" -n 1 &
JACKTRIP_PID=$!

sleep 1

./scripts/client-autopatch.py &
AUTOPATCH_PID=$!

sleep 1

osascript -e "set Volume 4"

kb_device=$(chuck --probe 2>&1 | awk '/keyboard/{kb=1} kb && /Apple Internal Keyboard/{gsub(/[][]/, "", $2); print $2; exit}')

CHUCK_PID=
start_chuck() {
    chuck --adc:"Apple Inc.: Potato" --dac:"Apple Inc.: Potato" -c28 client.ck:${SLOT}:cheese.local:${kb_device} &
    CHUCK_PID=$!
}

trap 'kill ${CHUCK_PID:-} $AUTOPATCH_PID $JACKTRIP_PID $JACKD_PID 2>/dev/null; networksetup -setairportpower en0 on' EXIT

# run chuck in background; press 'r' to restart, 'q' to quit (jacktrip/jackd stay up)
start_chuck
echo "[client] press 'r' to restart chuck, 'q' to quit"
while IFS= read -rsn1 key; do
    case "$key" in
        r)
            echo "[client] restarting chuck..."
            kill "$CHUCK_PID" 2>/dev/null || true
            wait "$CHUCK_PID" 2>/dev/null || true
            start_chuck
            ;;
        q)
            echo "[client] quitting..."
            break
            ;;
    esac
done
