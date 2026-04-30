#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "JACK-Client>=0.5.4",
# ]
# ///
"""Patch local JackTrip client:
system:capture_27 -> <jacktrip>:send_1
<jacktrip>:receive_1 -> system:playback_1
"""

import jack
import time

CAPTURE = "system:capture_27"
PLAYBACK = "system:playback_1"

client = jack.Client("client-autopatch", no_start_server=True)


def find_jacktrip_ports():
    """Return (send_port, receive_port) once both exist, else (None, None)."""
    send = recv = None
    for p in client.get_ports():
        if p.name.endswith(":send_1") and not p.name.startswith("system:"):
            send = p.name
        elif p.name.endswith(":receive_1") and not p.name.startswith("system:"):
            recv = p.name
    return send, recv


def try_connect(src, dst):
    try:
        client.connect(src, dst)
        print(f"  {src} -> {dst}", flush=True)
    except jack.JackError as e:
        if "already" not in str(e).lower():
            print(f"  failed {src} -> {dst}: {e}", flush=True)


def patch():
    send, recv = find_jacktrip_ports()
    if not (send and recv):
        return False
    try_connect(CAPTURE, send)
    try_connect(recv, PLAYBACK)
    return True


def on_port(port, register):
    if register and (port.name.endswith(":send_1") or port.name.endswith(":receive_1")):
        time.sleep(0.05)  # let the sibling port register too
        patch()


client.set_port_registration_callback(on_port)
client.activate()

# in case jacktrip's ports already exist when we start
patch()

print("client autopatcher running. ctrl-c to quit.", flush=True)
try:
    while True:
        time.sleep(3600)
except KeyboardInterrupt:
    print()
