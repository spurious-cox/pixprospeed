"""Everything that talks to Pixelmator Pro.

Copyright (c) 2026 Tim McCoy. All rights reserved.
Developed with assistance from Claude (Anthropic).

All of it goes through `osascript`. Two rules learned the hard way:

* Target Pixelmator by BUNDLE PATH, never by name and no longer by id.
  Apple's Creator Studio rebrand made `tell application "Pixelmator Pro"`
  resolve to Creator Studio instead of Tim's own copy; and several copies
  of one build share an id, so an id cannot pick between two running
  processes either. See target().

* Never activate Pixelmator from here. The panel is a nonactivating
  floating window; stealing the front-app slot would defeat the point.
"""

import os
import shutil
import subprocess
import tempfile

from AppKit import NSWorkspace

# Both Pixelmator builds are candidates. Pinning to one meant a document
# open in the other read as "no document" -- the panel was truthfully
# reporting on an app the user wasn't looking at.
BUNDLE_IDS = ("com.apple.pixelmator", "com.pixelmatorteam.pixelmator.x")


def target():
    """Bundle PATH of the Pixelmator build to drive, or "" if none qualifies.

    A path, not a bundle id. Several COPIES of one build can be installed
    and copies share an identifier, so `tell application id` cannot tell two
    such processes apart: it addresses whichever copy LaunchServices prefers
    and LAUNCHES that one if it is not running, then fails on the empty
    instance with "Can't get document 1 ... Invalid index (-1719)".

    NSRunningApplication gives each running process its own bundleURL, which
    is what distinguishes identical copies. Nothing here depends on the app's
    name or location, so it works on any Mac.

    Frontmost build wins; otherwise the first running build that has a
    document open. Resolved on every call rather than cached, because the
    panel is long-lived and the user can switch builds under it.
    """
    running = []
    for app in NSWorkspace.sharedWorkspace().runningApplications():
        if app.bundleIdentifier() not in BUNDLE_IDS:
            continue
        url = app.bundleURL()
        if url is None:
            continue
        running.append((bool(app.isActive()), str(url.path())))
    if not running:
        return ""

    for want_front in (True, False):
        for is_front, path in running:
            if is_front != want_front:
                continue
            if want_front:
                return path
            p = subprocess.run(
                ["osascript", "-e",
                 'tell application "%s" to get (count documents) > 0' % path],
                capture_output=True, text=True)
            if p.stdout.strip() == "true":
                return path
    return running[0][1]

# Sentinel that cannot appear in a layer name, used to split osascript
# output into fields. Layer names may contain almost anything else.
SEP = "\x1f"


def _osascript(script, args=None, timeout=90):
    """Run an AppleScript source string. Returns (ok, output_text)."""
    cmd = ["osascript", "-e", script]
    if args:
        cmd.extend(str(a) for a in args)
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return False, "Pixelmator did not respond."
    if p.returncode != 0:
        return False, (p.stderr or "").strip() or "AppleScript error"
    return True, p.stdout.strip()


def is_running():
    """True if a Pixelmator Pro instance is up.

    Checked before anything else so the panel never cold-launches
    Pixelmator just because it polled for the selected layer.
    """
    return target() != ""


def selected_layer():
    """Describe the single selected layer.

    Returns a dict with name/index/rotation/kind/width/height, or a dict
    with only 'error' explaining why there isn't one.

    width and height come back with their sign intact — a FLIPPED layer
    reports negative values. Callers must abs() before doing arithmetic.
    """
    app_path = target()
    if not app_path:
        return {"error": "Pixelmator Pro is not running."}

    script = '''
    tell application "%s"
        if (count documents) = 0 then return "ERR%sNo document is open."
        tell front document
            if (count selected layers) = 0 then return "ERR%sNo layer is selected."
            if (count selected layers) > 1 then return "ERR%sSelect just one layer."
            set L to current layer
            set r to 0
            try
                set r to rotation of L
            end try
            -- A nested layer's index is relative to its GROUP; every layer
            -- operation is document-level, so building from one would
            -- silently target the wrong top-level layer.
            set nested to "0"
            try
                if class of (parent of L) is group layer then set nested to "1"
            end try
            return "OK%s" & (name of L) & "%s" & (index of L) & "%s" & r & ¬
                "%s" & ((class of L) as text) & "%s" & (width of L) & "%s" & (height of L) & "%s" & nested
        end tell
    end tell
    ''' % (app_path, SEP, SEP, SEP, SEP, SEP, SEP, SEP, SEP, SEP, SEP)

    ok, out = _osascript(script, timeout=15)
    if not ok:
        return {"error": "Could not reach Pixelmator Pro."}
    parts = out.split(SEP)
    if not parts or parts[0] != "OK":
        return {"error": parts[1] if len(parts) > 1 else "Unknown Pixelmator error."}
    try:
        return {
            "name": parts[1],
            "index": int(float(parts[2])),
            "rotation": float(parts[3]),
            "kind": parts[4],
            "width": float(parts[5]),
            "height": float(parts[6]),
            "nested": parts[7] == "1",
        }
    except (IndexError, ValueError):
        return {"error": "Could not read the selected layer."}


