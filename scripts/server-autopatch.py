#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["JACK-Client>=0.5.4"]
# ///
"""Auto-patch JackTrip clients by their declared slot name (0, 1, 2, ...)."""

import jack
import queue
import re
import threading
import time

SLOTS = [
    ("system:playback_1", "system:capture_9"),
    ("system:playback_2", "system:capture_10"),
    ("system:playback_3", "system:capture_11"),
]
JT_RE = re.compile(r"^(\d+):(send_1|receive_1)$")

client = jack.Client("jacktrip-autopatch", no_start_server=True)
work = queue.Queue()


def try_connect(src, dst):
    try:
        client.connect(src, dst)
        print(f"  {src} -> {dst}", flush=True)
    except jack.JackError as e:
        if "already" not in str(e).lower():
            print(f"  failed {src} -> {dst}: {e}", flush=True)


def patch_slot(slot):
    if not (0 <= slot < len(SLOTS)):
        print(f"  slot {slot} out of range (have {len(SLOTS)} slots)", flush=True)
        return
    playback, capture = SLOTS[slot]
    try_connect(f"{slot}:receive_1", playback)
    try_connect(capture, f"{slot}:send_1")


def worker():
    while True:
        slot = work.get()
        time.sleep(0.05)  # let sibling port register too
        patch_slot(slot)


def on_port(port, register):
    if not register:
        return
    m = JT_RE.match(port.name)
    if not m:
        return
    # never call jack server functions from the notification thread
    work.put(int(m.group(1)))


threading.Thread(target=worker, daemon=True).start()
client.set_port_registration_callback(on_port)
client.activate()

# patch any clients already present at startup
for p in client.get_ports():
    m = JT_RE.match(p.name)
    if m:
        work.put(int(m.group(1)))

print("autopatcher running. ctrl-c to quit.", flush=True)
try:
    while True:
        time.sleep(3600)
except KeyboardInterrupt:
    print()
