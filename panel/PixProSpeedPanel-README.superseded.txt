=============================================================================
 PixProSpeedPanel — persistent floating controls for PixProSpeed
=============================================================================

A floating panel that stays on screen beside Pixelmator Pro. Pick a layer,
set the numbers, hit Create Speed, adjust, go again — no relaunching, no
modal dialog to answer for every trail.

The PixProSpeed applet (/Applications/PixProSpeed.app) still works and is
untouched. This is an alternative front end onto the same effect, not a
replacement, until you decide to retire the applet.

App:      /Applications/PixProSpeedPanel.app
Project:  ~/My_Applications/PixProSpeed/panel/
Build:    ./build.sh          (compiles the engine, builds, signs, installs)
Settings: ~/.pixprospeed_defaults.plist   — SHARED with the applet


-----------------------------------------------------------------------------
 THE PANEL
-----------------------------------------------------------------------------

    Layer:  <name>          the currently selected layer, polled every second
    <note>                  where the direction suggestion came from

    Direction   [   ]  [Measure]      degrees, 0 = right, 90 = down
    Distance    [   ]  px, mm or math
    Subimages   [   ]  stutter ghosts
    (o  ) Remove background

              [ Flip 180° ]
    <status>
    [ Create Speed ]   [ Dismiss ]     green / red

It is LSUIElement — no Dock icon, no menu bar. Dismiss, or closing the
window, quits it. Nothing else makes it go away.

KEEPING IT ON SCREEN took more than the obvious call. A utility panel hides
itself whenever its OWN app is deactivated, and because this app is
LSUIElement and nonactivating it is always deactivated the instant you click
back into Pixelmator — so the panel simply vanished (v1.0.1 and earlier).
setHidesOnDeactivate_(False) alone did NOT fix it. What actually keeps a
palette up across app switches is the collection behaviour:

    NSWindowCollectionBehaviorCanJoinAllSpaces
    | NSWindowCollectionBehaviorFullScreenAuxiliary
    | NSWindowCollectionBehaviorStationary

plus NSStatusWindowLevel rather than NSFloatingWindowLevel, and
setBecomesKeyOnlyIfNeeded_(True) so clicking the panel never takes key focus
away from Pixelmator.

The window is a nonactivating floating panel, so clicking it does NOT pull
focus away from Pixelmator. You can keep working in the document with the
panel in front of you.


COLOURED BUTTONS. setBezelColor_ is the obvious call and it does NOT work
here: the panel is nonactivating, so its buttons always draw in their
inactive state and the tint is discarded. Create Speed and Dismiss are
borderless buttons with the fill drawn on their own layer (background
colour + corner radius) and an attributed black title, which renders the
same whether the panel is active or not. A borderless button also shows no
disabled state of its own, so Create Speed is faded by hand via
layer().setOpacity_() while a build runs.


-----------------------------------------------------------------------------
 HOW THE DIRECTION IS WORKED OUT
-----------------------------------------------------------------------------

AUTO-MEASURE (v2.2.0). Selecting a different layer measures it straight
away — no need to click Measure for each new object. This solos the layer
and exports the document, so the canvas flickers on every selection change;
that was a deliberate trade Tim chose over having to click. Set
AUTO_MEASURE = False at the top of main.py to go back to measuring only on
demand. The Measure button still works either way, for re-measuring after
editing a layer.

Clicking quickly through several layers does not stack up measurements —
the busy flag skips a poll while one is already running.


FREE SIGNALS — applied first, from a single property read:

  * A remembered correction for that layer (see Flip below).
  * The layer's own rotation, for round objects that have no axis.

Both are single property reads. They cost nothing and do not disturb the
document, so the panel applies them the moment the selection changes.

EXPENSIVE SIGNAL — behind the Measure button:

  * Shape detection. The layer is soloed, the document exported to a temp
    PNG, and the principal axis of the opaque pixels computed (PCA on the
    alpha channel). Visibility is always restored afterwards.

Shape detection overrides the free signal whenever the outline has a usable
axis, and falls back to the rotation reading when it does not — which is
what a near-round shape like a heart (1.1 : 1) does.

Measured on real artwork:

    circle  1.00 : 1        square  1.00 : 1      <- no usable axis
    car     4.22 : 1        rocket  3.59 : 1      <- usable

so the 1.35 threshold separates them cleanly. Below it, the panel falls
back to the layer's rotation.


-----------------------------------------------------------------------------
 FLIP, AND WHY IT REMEMBERS
