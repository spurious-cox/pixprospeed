=============================================================================
 PixProSpeed — Motion / Speed Streak for Pixelmator Pro
=============================================================================

PixProSpeed is a macOS AppleScript applet that makes a selected layer look
like it is moving fast: a run of discrete "stutter" subimages trailing back
along the direction of travel, wrapped in a soft, fading motion smear that
spans the whole distance. It works with text, shape, and image layers.

Applet:   /Applications/PixProSpeed.app
Source:   ~/My_Applications/PixProSpeed/PixProSpeed.applescript
Defaults: ~/.pixprospeed_defaults.plist


-----------------------------------------------------------------------------
 USING IT
-----------------------------------------------------------------------------

Select ONE layer, run PixProSpeed, and fill in a single dialog:

    direction / distance / subimages          e.g.   335 / 1690 / 3

DIRECTION
    Degrees, describing the direction the object CAME FROM — the trail is
    laid out toward that angle while the object itself stays put.

            0 = right              90 = down 
          180 = left               270 = up
         45 = lower-right          135 = lower-left
        225 = upper-left           315 = upper-right

    So 335 puts the trail out to the right and slightly up.

    NOTE: this is NOT the same convention as PixProShadow, which uses
    0 = left. PixProSpeed uses 0 = right so the number reads as an
    ordinary screen direction.

    The field ARRIVES already filled in with a direction measured from
    the selected layer (v1.2.0). The dialog names the layer it measured
    and says how it got the number, so a prefilled value is never an
    unexplained figure in a box. Overtype it whenever you disagree.

    Type  auto  to re-measure and see the full reasoning, with a
    Use / Flip / Enter-manually choice. See AUTOMATIC DIRECTION below.

    Distance and subimages still come from the saved plist — those have
    nothing to do with the layer.

DISTANCE
    How far the trail reaches. Accepts plain pixels (200), millimetres
    (5mm), or a math expression (72/25.4*5, 5mm+10, 25*2).

SUBIMAGES
    How many discrete stutter ghosts to place inside that distance
    (0-24; 0 gives the smear alone). Ghost i lands at i/(N+1) of the
    distance, so the ghosts sit evenly INSIDE the run with clear air at
    both ends — the object holds the near end, and the smear tapers past
    the last ghost into the far end.

REMOVE BACKGROUND (toggle switch on the dialog)
    If the source layer is a photo with an opaque background, the streak
    would smear the whole rectangle instead of the subject. This toggle
    runs Pixelmator's ML background removal on the pixel COPY first. The
    real original is never touched either way. Leave it OFF for a layer
    that is already cut out — it can eat into the subject. The setting is
    remembered between runs.


-----------------------------------------------------------------------------
 AUTOMATIC DIRECTION  (type "auto" in the direction field)
-----------------------------------------------------------------------------

Two detectors are tried in order. Whatever they conclude is offered as a
SUGGESTION with three buttons — Use it, Flip it 180 degrees, or Enter
manually. Nothing is applied without that confirmation.

1. SHAPE — for anything with an obvious long axis: cars, rockets, arrows,
   planes. The layer is soloed (every other layer hidden), the document is
   exported to a temp PNG, and the principal axis of its opaque pixels is
   computed from the alpha channel. Visibility is always restored, even if
   the export fails. Measured on real artwork:

        circle  1.00 : 1        square  1.00 : 1     <- no usable axis
        car     4.22 : 1        rocket  3.59 : 1     <- usable

   so shapeMinElongation (1.35) separates them cleanly.

2. ROTATION — for round or featureless objects, which have no long axis at
   all. The layer's own "rotation" property is read instead: rotate the
   layer to point it where it is going and auto will pick that up. Rotation
   is taken as the Direction value directly, in the same sense — calibrated
   against a rotated Circle layer reading 323 in a document whose intended
   direction was 335.

WHAT IT CANNOT DO

   PCA finds an AXIS, not an arrow — 358 and 178 are the same line to it.
   Which end is the FRONT is decided separately, by taking the narrower end
   of the silhouette as the nose. That is decisive on a rocket (margin
   0.63) but nearly a coin toss on a car (margin ~0.10): two renderings of
   the same car produced opposite answers. So a low margin is reported in
   the confirmation dialog as "which end is the front is uncertain" rather
   than being quietly presented as fact. That is what the Flip button is
   for, and on car-like shapes expect to need it about half the time.

   The long axis equals the direction of travel only for things that move
   nose-first. A running figure is tall but travels sideways — shape
   detection would confidently report "vertical".

   A photo layer with an opaque background has no silhouette to measure.
   Rather than guess, detection says so and suggests switching on Remove
   background and running auto again.

   Detection needs python3 with the Pillow imaging library. If that is
   missing, auto reports it and you type an angle instead; nothing else in
   the app depends on Pillow.


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