def solo_export(layer_index, out_path):
    """Export just this layer to a PNG, then restore every layer's visibility.

    Verified safe on a live document: visibility is restored in a block
    OUTSIDE the try that hides and exports, so a failure part-way can
    never leave the document soloed. Also verified that setting `visible`
    creates NO undo entries, so measuring does not pollute undo history.

    `export` needs a POSIX file object — passing a bare path string fails.
    """
    app_path = target()
    if not app_path:
        return False

    try:
        os.remove(out_path)
    except OSError:
        pass

    script = '''
    on run argv
        set expPath to item 1 of argv
        set layerIdx to (item 2 of argv) as number
        tell application "%s"
            if (count documents) = 0 then return "ERR"
            tell front document
                set lc to (count layers)
                set savedVis to {}
                repeat with i from 1 to lc
                    set end of savedVis to (visible of layer i)
                end repeat
            end tell
            set exportOK to false
            try
                tell front document
                    repeat with i from 1 to lc
                        set visible of layer i to (i = layerIdx)
                    end repeat
                end tell
                export front document to (POSIX file expPath) as PNG
                set exportOK to true
            end try
            try
                tell front document
                    repeat with i from 1 to lc
                        set visible of layer i to (item i of savedVis)
                    end repeat
                end tell
            end try
            if exportOK then
                return "OK"
            else
                return "ERR"
            end if
        end tell
    end run
    ''' % app_path

    ok, out = _osascript(script, [out_path, layer_index], timeout=60)
    return ok and out == "OK" and os.path.exists(out_path)


def footprint(layer_index):
    """(width, height) of what a layer actually RENDERS, in document pixels.

    Solo-exports the layer and measures the opaque bounds. Returns (0, 0) if
    anything fails, which the engine treats as "fall back to width of layer".
    """
    from . import detect
    png = os.path.join(tempfile.gettempdir(), "pixprospeed_footprint.png")
    if not solo_export(layer_index, png):
        return (0, 0)
    try:
        return detect.footprint(png)
    finally:
        try:
            os.remove(png)
        except OSError:
            pass


def run_engine(engine_path, direction, distance, subimages, remove_bg,
               foot_w=0, foot_h=0):
    """Build the speed trail. Returns (ok, message).

    The engine is a compiled .scpt shipped inside the app bundle; it
    contains the layer-building logic and never opens a dialog, because
    a dialog would block with the panel unable to dismiss it.
    """
    if not os.path.exists(engine_path):
        return False, "The build engine is missing from the app bundle."

    # Run a COPY, never the original.
    #
    # engine.scpt declares script properties (smearDensity, ghostStartBlur,
    # ...). AppleScript persists property state back into a compiled .scpt
    # when osascript runs it, so running the engine in place REWROTE it
    # inside the signed bundle -- the file grew 50,460 -> 62,042 bytes and
    # `spctl` then reported "a sealed resource is missing or invalid".
    # Every build was valid until the first Create Speed and broken after.
    # A throwaway copy absorbs the write and the bundle stays sealed.
    scratch = os.path.join(tempfile.gettempdir(), "pixprospeed_engine.scpt")
    try:
        shutil.copy2(engine_path, scratch)
        engine_path = scratch
    except OSError:
        pass  # fall back to running in place rather than failing the build

    app_path = target()
    if not app_path:
        return False, "Pixelmator Pro is not running."

    # The engine takes the app PATH as its 5th argument rather than
    # resolving it again -- one decision, made here, for the whole run.
    cmd = ["osascript", engine_path,
           str(direction), str(int(round(distance))),
           str(int(subimages)), "1" if remove_bg else "0", app_path,
           str(int(foot_w)), str(int(foot_h))]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    except subprocess.TimeoutExpired:
        return False, "The build took too long and was abandoned."

    out = (p.stdout or "").strip()
    if p.returncode != 0:
        return False, (p.stderr or "").strip().splitlines()[-1] if p.stderr else "Build failed."
    if out.startswith("OK"):
        return True, out[2:].strip()
    if out.startswith("ERR"):
        return False, out[3:].strip()
    return False, out or "The engine returned nothing."