-----------------------------------------------------------------------------

PCA finds an AXIS, not an arrow — 358 and 178 are the same line to it.
Which end is the FRONT is a separate heuristic (narrower end = nose) and on
car-like silhouettes it is close to a coin toss: two renderings of the same
MX-5 gave OPPOSITE answers, margin ~0.10 both times. A rocket scored 0.63
and is decisive.

Rather than guess harder, Flip turns the direction around AND remembers the
correction against the layer's NAME. Next time you select that layer the
correction is applied automatically and the note says so. Flipping twice
clears the memory rather than leaving a correction you have undone.

Keyed by name, not index, because indices shift constantly as layers are
added and grouped — but a car layer stays called the same thing.

The memory lives in the shared plist as "flip:<layer name>" keys.


-----------------------------------------------------------------------------
 ARCHITECTURE
-----------------------------------------------------------------------------

    main.py                  the NSPanel and all its wiring
    pixprospeed/pixelmator.py  everything that talks to Pixelmator, via osascript
    pixprospeed/detect.py      the PCA shape detector (Pillow)
    pixprospeed/state.py       settings + per-layer flip memory
    engine.applescript       the layer-building engine
    engine.scpt              compiled at build time into Resources/

The engine is the layer-building half of PixProSpeed 1.2.2 — the version
whose output was verified on screen — with every dialog and all detection
stripped out. It takes finished numbers:

    osascript engine.scpt <direction> <distance> <subimages> <removebg>

and prints "OK <name>" or "ERR <message>". It never opens a dialog, because
a dialog would block with the panel unable to dismiss it.

Pillow is bundled INSIDE the app, so shape detection no longer depends on a
homebrew python that a brew upgrade can move out from under it.

Settings go through the `defaults` CLI rather than plistlib, because the
applet uses `defaults` and cfprefsd caches the file — a process that edits
the plist directly can be silently overwritten by the cached copy.


-----------------------------------------------------------------------------
 BUILD NOTES (things that will bite on a rebuild)
-----------------------------------------------------------------------------

PyObjC IS A SEPARATE DEPENDENCY. py2app does not pull in the Cocoa bindings.
Without pyobjc-framework-Cocoa the app builds fine and then dies at launch
with "ModuleNotFoundError: No module named 'AppKit'".

PYOBJC BRIDGES EVERY METHOD ON AN NSObject SUBCLASS into an Objective-C
selector. A helper like _label(text, y, ...) becomes a zero-argument
selector and raises BadPrototypeError at class-creation time. Anything that
is not a target/action or delegate callback must be decorated
@objc.python_method. Use objc.super(), not the builtin super().

liblzma.5.dylib CANNOT BE SIGNED AS py2app LEAVES IT. py2app strips its
signature but leaves the LC_CODE_SIGNATURE load command pointing at a blob
that is gone, so codesign reports "main executable failed strict validation"
and then "internal error in Code Signing subsystem" when asked to re-sign.
--remove-signature cannot repair it. build.sh copies the pristine dylib from
/opt/homebrew/opt/xz/lib over the top and restores the install name. Of the
85 nested binaries it is the only one affected.

DO NOT USE codesign --deep. It is deprecated and reports a useless error
when one nested file is the problem. build.sh signs nested binaries
individually, then the bundle.

Sign by cert HASH, never by name: an expired 2023 certificate carries an
identical name. --timestamp is mandatory or the signature dies with the
certificate in Aug 2027.


-----------------------------------------------------------------------------
 VERSION HISTORY
-----------------------------------------------------------------------------

v1.0.0  (2026-08-07)
    First release. Floating nonactivating panel; live layer tracking;
    automatic free-signal direction (remembered flip, then rotation);
    Measure for shape detection; Flip with per-layer memory; shared
    settings with the applet; Pillow bundled.

v1.0.1  (2026-08-07)
    Refuses a layer that is inside a group — a nested layer's index is
    relative to its GROUP, so building from one silently targets the wrong
    top-level layer. Ghost opacity 45% -> 12%. Engine picked up the motion
    blur angle fix.

v1.0.2  (2026-08-07)  — current
    The panel no longer disappears when you click into Pixelmator. See
    KEEPING IT ON SCREEN above. The preserved original layer inside the
    result group is now switched off.


-----------------------------------------------------------------------------
 Copyright (c) 2026 Tim McCoy. All rights reserved.

 Developed with the support of Claude (Anthropic) — design, code, and
 testing assistance.
=============================================================================
