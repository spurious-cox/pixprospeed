"""Saved settings, shared with the PixProSpeed applet.

Copyright (c) 2026 Tim McCoy. All rights reserved.
Developed with assistance from Claude (Anthropic).

Everything lives in ~/.pixprospeed_defaults.plist and is read and written
through the `defaults` CLI rather than plistlib. That is deliberate: the
applet uses `defaults`, and cfprefsd caches the file, so a process that
edits the plist directly can be silently overwritten by the cached copy.
Going through `defaults` in both places keeps them in step.

Besides the four shared settings there is a per-layer flip memory. The
nose/tail call on car-like silhouettes is close to a coin toss, so rather
than guess better, the panel remembers which way the user corrected a
given layer and applies that correction next time.
"""

import subprocess

DOMAIN = "$HOME/.pixprospeed_defaults"

DEFAULTS = {
    "direction": "335",
    "distance": "200",
    "subimages": "3",
    "removebg": "0",
}


def _read(key):
    p = subprocess.run("defaults read %s %s 2>/dev/null" % (DOMAIN, _quote(key)),
                       shell=True, capture_output=True, text=True)
    return p.stdout.strip() if p.returncode == 0 else None


def _write(key, value):
    subprocess.run("defaults write %s %s %s" % (DOMAIN, _quote(key), _quote(str(value))),
                   shell=True, capture_output=True, text=True)


def _delete(key):
    subprocess.run("defaults delete %s %s 2>/dev/null" % (DOMAIN, _quote(key)),
                   shell=True, capture_output=True, text=True)


def _quote(s):
    """Single-quote for the shell. Layer names can contain anything."""
    return "'" + str(s).replace("'", "'\\''") + "'"


def get(key):
    return _read(key) or DEFAULTS.get(key, "")


def set_settings(direction, distance, subimages, remove_bg):
    _write("direction", direction)
    _write("distance", distance)
    _write("subimages", subimages)
    _write("removebg", "1" if remove_bg else "0")


def get_remove_bg():
    return get("removebg") == "1"


# ── Per-layer flip memory ────────────────────────────────────────────

def _flip_key(layer_name):
    return "flip:" + layer_name


def remembered_flip(layer_name):
    """True if the user has corrected this layer's direction before."""
    if not layer_name:
        return False
    return _read(_flip_key(layer_name)) == "1"


def remember_flip(layer_name, flipped):
    """Store — or clear — the correction for this layer name.

    Keyed by NAME, not index: indices shift constantly as layers are
    added and grouped, but a car layer stays called the same thing.
    Flipping twice returns to the original, so the memory is cleared
    rather than left holding a correction the user has undone.
    """
    if not layer_name:
        return
    if flipped:
        _write(_flip_key(layer_name), "1")
    else:
        _delete(_flip_key(layer_name))


def forget_all_flips():
    p = subprocess.run("defaults read %s 2>/dev/null" % DOMAIN,
                       shell=True, capture_output=True, text=True)
    count = 0
    for line in p.stdout.splitlines():
        line = line.strip()
        if line.startswith('"flip:') or line.startswith("flip:"):
            key = line.split("=")[0].strip().strip('"')
            _delete(key)
            count += 1
    return count
