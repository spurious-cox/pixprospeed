=============================================================================
 PixProSpeed — Motion / Speed Streak for Pixelmator Pro
=============================================================================

A floating panel that stays on screen beside Pixelmator Pro. Pick a layer,
set the numbers, hit Create Speed, adjust, go again — no relaunching, no
modal dialog to answer for every trail. It makes a selected layer look like
it is moving fast: a run of discrete "stutter" subimages trailing back along
the direction of travel, wrapped in a soft, fading motion smear that spans
the whole distance. Text, shape and image layers all work.

App:      /Applications/PixProSpeed.app
Project:  ~/My_Applications/PixProSpeed/panel/
Build:    ./build.sh          (compiles the engine, builds, signs, installs)
Settings: ~/.pixprospeed_defaults.plist
Read Me:  embedded in the app bundle (Contents/Resources), so it travels
          with the app and depends on no external path

HISTORY: PixProSpeed began as an AppleScript applet. The applet is RETIRED —
this Python/PyObjC panel is what /Applications/PixProSpeed.app now is. The
old applet source is preserved at ~/My_Applications/PixProSpeed/ alongside
its own archived README, but it is no longer built or installed.

-----------------------------------------------------------------------------
 HOW TO USE IT
-----------------------------------------------------------------------------

    1. Launch /Applications/PixProSpeed.app. The panel floats above
       Pixelmator Pro and never takes focus from it, so leave it up while
       you work.

    2. Select a layer in Pixelmator Pro. The panel picks it up within a
       second, shows its name, and measures a suggested direction; the
       note under the name says where that suggestion came from. Measure
       runs that measurement again by hand.

    3. Set the numbers:
           Direction   degrees, 0 = right, 90 = down
           Distance    pixels, mm or math — how far the trail runs
           Subimages   how many stutter ghosts trail behind
       Switch Remove background on for a photo layer whose subject sits
       on a background.

    4. Click Create Speed. If the trail runs the wrong way, click
       Flip 180° and build again — the correction is remembered for that
       shape.

    5. Adjust and build as often as you like. Dismiss, or closing the
       window, quits.

You get one group named after the source layer. Your original is the bottom
layer of that group, untouched and switched off — delete the group to start
over. Every ghost and the smear keep live effects, so the result can also
be tuned in Pixelmator Pro afterward.


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
 WHAT YOU GET
-----------------------------------------------------------------------------

One group named after the source layer, containing (top to bottom):

    <name>.pixel     sharp pixel copy of the original
    <name> ghost 1   nearest stutter subimage
    ...              each ghost fades and blurs more with distance
    <name> ghost N   farthest stutter subimage
    <name> smear     the merged fading streak over the whole distance
    <name>           the real original layer, untouched and switched OFF

Every ghost keeps its OWN live motion effect and opacity, and the smear
keeps a live motion effect plus a light gaussian — so the whole result
stays tunable in Pixelmator's UI after the fact. Nothing is baked except
the smear's internal step stack. Other layers in the document are left
completely alone.


-----------------------------------------------------------------------------
 HOW THE EFFECT IS BUILT (techniques)
-----------------------------------------------------------------------------

PIXEL SOURCE
    The original layer is duplicated and the duplicate converted into
    pixels; the real original is never modified. One unified path serves
    all layer types with no "convert?" dialog.

TRUE PIXEL POSITION
    After conversion the position is re-read. Text and shape layers report
    position as a baseline / vector origin, but correct trail placement
    needs the rendered pixel bounding-box top-left — which is exactly what
    the converted pixel layer reports.

THE SMEAR: STEP, RAMP, MERGE, THEN BLUR ALONG THE AXIS
    The streak is built from many low-opacity copies stepped along the
    direction vector, with opacity ramping down toward the tail so the
    trail is dense at the object and dissolves at the far end. Those
    copies are merged into one layer, and a motion effect is then applied
    ALONG the travel axis to fuse the discrete steps into a continuous
    streak.

    The step count adapts to the object: the object's own footprint
    measured along the travel axis is divided by smearDensity, so a big
    object gets widely spaced copies and a small one gets tight copies,
    and they always overlap enough to read as one streak. The count is
    clamped to 8-60 so a long distance can't make the build crawl.

SUBIMAGES AS SEPARATE LAYERS
    The ghosts are deliberately NOT merged. Each is its own layer with its
    own opacity and motion-blur radius, both ramping with distance, so any
    individual stutter frame can be nudged, retimed, or deleted after the
    fact.