A REAL TOGGLE IN THE DIALOG
    `display dialog` cannot host a checkbox, so the prompt is an NSAlert
    with an accessory view holding the text field and a genuine NSSwitch.
    The applet activates itself before running the alert — otherwise the
    modal opens BEHIND the Pixelmator window and blocks with nothing
    visible on screen. If the AppKit path ever fails, the script falls
    back automatically to a plain three-button dialog offering the same
    choice.

BOUND BY BUNDLE ID
    The script targets `application id "com.pixelmatorteam.pixelmator.x"`,
    not the name "Pixelmator Pro". After Apple's Creator Studio rebrand,
    name resolution points at Pixelmator Pro Creator Studio
    (com.apple.pixelmator) instead.

TRIG
    AppleScript has no trig. One Python call resolves the distance
    expression and returns cos/sin together. The Taylor handlers at the
    bottom of the source are an accurate quadrant-reduced fallback only —
    folded into 0-90 degrees first, because an unreduced Taylor series
    evaluated near pi is off by more than 20% and would point the trail
    the wrong way.


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
 REBUILD AFTER EDITING THE SOURCE
-----------------------------------------------------------------------------

    osacompile -o /tmp/main.scpt PixProSpeed.applescript
    cp /tmp/main.scpt /Applications/PixProSpeed.app/Contents/Resources/Scripts/main.scpt
    codesign --force --deep --timestamp \
        --sign "6448B80DAC9E6F49363B3961E611B3649CD330DD" \
        /Applications/PixProSpeed.app

Swapping main.scpt PRESERVES the Info.plist version keys. A full
from-scratch `osacompile -o PixProSpeed.app` regenerates Info.plist and
DROPS CFBundleShortVersionString / CFBundleVersion / CFBundleGetInfoString /
NSHumanReadableCopyright — re-add them, then re-sign (editing Info.plist
invalidates the signature).

Sign by cert HASH, never by name: an expired 2023 certificate carries an
identical name. Re-signing resets TCC, so the "wants to control Pixelmator
Pro" automation prompt reappears once.


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
 VERSION HISTORY
-----------------------------------------------------------------------------

v1.0.0  (2026-08-07)
    First release. Direction / distance / subimages prompt with an NSSwitch
    Remove-background toggle; separate live ghost layers; merged fading
    smear carrying a live motion effect plus gaussian; results grouped
    under the source layer name with the untouched original at the bottom.

v1.0.1  (2026-08-07)
    FIXED: the prompt often never appeared — the applet just bounced in
    the Dock. v1.0.0 activated Pixelmator BEFORE showing the dialog, so
    the applet's own modal opened behind Pixelmator's window. Whether you
    actually saw it depended on what that window happened to cover, which
    is why it worked sometimes and not others.

    The script is now split into three phases: a pre-flight pass that
    reads the document WITHOUT activating anything, the prompt while this
    applet is still frontmost, and only then Pixelmator is activated for
    the layer work. All pre-flight warnings are raised by the applet
    itself rather than from inside a `tell application "Pixelmator Pro"`
    block, for the same reason. Three extra guards inside the prompt:
    `tell me to activate`, a 0.3s delay so the activation is processed
    before runModal blocks the event loop, and a floating window level
    on the alert. No change to the effect-building code.

    Also added the app icon, built from Tim's own red-circle speed-trail
    artwork — which PixProSpeed itself generated.