MOTION-BLUR ANGLE SIGN
    Pixelmator's motion-effect angle is measured counter-clockwise in a
    Y-UP frame, while layer positions are Y-DOWN, so the angle is negated
    before use. That flip lives in one property (motionAngleSign) — if a
    diagonal streak ever blurs across the wrong diagonal, set it to 1.

MERGE POSITION IS USED AS-IS
    The merged smear layer is left exactly where Pixelmator reports it.
    PixProSurround v1.0.9 established that "snapping" a merge result back
    to a computed origin is wrong once a blur is involved: the blur's real
    pixel extent is always larger than the formula predicts.

INDEX BOOKKEEPING
    `duplicate layer X` puts the copy AT index X and pushes the source down
    to X+1, and `current layer` only follows the *selected* layer — so every
    index is computed arithmetically, never read back from the app's
    selection state. The final grouping gathers layers by INDEX rather than
    by name, which avoids the duplicate-name trap that bit PixProEmboss
    2.2.2 when several layers shared a name.

NO DIALOG AT ALL
    The panel replaced the applet's modal prompt entirely: direction,
    distance, subimages and the Remove-background switch are all live
    controls on the floating window, so there is nothing to answer and
    nothing that can open behind the Pixelmator window. (The applet used
    an NSAlert with an NSSwitch accessory view for this, and had to
    activate itself first or the modal opened invisibly. That whole class
    of problem is gone.)

WHICH PIXELMATOR — RESOLVED AT RUN TIME
    Both builds are candidates:
        com.apple.pixelmator             Pixelmator Pro Creator Studio (4.x)
        com.pixelmatorteam.pixelmator.x  Pixelmator Pro (3.x)
    Never the NAME "Pixelmator Pro" — after the Creator Studio rebrand that
    resolves to whichever build macOS picks. pixelmator.target() chooses the
    frontmost build, else the first running build with a document open, on
    every call (the panel is long-lived and you can switch builds under it).
    The chosen bundle id is passed to the engine as its 5th argument, so one
    decision covers the whole build rather than each step guessing again.
    What travels to the engine as its 5th argument is the chosen build's
    PATH, not its bundle id: several copies of one build can be installed,
    and a bundle id cannot say which of them is the one in front.
    Earlier versions were PINNED to 3.x, which meant a document open in
    Creator Studio reported as "no document".

TRIG
    AppleScript has no trig. One Python call resolves the distance
    expression and returns cos/sin together. The Taylor handlers at the
    bottom of the source are an accurate quadrant-reduced fallback only —
    folded into 0-90 degrees first, because an unreduced Taylor series
    evaluated near pi is off by more than 20% and would point the trail
    the wrong way.


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
 TUNING
-----------------------------------------------------------------------------

Properties at the top of the source, all safe to adjust and recompile:

    smearDensity        smear copies per object-extent (higher = smoother,
                        slower)
    minSmearCopies      lower clamp on the smear step count
    maxSmearCopies      upper clamp on the smear step count
    smearStartOpacity   smear opacity % at the object end
    smearEndOpacity     smear opacity % at the tail
    smearSoftness       extra gaussian radius on the smear (0 = motion
                        blur only)
    ghostStartOpacity   opacity % of the nearest ghost
    ghostEndOpacity     opacity % of the farthest ghost
    ghostStartBlur      motion-blur radius of the nearest ghost
    ghostEndBlur        motion-blur radius of the farthest ghost
    motionAngleSign     -1 or 1; flip if a diagonal streak blurs across
                        the wrong diagonal
    maxBlurRadius       Pixelmator's blur sliders top out at 100
    maxSubimages        upper clamp on the subimage count
    shapeMinElongation  long:short ratio a shape needs before it counts as
                        having a direction (1.35; circle/square measure
                        1.00, car 4.22, rocket 3.59)
    noseConfidentMargin below this nose-vs-tail margin the front/back call
                        is flagged as uncertain (0.25)
    opaqueCoverageLimit above this opaque fraction the layer is treated as
                        having no silhouette to measure (0.9)
    rotationSign        1 or -1; how layer rotation maps onto the Direction
                        field. A 180 error needs no change here — that is
                        what the Flip button is for
    debugMode           true writes a step log to
                        ~/Desktop/pixprospeed_debug.txt


-----------------------------------------------------------------------------
 IF THE RESULT IS NOT WHAT YOU EXPECTED
-----------------------------------------------------------------------------