v1.1.0  (2026-08-07)
    Automatic direction detection. Type "auto" in the direction field and
    the applet measures the layer and SUGGESTS an angle, which you accept,
    flip, or override. Shape analysis (principal axis of the alpha channel,
    via a solo export) handles cars and rockets; layer rotation handles
    round objects that have no axis. See AUTOMATIC DIRECTION above for what
    it can and cannot determine.

    The prompt now runs in a loop, so a bad entry or a detected angle you
    want to edit re-opens the dialog with your values still in it instead
    of dropping out.

    FIXED: a horizontally or vertically flipped layer reports a NEGATIVE
    width or height (Tim's Circle layer reads w=-650). That went straight
    into the object-footprint calculation that sets the smear step count,
    shrinking or inverting it. Both dimensions are now taken as absolute.

    Detector hardening: the exported image is scaled to a fixed size before
    measuring, because an earlier version sub-sampled the raw export and
    gave different answers for the same object in a 2400px document versus
    an 800px one. End width is now a mean half-width (area-based) rather
    than an extreme min-to-max that one stray pixel could swing.

v1.2.0  (2026-08-07)
    The dialog now OPENS with a measured guess already in the direction
    field, rather than the last-used plist number. The selected layer is
    measured before the prompt is shown; distance and subimages still
    come from the plist. The prompt names the layer it measured and
    states how the number was arrived at. Typing "auto" still works and
    re-measures with the full Use / Flip / Enter-manually reasoning.

    Measuring costs one solo + export per run — timed at 0.55s for the
    export and 0.28s for the analysis on a 2400x2400 document, so under
    a second. Verified that toggling a layer's "visible" creates NO undo
    entries in Pixelmator, so measuring does not pollute undo history.

    Handles the selection changing while the dialog is open. The alert
    is app-modal to the applet only, so Pixelmator stays clickable
    behind it. After the dialog returns, the selected layer is
    re-checked; if it moved, the new layer is measured and the prompt
    re-opens instead of building on a stale suggestion.

    Verified on screen: with the Circle layer selected the dialog opened
    reading "Layer: Circle / Direction suggested from the layer's own
    rotation" with 323 prefilled — the Circle's actual rotation — in
    place of the 335 sitting in the plist.


v1.3.0  (2026-08-07)
    FIXED banding running PERPENDICULAR to the trail. Two causes, both
    about the smear's motion blur.

    1. The blur was aimed wrong. motionAngleSign was -1 on the assumption
       that Pixelmator's motion-effect angle is counter-clockwise in a
       Y-up frame. Measured in a throwaway document: a motion effect
       requested at 0 / 45 / 90 renders a smear axis of exactly
       0 / 45 / 90 in SCREEN space (Y down) — the frame this script
       already uses — so the angle passes through unchanged and the sign
       is now 1. At direction 323 the old code aimed the blur at 37 while
       the trail runs along 143: 74 degrees out, near enough
       perpendicular to smear across the trail instead of along it.

    2. The blur could not reach between copies. Radius is
       smearSpacing * 1.5 and Pixelmator caps radius at 100, so distance
       900 gave spacing 112 against a clamped radius of 100 and the
       stepped copies never fused — their edges showed as bands. The copy
       count is now also driven by that limit, so spacing stays under
       100/1.5. maxSmearCopies raised 60 -> 90 to cover long trails at
       the tighter spacing.

v1.3.1  (2026-08-07)
    REFUSES a layer that is inside a group. A nested layer reports an
    "index" relative to its GROUP, while every layer operation here is
    document-level. That either errors outright or — far worse —
    silently builds the trail from whichever top-level layer happens to
    sit at that index. Seen for real: a layer inside a group reported
    index 1, a perfectly valid document index pointing at an unrelated
    group. Detected with

        class of (parent of current layer) is group layer

    comparing the class CONSTANT, never its text form. Drag the layer out
    to the top level, run PixProSpeed, then move the result back.

    Ghost opacity now runs 45% down to 12% (was 70% down to 25%) — at 70%
    the nearest ghost read almost as solid as the object itself.

v1.3.2  (2026-08-07)  — current
    The preserved original layer inside the result group is now switched
    OFF. It is still there and still untouched — hiding it stops it showing
    through the moment the .pixel copy is moved or edited, and being the
    only hidden layer in the group marks which one is the original.


-----------------------------------------------------------------------------
 ICON
-----------------------------------------------------------------------------

Source artwork: PixProSpeedIcon.png (1024px square) and PixProSpeed.icns in
the project folder. Tim's own design: grey background matching the rest of
the PixPro family, "PixPro" / "Speed" set top and bottom, and a speed trail
that PixProSpeed itself generated with v1.3.0.

The same icns is used by PixProSpeedPanel.app (its setup.py points at
../PixProSpeed.icns). macOS clips icons to a rounded squircle, so keep text
inside roughly the middle 80% or its ends get trimmed.

To rebuild the icon from a new square PNG:

    for s in 16 32 128 256 512; do
      sips -z $s $s SRC.png --out ICON.iconset/icon_${s}x${s}.png
      sips -z $((s*2)) $((s*2)) SRC.png --out ICON.iconset/icon_${s}x${s}@2x.png
    done
    iconutil -c icns ICON.iconset -o applet.icns

Then embed it in the bundle:

    cp applet.icns  <App>.app/Contents/Resources/applet.icns
    rm -f           <App>.app/Contents/Resources/Assets.car
    /usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" <App>.app/Contents/Info.plist
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile applet" <App>.app/Contents/Info.plist
    codesign --force --deep --timestamp --sign "<hash>" <App>.app
    lsregister -f <App>.app ; killall Finder

BOTH `Assets.car` AND `CFBundleIconName` must go. Either one silently
overrides CFBundleIconFile, and the custom icon is simply ignored with no
error anywhere.


-----------------------------------------------------------------------------
 Copyright (c) 2026 Tim McCoy. All rights reserved.

 Developed with the support of Claude (Anthropic) — design, code, and
 testing assistance.
=============================================================================