Multiple layers are created in this process — the pixel copy, every ghost,
and the smear. They are collected into one group named after the source
layer.

The BOTTOM layer of that group is your ORIGINAL, untouched, and it is the
only hidden layer in the group. To start over: drag it out of the group to
the top level of the Layers list and make it visible, then delete the group
and run PixProSpeed again with adjusted settings.

Nothing is lost by retrying — the original is never modified.


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

Panel line (this app):

v1.0.0  (2026-08-07)
    First release. Floating nonactivating panel; live layer tracking;
    automatic free-signal direction (remembered flip, then rotation);
    Measure for shape detection; Flip with per-layer memory; Pillow bundled.

v1.0.1  (2026-08-07)
    Refuses a layer that is inside a group — a nested layer's index is
    relative to its GROUP, so building from one silently targets the wrong
    top-level layer. Ghost opacity 45% -> 12%. Engine picked up the motion
    blur angle fix.

v1.0.2  (2026-08-07)
    The panel no longer disappears when you click into Pixelmator. The
    preserved original layer inside the result group is now switched off.

v2.0.0 - v2.2.2
    NOT RECORDED. The panel took over the /Applications/PixProSpeed.app slot
    from the retired applet somewhere in this range, but the individual
    changes were never written down. Reconstruct from git or the source
    header if you need them.

v2.3.0  (2026-08-10)
    Targets whichever Pixelmator build is actually in use instead of being
    pinned to Pixelmator Pro 3.x. The pin was deliberate — it stopped the
    Creator Studio rebrand hijacking the app name — but it also meant a
    document open in Creator Studio read as "no document". pixelmator.target()
    now picks the frontmost build, else any running build with a document,
    and passes that bundle id to the engine as a 5th argument so one decision
    covers the whole run. This README is also now embedded in the bundle.


v2.4.0  (2026-08-10)
    Step spacing now uses the TRUE rendered footprint, measured from pixels,
    instead of `width of layer`. Pixelmator reports a shape layer's PATH
    bounds and a text layer's TYPOGRAPHIC bounds — neither of which is what
    actually gets drawn:

        text layer   reported 666 x 97    actually inked 640 x 52
        shape layer  reported 258 x 239   rasterised   251 x 248
        image layer  reported 795 x 1544  actually      795 x 1543

    Text is the worst case (height overstated by ~46%): line height and side
    bearings are counted as if they were ink. Shapes disagree because a
    stroke renders outside or inside the path. Image layers were always fine.
    Overstating the extent divides into fewer smear copies, spacing them too
    far apart, and the trail develops GAPS along its flanks — worst with an
    outside stroke, which inflates every side.

    detect.footprint() measures the opaque bounds of the solo export at FULL
    resolution (measure_shape thumbnails for its PCA, so it is no use as a
    size), and the panel passes width/height to the engine as arguments 6
    and 7. Skipped when Remove background is on — the export still contains
    the background, so the measurement would cover the whole rectangle; 0
    tells the engine to fall back to `width of layer` as before.

v2.5.0  (2026-08-15)
    Targets Pixelmator by application PATH instead of bundle id. Several
    copies of one build can be installed, and `tell application id` reaches
    whichever the system resolves rather than the copy that is actually in
    front. The engine's 5th argument carries the path that pixelmator.target()
    picked, and the engine addresses it with `tell application <path>`.


v2.5.1  (2026-09-13)
    Documentation release; no change to the effect. Adds a HOW TO USE IT
    section — numbered steps from selecting the layer, through every dialog
    field and its units, to what the result group contains — and fills in a
    version history that had stopped one release short of the shipping build.
    The copy inside the bundle was refreshed with it, so the Read Me button
    shows the same text.

    Also corrects the version the panel announces: main.py still had 2.4.0
    while the bundle said 2.5.0, and a docstring paragraph still described
    measuring as manual-only, which AUTO_MEASURE had already changed.


v2.6.0  (2026-09-13)  — current
    Checks for a newer release, from an Updates… button on the Flip row. It asks GitHub for
    the newest published tag and reports what it finds, offering the releases
    page and the `brew upgrade` line — it never downloads or replaces itself,
    because a running bundle cannot safely overwrite its own files. Versions are
    compared as integers, so 3.10.0 counts as newer than 3.9.0 rather than
    older.


-----------------------------------------------------------------------------
 Copyright (c) 2026 Tim McCoy. All rights reserved.

 Developed with the support of Claude (Anthropic) — design, code, and
 testing assistance.
=============================================================================
