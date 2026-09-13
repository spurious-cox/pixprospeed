use framework "Foundation"
use framework "AppKit"
use scripting additions

-- ============================================================
-- PixProSpeed.applescript
-- Version 1.3.2  (2026-08-07)
--
-- Copyright (c) 2026 Tim McCoy. All rights reserved.
-- Developed with assistance from Claude (Anthropic).
--
-- New in 1.3.2: the preserved original layer inside the result group is
--   now switched OFF. It is still there and still untouched — hiding it
--   stops it showing through when the .pixel copy is moved or edited,
--   and being the only hidden layer in the group marks which one is the
--   original.
--
-- New in 1.3.1: REFUSES a layer that is inside a group, and makes the
--   stutter ghosts fainter.
--
--   A nested layer reports an `index` relative to its GROUP, while every
--   layer operation in this script is document-level. That either errors
--   outright or, when the nested index happens to be a valid top-level
--   index, silently builds the trail from a completely different layer.
--   Seen for real: a layer inside a group reported index 1, which is a
--   perfectly valid document index pointing at an unrelated group.
--   Detected with `class of (parent of current layer) is group layer` —
--   compare the class CONSTANT, never its text form (PixProEmboss 2.2.2).
--
--   Ghost opacity now runs 45% down to 12% (was 70% down to 25%). The
--   nearest ghost at 70% read almost as solid as the object itself.
--
-- New in 1.3.0: FIXED banding running PERPENDICULAR to the trail.
--   Two causes, both about the smear's motion blur.
--
--   1. THE BLUR WAS AIMED WRONG. motionAngleSign was -1 on the
--      assumption that Pixelmator's motion-effect angle is measured
--      counter-clockwise in a Y-UP frame. Measured in a throwaway
--      document: a motion effect requested at 0 / 45 / 90 renders a
--      smear axis of exactly 0 / 45 / 90 in SCREEN space (Y down),
--      which is the frame this script already uses. The angle passes
--      through unchanged, so the sign is now 1. At direction 323 the
--      old code aimed the blur at 37 while the trail runs along 143 —
--      74 degrees out, near enough perpendicular to smear across the
--      trail rather than along it.
--
--   2. THE BLUR COULD NOT REACH BETWEEN COPIES. Radius is
--      smearSpacing * 1.5 and Pixelmator caps radius at 100, so a long
--      distance produced spacing wider than the blur could bridge
--      (distance 900 gave spacing 112 against a clamped radius of 100)
--      and the stepped copies never fused — their edges showed as
--      bands. The copy count is now also driven by that limit, so
--      spacing always stays under 100/1.5. maxSmearCopies raised
--      60 -> 90 to cover long trails at the tighter spacing.
--
-- New in 1.2.2: FIXED space stripping, which had never actually
--   worked. The delimiter was left as " " while the split list was
--   coerced back to text, so the join re-inserted the very spaces the
--   split had just removed. Numbers still coerced fine ("323 " as
--   number = 323), which hid it — but `isAutoKeyword` is an exact
--   match, so "auto / 900" was silently NOT treated as auto.
--   Introduced here by collapsing two statements into one — the same
--   idiom in PixProShadow (line 190) is written correctly and is fine.
--
-- New in 1.2.1: FIXED an endless loop. Typing just `auto` — which the
--   dialog explicitly invites — was rejected because the parser
--   demanded all three slash-separated fields. The error alert then
--   re-opened the same dialog, so retyping `auto` looped forever
--   (Cancel was the only way out). The parse is now tolerant: any
--   field left off keeps the value already in play, so `auto`, `180`,
--   and `180 / 900` are all valid entries.
--
-- New in 1.2.0: THE DIALOG NOW OPENS WITH A MEASURED GUESS ALREADY IN
--   IT. Up to 1.1.0 the direction field was prefilled from the saved
--   plist (the last-used number) and detection only ran if you typed
--   `auto`. Now the selected layer is measured BEFORE the dialog is
--   shown, and the direction field is prefilled with that suggestion;
--   distance and subimages still come from the plist, since those have
--   nothing to do with the layer. The prompt states which layer it
--   measured and how the number was arrived at, so a prefilled value
--   is never an unexplained number in a box. Typing `auto` still
--   works — it re-measures and shows the full reasoning with the
--   Use / Flip / Enter-manually choice.
--
--   Measuring costs one solo + export per run. Verified that toggling
--   a layer's `visible` creates NO undo entries in Pixelmator, so this
--   does not pollute the document's undo history.
--
--   SELECTION CAN CHANGE WHILE THE DIALOG IS OPEN. The alert is
--   app-modal to THIS applet only, so Pixelmator stays clickable
--   behind it. After the dialog returns, the selected layer is
--   re-checked; if it moved, the new layer is measured and the prompt
--   re-opens rather than building on a suggestion for a layer that is
--   no longer selected.
--
-- New in 1.1.0: AUTOMATIC DIRECTION DETECTION. Type `auto` in the
--   direction field and the applet works out which way the object is
--   pointing, then SUGGESTS an angle you can accept, flip, or ignore.
--   It never applies a detected angle without asking.
--
--   Two detectors, tried in order:
--
--   1. SHAPE (for things with an obvious long axis — cars, rockets,
--      arrows, planes). The layer is soloed, exported to a temp PNG,
--      and the principal axis of its opaque pixels is computed
--      (PCA on the alpha channel). Measured on real artwork:
--          circle 1.00 : 1     square 1.00 : 1      <- no usable axis
--          car    4.23 : 1     rocket 3.64 : 1      <- usable
--      so shapeMinElongation gates cleanly between them.
--
--      PCA yields an AXIS, not an arrow — 358 and 178 are identical
--      to it. Which end is the nose is decided by a second pass: the
--      narrower end of the silhouette is taken as the front. That is
--      decisive on a rocket (margin 0.68) but weak on a car (0.12),
--      so a low margin is reported in the confirmation dialog as
--      "which end is uncertain" rather than being hidden.
--
--   2. ROTATION (for round or featureless objects — a ball, a blob,
--      a circle). These have no long axis at all, so the layer's own
--      `rotation` property is used instead: rotate the layer to point
--      it where it is going, and `auto` will read that back.
--
--   Detection reports the direction the object FACES. The Direction
--   field wants where it CAME FROM, so the suggestion is facing+180.
--
--   LIMITS worth knowing: the long axis equals the travel direction
--   only for things that move nose-first. A running figure is tall
--   but travels sideways — shape detection would confidently say
--   "vertical". And a photo layer with an opaque background has no
--   silhouette to measure, so detection reports that instead of
--   guessing (turn on Remove background and rerun, or type an angle).
--
-- New in 1.0.1: FIXED the prompt never appearing (the applet just
--   bounced in the Dock). v1.0.0 called `activate` on Pixelmator
--   BEFORE showing the dialog, which made Pixelmator frontmost and
--   left the applet's own modal stranded behind its window with
--   nothing visible. The script is now split into a pre-flight pass
--   that reads the document WITHOUT activating anything, then the
--   prompt while this applet is still the frontmost app, and only
--   then activates Pixelmator for the layer work. All pre-flight
--   warnings are shown by the applet itself instead of by Pixelmator
--   for the same reason. Belt-and-braces added inside the prompt:
--   `tell me to activate`, a short delay so the activation is
--   processed before the modal blocks the event loop, and a floating
--   window level on the alert.
--
-- Creates a "speed" / motion-streak effect behind a selected
-- layer in Pixelmator Pro. Works with text, shape, and image
-- layers. Sibling of PixProShadow / PixProSurround / PixProEmboss.
--
-- Prompts once for:
--   • Direction  — degrees, the direction the object CAME FROM
--                  (the trail is laid out toward this angle)
--   • Distance   — how far the trail reaches, in pixels
--   • Subimages  — how many discrete "stutter" ghosts to place
--                  inside that distance
--   • Remove background — a toggle switch on the same dialog
--
-- ANGLE CONVENTION (screen angles, NOT PixProShadow's):
--     0 = right    90 = down   180 = left   270 = up
--    45 = lower-right   135 = lower-left
--   225 = upper-left    315 = upper-right
--   e.g. 335 = right and slightly up.
--   NOTE: PixProShadow uses the mirrored convention (0 = left).
--   PixProSpeed deliberately uses 0 = right so the entered angle
--   reads as a normal screen direction.
--
-- Distance field accepts:
--   • Plain number:       200
--   • Millimetres:        5mm
--   • Math expression:    72/25.4*5
--   • Mixed:              5mm+10   or   25*2
--
-- WHAT GETS BUILT (top to bottom inside one group named <name>):
--   <name>.pixel     — sharp pixel copy of the original
--   <name> ghost 1   — nearest stutter subimage  (own opacity + motion blur)
--   ...              — ghosts fade and blur more with distance
--   <name> ghost N   — farthest stutter subimage
--   <name> smear     — one merged, fading streak spanning the WHOLE
--                      distance, carrying a LIVE motion effect (and a
--                      light gaussian) so it stays tunable in the UI
--   <name>           — the real original layer, untouched
--
-- The smear is built by stepping many low-opacity copies of the
-- object along the direction vector, ramping opacity down toward
-- the tail, merging them into one layer, then applying a motion
-- effect ALONG the travel axis to fuse the steps into a streak.
--
-- THE DIALOG: display dialog cannot host a checkbox, so the prompt
-- is an NSAlert with an accessory view holding the text field and a
-- real NSSwitch. If anything in that AppKit path fails the script
-- falls back to a plain three-button display dialog, which offers
-- the same choice as "Remove BG + Speed" vs "Create Speed".
-- ORDER MATTERS: nothing may activate another application before
-- this prompt runs — see the 1.0.1 note above.
--
-- REMOVE BACKGROUND: if the source layer is a photo with an opaque
-- background, the streak would smear the whole rectangle. The toggle
-- runs Pixelmator's ML background removal on the pixel COPY first;
-- the real original is never touched either way. Leave it off for a
-- layer that is already cut out — it can eat into the subject.
-- `remove background` acts on the document's CURRENT layer, so the
-- pixel copy is explicitly selected before it is called.
--
-- INDEX BOOKKEEPING (the fragile part — see PixProShadow notes):
--   `duplicate layer X` puts the copy AT index X and pushes the
--   source down to X+1, so every index is computed arithmetically,
--   never read back from `current layer` (which only follows the
--   *selected* layer).
--   The merged smear layer's position is used EXACTLY as Pixelmator
--   reports it — PixProSurround v1.0.9 proved that "snapping" a
--   merge result back to a computed origin is wrong once a blur is
--   involved, because the blur's real pixel extent is larger than
--   any formula predicts.
--
-- Trig is done in Python (one shell call also resolves the distance
-- expression). AppleScript has no trig; the Taylor handlers at the
-- bottom are an accurate quadrant-reduced fallback only.
--
-- Defaults saved to ~/.pixprospeed_defaults.plist
-- ============================================================

property scriptVersion : "1.3.2"
property debugMode : false

-- ── Direction detection (`auto`) ──────────────────────────────
-- Minimum long-axis : short-axis ratio before a shape is considered
-- to HAVE a direction. Measured: circle/square 1.00, car 4.23,
-- rocket 3.64. Anything under this falls through to layer rotation.
property shapeMinElongation : 1.35
-- Below this nose-vs-tail width margin the front/back call is flagged
-- as uncertain in the confirmation dialog. Rocket 0.68, car 0.12.
property noseConfidentMargin : 0.25
-- A layer this opaque has no silhouette to measure (a photo with its
-- background still on). Reported rather than guessed at.
property opaqueCoverageLimit : 0.9
-- How a layer's `rotation` maps onto the Direction field. CALIBRATED
-- against Tim's rotated Circle layer, which reads rotation = 323 in a
-- document where the direction he wanted was 335 — a 12-degree eyeball
-- difference, so rotation is taken as the Direction value DIRECTLY
-- (same sense, no negation, no 180 offset). Negating it would have
-- given 37, which is 62 degrees out and clearly not what he drew.
-- If rotation ever reads inverted, set this to -1. A 180 error needs
-- no property at all — the confirmation dialog's Flip button covers it.
property rotationSign : 1

-- ── Tuning knobs ──────────────────────────────────────────────
-- Smear copies per object-extent along the travel axis. Higher =
-- smoother streak, slower build.
property smearDensity : 6
property minSmearCopies : 8
property maxSmearCopies : 90
-- Opacity ramp (%) applied to the smear copies before they merge.
property smearStartOpacity : 45
property smearEndOpacity : 2
-- Extra gaussian softness on the merged smear (0 = motion blur only).
property smearSoftness : 6
-- Ghost (subimage) opacity + motion-blur ramps, nearest → farthest.
property ghostStartOpacity : 45
property ghostEndOpacity : 12
property ghostStartBlur : 2
property ghostEndBlur : 20
-- How a screen angle maps onto the motion effect's angle. MEASURED
-- 2026-08-07 in a throwaway document: a motion effect requested at 0 /
-- 45 / 90 renders a smear axis of exactly 0 / 45 / 90 in screen space
-- (Y down) — the same frame this script's directions use. So the angle
-- passes through UNCHANGED.
-- This was -1 up to 1.2.2 on the assumption that the effect angle was
-- counter-clockwise in a Y-UP frame. It is not. The result was a blur
-- running up to 90 degrees ACROSS the trail instead of along it, which
-- showed up as banding perpendicular to the direction of travel.
property motionAngleSign : 1
-- Pixelmator's blur radius sliders top out at 100.
property maxBlurRadius : 100
property maxSubimages : 24

if debugMode then
	do shell script "echo '' > ~/Desktop/pixprospeed_debug.txt"
	my spLog("=== PixProSpeed " & scriptVersion & " started " & (do shell script "date '+%Y-%m-%d %H:%M:%S'") & " ===")
end if

-- ============================================================
-- LOAD SAVED DEFAULTS
-- ============================================================
set defaultDirection to "335"
set defaultDistance to "200"
set defaultSubimages to "3"
set defaultBG to false
try
	set defaultDirection to do shell script "defaults read $HOME/.pixprospeed_defaults direction 2>/dev/null"
end try
try
	set defaultDistance to do shell script "defaults read $HOME/.pixprospeed_defaults distance 2>/dev/null"
end try
try
	set defaultSubimages to do shell script "defaults read $HOME/.pixprospeed_defaults subimages 2>/dev/null"
end try
try
	set defaultBG to ((do shell script "defaults read $HOME/.pixprospeed_defaults removebg 2>/dev/null") is "1")
end try

-- ============================================================
-- PRE-FLIGHT — read the document WITHOUT activating Pixelmator.
-- Activating it here would steal the front-app slot and the prompt
-- below would open behind Pixelmator's window (the 1.0.0 bug).
-- Bind by BUNDLE ID, never by name: Apple's Creator Studio rebrand
-- made `tell application "Pixelmator Pro"` resolve to Pixelmator Pro
-- Creator Studio (com.apple.pixelmator). This id is the owned copy.
-- ============================================================
set preflightError to ""
set docDPI to 72
set sourceLayerIndex to 0
set sourceLayerName to ""
tell application id "com.pixelmatorteam.pixelmator.x"
	if (count documents) = 0 then
		set preflightError to "Open a document first."
	else
		tell front document
			if not ((count selected layers) = 1) then
				set preflightError to "Select exactly one layer to give a speed trail."
			else
				-- A layer INSIDE a group reports an index relative to its
				-- group, not to the document. Every layer operation here is
				-- document-level, so a nested selection either errors or —
				-- far worse — silently builds the trail from whichever
				-- top-level layer happens to sit at that index.
				set layerIsNested to false
				try
					if class of (parent of current layer) is group layer then set layerIsNested to true
				end try
				if layerIsNested then
					set preflightError to "That layer is inside a group, so its index is relative to the group and not to the document. Building from it would work on the wrong layer entirely." & return & return & "Drag it out to the top level, run PixProSpeed, then move the result back."
				else
					-- Needed up front so direction detection can solo and
					-- measure this layer before the dialog is even shown.
					set sourceLayerIndex to index of current layer
					set sourceLayerName to name of current layer
				end if
			end if
			try
				set docDPI to resolution
			end try
		end tell
	end if
end tell

if preflightError is not "" then
	my showAlert(preflightError)
	return
end if

-- ============================================================
-- STEP 1: Prompt for direction / distance / subimages + the
-- Remove-background toggle. Runs while THIS applet is still the
-- frontmost app. Asked before anything is created, so Cancel
-- leaves the document completely untouched.
-- ============================================================
-- ============================================================
-- STEP 0: Measure the selected layer BEFORE the dialog opens, so the
-- direction field can be prefilled with a suggestion instead of the
-- last-used number. Distance and subimages still come from the plist —
-- those have nothing to do with the layer.
--
-- This costs one solo + export per run. Verified that toggling layer
-- `visible` creates NO undo entries in Pixelmator, so the document's
-- undo history is not polluted by measuring.
--
-- The dialog names the layer it measured. That matters because the
-- alert is app-modal to THIS applet only — Pixelmator stays clickable
-- behind it, so the selection can change while the dialog is open.
-- The loop below re-checks the selection and re-measures if it moved.
-- ============================================================
set prefillDir to defaultDirection
set detectSummary to "Direction below is your last-used value."
set detection to my detectDirection(sourceLayerIndex)
if detOK of detection then
	set prefillDir to my roundedText(my suggestionFrom(detection))
	set detectSummary to my describeDetection(detection)
end if

-- The prompt runs in a loop so that a bad entry, a detected angle the
-- user wants to edit, or a changed layer selection re-opens the dialog
-- with everything still in it, instead of dropping out.
set promptDefault to prefillDir & " / " & defaultDistance & " / " & defaultSubimages
set wantsBGRemoval to defaultBG
set chosenDirection to 0
set rawDistance to defaultDistance
set subImageCount to 3
set settingsReady to false

repeat until settingsReady
	-- Naming the measured layer matters: the selection can change while
	-- this dialog is open, so the user can see what it applies to.
	set promptResult to my promptForSettings(promptDefault, wantsBGRemoval, ¬
		"Layer:  " & sourceLayerName & return & detectSummary)
	if didCancel of promptResult then return
	set rawInput to inputText of promptResult
	set wantsBGRemoval to removeBG of promptResult

	-- Strip every space, then split on "/".
	-- The delimiter MUST be reset to "" before the list is coerced back
	-- to text, otherwise the join re-inserts the very spaces the split
	-- just removed and the whole thing is a no-op. That left fields like
	-- "auto " with a trailing space, which failed the exact-match auto
	-- test even though numbers still coerced fine and hid the problem.
	-- Keep these as FOUR separate statements; collapsing the split and
	-- the coercion onto one line is exactly what caused the bug.
	set AppleScript's text item delimiters to " "
	set inputParts to text items of rawInput
	set AppleScript's text item delimiters to ""
	set rawInput to inputParts as text
	set AppleScript's text item delimiters to "/"
	set inputFields to text items of rawInput
	set AppleScript's text item delimiters to ""

	-- TOLERANT PARSE. Typing just `auto` — or just an angle — has to
	-- work: the dialog invites the bare word, and demanding all three
	-- fields made an error that simply re-opened the same dialog, so
	-- retyping `auto` looped forever. Any field left out keeps the
	-- value already in play (plist on the first pass).
	set fieldCount to (count inputFields)
	if fieldCount < 1 or fieldCount > 3 then
		my showAlert("Enter up to three values separated by slashes:" & return & return & "    direction / distance / subimages" & return & return & "Anything you leave off keeps its current value, so  auto  on its own is fine.")
	else
		set dirField to item 1 of inputFields
		set fieldsOK to true

		if fieldCount ≥ 2 then
			if (item 2 of inputFields) is not "" then set rawDistance to item 2 of inputFields
		end if
		if fieldCount ≥ 3 then
			if (item 3 of inputFields) is not "" then
				try
					set subImageCount to ((item 3 of inputFields) as number) as integer
				on error
					set fieldsOK to false
					my showAlert("Subimages must be a number.")
				end try
			end if
		end if

		if fieldsOK then
			if subImageCount < 0 then set subImageCount to 0
			if subImageCount > maxSubimages then set subImageCount to maxSubimages

			-- The alert is app-modal to THIS applet only, so Pixelmator
			-- stayed clickable behind it and the selection may have been
			-- changed while it was open. Anything measured for the old
			-- layer is meaningless now, so re-measure and ask again
			-- rather than building on a stale suggestion.
			set layerMoved to false
			tell application id "com.pixelmatorteam.pixelmator.x"
				tell front document
					try
						if (count selected layers) = 1 then
							if ((index of current layer) is not sourceLayerIndex) or ((name of current layer) is not sourceLayerName) then
								set sourceLayerIndex to index of current layer
								set sourceLayerName to name of current layer
								set layerMoved to true
							end if
						end if
					end try
				end tell
			end tell

			if layerMoved then
				set detection to my detectDirection(sourceLayerIndex)
				if detOK of detection then
					set prefillDir to my roundedText(my suggestionFrom(detection))
					set detectSummary to my describeDetection(detection)
				else
					set prefillDir to defaultDirection
					set detectSummary to "Direction below is your last-used value."
				end if
				set promptDefault to prefillDir & " / " & rawDistance & " / " & (subImageCount as text)
				my showAlert("The selected layer is now:  " & sourceLayerName & return & return & "Its direction has been re-measured. Check the dialog again.")

			else if my isAutoKeyword(dirField) then
				-- ── Detect, then ASK. Never applied silently. ──
				set detection to my detectDirection(sourceLayerIndex)
				if not (detOK of detection) then
					my showAlert((detNote of detection) & return & return & "Enter the direction in degrees instead.")
					set promptDefault to defaultDirection & " / " & rawDistance & " / " & (subImageCount as text)
				else
					set suggestedDir to my suggestionFrom(detection)
					set flippedDir to my normDeg(suggestedDir + 180)
					set answer to my confirmDirection(suggestedDir, flippedDir, detection)
					if answer is "use" then
						set chosenDirection to suggestedDir
						set settingsReady to true
					else if answer is "flip" then
						set chosenDirection to flippedDir
						set settingsReady to true
					else
						-- "Enter manually" — hand the suggestion back as the
						-- starting value so it can be nudged rather than retyped.
						set promptDefault to (my roundedText(suggestedDir)) & " / " & rawDistance & " / " & (subImageCount as text)
					end if
				end if
			else
				try
					set chosenDirection to dirField as number
					set settingsReady to true
				on error
					my showAlert("Direction must be a number in degrees, or the word  auto.")
				end try
			end if
		end if
	end if
end repeat

-- ============================================================
-- STEP 2: Resolve distance + direction vector in Python.
-- One shell call returns "<distance> <dirX> <dirY>".
-- dirX/dirY are already in SCREEN space (Y increases down),
-- so 335 gives right-and-up exactly as the dialog promises.
-- ============================================================
set travelDistance to 0
set dirX to 0
set dirY to 0
set solvedInPython to false
try
	set calcScript to "import re, math" & linefeed & ¬
		"dpi = " & (docDPI as text) & linefeed & ¬
		"expr = '" & rawDistance & "'" & linefeed & ¬
		"expr = re.sub(r'([0-9.]+)mm', lambda m: str(float(m.group(1)) * dpi / 25.4), expr)" & linefeed & ¬
		"d = int(round(eval(expr)))" & linefeed & ¬
		"a = math.radians(" & (chosenDirection as text) & ")" & linefeed & ¬
		"print(d, math.cos(a), math.sin(a))"
	set calcResult to do shell script "python3 -c " & quoted form of calcScript
	set AppleScript's text item delimiters to " "
	set calcParts to text items of calcResult
	set AppleScript's text item delimiters to ""
	set travelDistance to (item 1 of calcParts) as number
	set dirX to (item 2 of calcParts) as number
	set dirY to (item 3 of calcParts) as number
	set solvedInPython to true
on error errMsg
	my spLog("Python solve failed (" & errMsg & ") — falling back to AppleScript trig")
end try

if not solvedInPython then
	-- Fallback: plain number only, quadrant-reduced Taylor trig.
	try
		set travelDistance to (rawDistance as number)
	on error
		set travelDistance to (defaultDistance as number)
	end try
	set dirX to my cosDeg(chosenDirection)
	set dirY to my sinDeg(chosenDirection)
end if

if travelDistance < 1 then
	my showAlert("Distance must be at least 1 pixel.")
	return
end if
my spLog("direction=" & (chosenDirection as text) & " distance=" & (travelDistance as text) & " subimages=" & (subImageCount as text) & " dir=(" & (dirX as text) & "," & (dirY as text) & ")")

-- ============================================================
-- STEP 3: Save defaults (the RESOLVED distance, so a math
-- expression never has to survive a plist round-trip).
-- ============================================================
do shell script "defaults write $HOME/.pixprospeed_defaults direction " & (chosenDirection as text)
do shell script "defaults write $HOME/.pixprospeed_defaults distance " & (travelDistance as text)
do shell script "defaults write $HOME/.pixprospeed_defaults subimages " & (subImageCount as text)
if wantsBGRemoval then
	do shell script "defaults write $HOME/.pixprospeed_defaults removebg 1"
else
	do shell script "defaults write $HOME/.pixprospeed_defaults removebg 0"
end if

-- ============================================================
-- BUILD — from here on Pixelmator is the app that matters, so it
-- is safe (and wanted) to bring it forward.
-- ============================================================
set runCompleted to false
set buildError to ""

tell application id "com.pixelmatorteam.pixelmator.x"
	activate
	tell front document

		-- The selection is re-checked here: the prompt is modal, but
		-- the user could still have clicked into Pixelmator behind it.
		if not ((count selected layers) = 1) then
			set buildError to "Select exactly one layer to give a speed trail."
		else

			set originalLayerName to name of current layer
			set originalLayerIndex to index of current layer
			my spLog("Source layer '" & originalLayerName & "' at index " & originalLayerIndex & " kind=" & ((class of current layer) as text))

			-- ════════════════════════════════════════════════════
			-- STEP 4: Build the pixel source.
			-- Duplicate the original, convert the DUPLICATE to pixels.
			-- The real original is never modified — it survives at
			-- originalLayerIndex+1 and ends up at the bottom of the group.
			-- Converting also gives the true rendered bounding box as
			-- `position`; text and shape layers otherwise report a
			-- baseline / vector origin, which would misplace the trail.
			-- ════════════════════════════════════════════════════
			duplicate layer originalLayerIndex
			tell layer originalLayerIndex to convert into pixels
			set pixelLayerIndex to originalLayerIndex

			-- Optional ML background removal, on the pixel COPY only.
			if wantsBGRemoval then
				set current layer to layer pixelLayerIndex
				my spLog("Removing background from pixel copy")
				try
					remove background
				on error errMsg
					my spLog("remove background failed: " & errMsg)
				end try
			end if

			set {coordX, coordY} to position of layer pixelLayerIndex
			set objWidth to width of layer pixelLayerIndex
			set objHeight to height of layer pixelLayerIndex
			my spLog("Pixel copy at index " & pixelLayerIndex & " pos=" & (coordX as text) & "," & (coordY as text) & " size=" & (objWidth as text) & "x" & (objHeight as text))

			-- ════════════════════════════════════════════════════
			-- STEP 5: Work out the smear step count.
			-- objExtent = the object's own footprint measured ALONG the
			-- travel axis. Spacing copies at a fraction of that keeps
			-- them overlapping, so the merge reads as one streak rather
			-- than a row of stamps.
			-- ════════════════════════════════════════════════════
			-- absVal on the layer size too: a horizontally or vertically
			-- FLIPPED layer reports a NEGATIVE width/height (Tim's Circle
			-- layer reads w=-650), which would otherwise shrink or invert
			-- the footprint and wreck the smear step count.
			set objExtent to (my absVal(dirX)) * (my absVal(objWidth)) + (my absVal(dirY)) * (my absVal(objHeight))
			if objExtent < 1 then set objExtent to 1
			set smearCopies to (round (travelDistance / (objExtent / smearDensity)))
			-- The motion blur has to be able to BRIDGE the gap between
			-- copies or the steps never fuse and their edges read as
			-- bands across the trail. Blur radius is smearSpacing * 1.5
			-- and Pixelmator caps radius at 100, so spacing must stay
			-- under 100/1.5 no matter how long the distance is.
			set spacingLimit to maxBlurRadius / 1.5
			set copiesForBlur to (round (travelDistance / spacingLimit)) + 1
			if smearCopies < copiesForBlur then set smearCopies to copiesForBlur
			if smearCopies < minSmearCopies then set smearCopies to minSmearCopies
			if smearCopies > maxSmearCopies then set smearCopies to maxSmearCopies
			set smearSpacing to travelDistance / smearCopies
			my spLog("objExtent=" & (objExtent as text) & " smearCopies=" & (smearCopies as text) & " spacing=" & (smearSpacing as text))

			-- Motion-blur angle for the streak. Blur is symmetric about
			-- its axis, so only the axis tilt matters; the Y-up/Y-down
			-- flip is handled by motionAngleSign.
			set motionAngle to (motionAngleSign * chosenDirection)
			repeat while motionAngle < 0
				set motionAngle to motionAngle + 360
			end repeat
			repeat while motionAngle ≥ 360
				set motionAngle to motionAngle - 360
			end repeat

			-- ════════════════════════════════════════════════════
			-- STEP 6: The sharp face copy — <name>.pixel.
			-- Duplicating the pixel source puts this copy AT
			-- pixelLayerIndex and pushes the source to +1, so the sharp
			-- object ends up ON TOP of everything built afterwards.
			-- ════════════════════════════════════════════════════
			set faceIndex to pixelLayerIndex
			duplicate layer pixelLayerIndex
			set pixelLayerIndex to pixelLayerIndex + 1
			set name of layer faceIndex to originalLayerName & ".pixel"
			set position of layer faceIndex to {coordX, coordY}

			-- ════════════════════════════════════════════════════
			-- STEP 7: The stutter subimages — <name> ghost 1..N.
			-- Ghost i sits at i/(N+1) of the distance, so the ghosts are
			-- evenly spread INSIDE the run with clear air at both ends:
			-- the object holds the near end and the smear tapers past
			-- the last ghost into the far end.
			-- Each ghost keeps its own LIVE motion effect and opacity so
			-- individual stutter frames stay tunable afterwards.
			-- ════════════════════════════════════════════════════
			set ghostIndex to pixelLayerIndex
			repeat with i from 1 to subImageCount
				-- Copy lands AT ghostIndex; the pixel source shifts down 1.
				duplicate layer ghostIndex
				set pixelLayerIndex to pixelLayerIndex + 1

				set ghostOffset to travelDistance * (i / (subImageCount + 1))

				-- Ramp 0→1 across the ghosts (0 when there is only one).
				if subImageCount > 1 then
					set ramp to (i - 1) / (subImageCount - 1)
				else
					set ramp to 0
				end if
				set ghostOpacity to round (ghostStartOpacity + ramp * (ghostEndOpacity - ghostStartOpacity))
				set ghostBlur to round (ghostStartBlur + ramp * (ghostEndBlur - ghostStartBlur))
				if ghostBlur > maxBlurRadius then set ghostBlur to maxBlurRadius

				set name of layer ghostIndex to originalLayerName & " ghost " & (i as text)
				set position of layer ghostIndex to {coordX + (dirX * ghostOffset), coordY + (dirY * ghostOffset)}
				set opacity of layer ghostIndex to ghostOpacity
				if ghostBlur > 0 then
					tell layer ghostIndex to make new motion effect at the beginning of effects with properties {radius:ghostBlur, angle:motionAngle}
				end if
				my spLog("ghost " & i & " offset=" & (ghostOffset as text) & " opacity=" & (ghostOpacity as text) & " blur=" & (ghostBlur as text))

				set ghostIndex to ghostIndex + 1
			end repeat

			-- ════════════════════════════════════════════════════
			-- STEP 8: The smear stack.
			-- Copy j sits at j/smearCopies of the distance with opacity
			-- ramping from smearStartOpacity down to smearEndOpacity, so
			-- the merged result is dense at the object and dissolves at
			-- the tail. These copies get NO effects — one motion effect
			-- on the merged layer is far cheaper and looks better.
			-- ════════════════════════════════════════════════════
			set smearTop to pixelLayerIndex
			set smearIndex to pixelLayerIndex
			repeat with j from 1 to smearCopies
				duplicate layer smearIndex
				set pixelLayerIndex to pixelLayerIndex + 1

				set smearOffset to smearSpacing * j
				set ramp to (j - 1) / (smearCopies - 1)
				set smearOpacity to round (smearStartOpacity + ramp * (smearEndOpacity - smearStartOpacity))
				if smearOpacity < 1 then set smearOpacity to 1

				set position of layer smearIndex to {coordX + (dirX * smearOffset), coordY + (dirY * smearOffset)}
				set opacity of layer smearIndex to smearOpacity

				set smearIndex to smearIndex + 1
			end repeat
			set smearBottom to smearTop + smearCopies - 1
			my spLog("Smear stack built: indices " & smearTop & ".." & smearBottom & ", pixel source now at " & pixelLayerIndex)

			-- ════════════════════════════════════════════════════
			-- STEP 9: Merge the smear stack into one layer.
			-- The merge collapses smearCopies layers into 1, so the pixel
			-- source rises by (smearCopies - 1).
			-- The merged layer's reported position is used AS-IS: see the
			-- PixProSurround v1.0.9 note in the header.
			-- ════════════════════════════════════════════════════
			set layersToMerge to {}
			repeat with i from smearTop to smearBottom
				set end of layersToMerge to layer i
			end repeat
			set smearLayer to merge layers layersToMerge
			set pixelLayerIndex to pixelLayerIndex - (smearCopies - 1)
			set name of smearLayer to originalLayerName & " smear"

			-- The live effects that turn the stepped stack into a streak.
			set smearBlur to round (smearSpacing * 1.5)
			if smearBlur < 4 then set smearBlur to 4
			if smearBlur > maxBlurRadius then set smearBlur to maxBlurRadius
			tell smearLayer to make new motion effect at the beginning of effects with properties {radius:smearBlur, angle:motionAngle}
			if smearSoftness > 0 then
				tell smearLayer to make new gaussian effect at the beginning of effects with properties {radius:smearSoftness}
			end if
			my spLog("Smear merged, motion radius=" & (smearBlur as text) & " angle=" & (motionAngle as text) & " gaussian=" & (smearSoftness as text))

			-- ════════════════════════════════════════════════════
			-- STEP 10: Drop the working pixel source.
			-- <name>.pixel already carries the sharp object, so this
			-- scratch layer has no further use. Deleting it shifts the
			-- real original up into its slot.
			-- ════════════════════════════════════════════════════
			delete layer pixelLayerIndex
			set originalNowAt to pixelLayerIndex

			-- Hide the preserved original. It is kept so nothing is ever
			-- destroyed, but it sits directly under <name>.pixel and would
			-- show through the moment the .pixel copy is moved or edited.
			-- Being the one hidden layer in the group also marks which one
			-- is the untouched original.
			set visible of layer originalNowAt to false

			-- ════════════════════════════════════════════════════
			-- STEP 11: Group everything under the source layer's name.
			-- The layers run contiguously from faceIndex to originalNowAt
			-- (.pixel → ghosts → smear → original), and `make group`
			-- requires ADJACENT layers. Gathering them by INDEX rather
			-- than by name avoids the duplicate-name trap that bit
			-- PixProEmboss 2.2.2.
			-- ════════════════════════════════════════════════════
			set layersToGroup to {}
			repeat with i from faceIndex to originalNowAt
				set end of layersToGroup to layer i
			end repeat
			set theGroup to make group from layersToGroup
			set name of theGroup to originalLayerName
			my spLog("Grouped indices " & faceIndex & ".." & originalNowAt & " as '" & originalLayerName & "'")

			set runCompleted to true
		end if

	end tell
end tell

if buildError is not "" then
	my showAlert(buildError)
else if runCompleted then
	display notification "Speed trail built: " & (subImageCount as text) & " subimage(s) over " & (travelDistance as text) & " px." with title "PixProSpeed " & scriptVersion
end if
my spLog("=== PixProSpeed complete ===")

-- ============================================================
-- HELPER HANDLERS
-- ============================================================

-- promptForSettings: one dialog carrying the "direction / distance /
-- subimages" text field AND a real Remove-background toggle switch.
-- `display dialog` has no checkbox, so this is an NSAlert with an
-- accessory view: an NSTextField above an NSSwitch + label.
--
-- MUST be called while this applet is frontmost. In 1.0.0 Pixelmator
-- had already been activated, and the modal opened behind it — the
-- applet just bounced in the Dock with no dialog on screen. Three
-- layers of insurance now: `tell me to activate`, a delay so that
-- activation is processed before runModal blocks the event loop, and
-- a floating window level (3) on the alert window.
--
-- Returns {didCancel:boolean, inputText:text, removeBG:boolean}.
-- Any AppKit failure falls through to a plain three-button dialog
-- offering the identical choice.
on promptForSettings(defaultText, bgOnByDefault, contextText)
	set infoText to contextText & return & return & ¬
		"Format:  direction / distance / subimages" & return & return & ¬
		"Direction — degrees the object CAME FROM:" & return & ¬
		"      0 = right     90 = down     180 = left     270 = up" & return & ¬
		"    45 = lower-right          135 = lower-left" & return & ¬
		"  225 = upper-left            315 = upper-right" & return & return & ¬
		"   The direction above is already measured from this layer." & return & ¬
		"   Type  auto  on its own to re-measure and see the reasoning." & return & return & ¬
		"Leave a field off and it keeps its current value —" & return & ¬
		"   auto        just re-measure the direction" & return & ¬
		"   180         just change the direction" & return & ¬
		"   180 / 900   direction and distance" & return & return & ¬
		"Distance — pixels, mm (5mm), or math (72/25.4*5)" & return & ¬
		"Subimages — stutter ghosts inside that distance (0-" & maxSubimages & ")"
	try
		tell me to activate
		delay 0.3

		set theAlert to current application's NSAlert's alloc()'s init()
		theAlert's setMessageText:("PixProSpeed " & scriptVersion)
		theAlert's setInformativeText:infoText
		theAlert's addButtonWithTitle:"Create Speed"
		theAlert's addButtonWithTitle:"Cancel"

		set accessory to current application's NSView's alloc()'s initWithFrame:{{0, 0}, {380, 76}}

		set inputField to current application's NSTextField's alloc()'s initWithFrame:{{0, 46}, {380, 24}}
		inputField's setStringValue:defaultText
		accessory's addSubview:inputField

		set bgSwitch to current application's NSSwitch's alloc()'s initWithFrame:{{0, 4}, {38, 22}}
		if bgOnByDefault then
			bgSwitch's setState:1
		else
			bgSwitch's setState:0
		end if
		accessory's addSubview:bgSwitch

		set bgLabel to current application's NSTextField's labelWithString:"Remove background from the copy first"
		bgLabel's setFrame:{{48, 7}, {330, 18}}
		accessory's addSubview:bgLabel

		theAlert's setAccessoryView:accessory
		theAlert's |window|'s setInitialFirstResponder:inputField
		-- NSFloatingWindowLevel = 3. Keeps the modal above the
		-- Pixelmator window even if activation has not settled yet.
		try
			theAlert's |window|'s setLevel:3
		end try

		current application's NSApplication's sharedApplication()'s activateIgnoringOtherApps:true
		set theResponse to theAlert's runModal()

		-- NSAlertFirstButtonReturn = 1000 → "Create Speed".
		set wasCancelled to ((theResponse as integer) is not 1000)
		set enteredText to (inputField's stringValue()) as text
		set bgWanted to ((bgSwitch's state()) as integer) is 1
		return {didCancel:wasCancelled, inputText:enteredText, removeBG:bgWanted}
	on error errMsg
		my spLog("NSAlert prompt failed (" & errMsg & ") — using display dialog fallback")
	end try

	-- Fallback: no checkbox available, so the choice becomes a button.
	tell me to activate
	set dlg to display dialog ("PixProSpeed " & scriptVersion & return & return & infoText) ¬
		default answer defaultText ¬
		buttons {"Cancel", "Remove BG + Speed", "Create Speed"} ¬
		default button "Create Speed" ¬
		cancel button "Cancel"
	return {didCancel:false, inputText:(text returned of dlg), removeBG:((button returned of dlg) is "Remove BG + Speed")}
end promptForSettings

-- suggestionFrom: turn a detection into a Direction-field value.
-- Shape analysis reports which way the object FACES, so 180 is added
-- to get "came from". Layer rotation is already a Direction value and
-- is used unchanged — that is what detIsFacing distinguishes.
on suggestionFrom(detection)
	if detIsFacing of detection then
		return my normDeg((detFacing of detection) + 180)
	end if
	return my normDeg(detFacing of detection)
end suggestionFrom

-- describeDetection: the one-line explanation shown in the prompt, so
-- the prefilled number is never an unexplained value in a box.
on describeDetection(detection)
	if (detSource of detection) is "shape" then
		set s to "Direction suggested from the layer outline (" & my oneDecimal(detElong of detection) & " : 1)."
		if (detMargin of detection) < noseConfidentMargin then
			set s to s & return & "Which END is the front is uncertain — add 180 if the trail comes out the wrong side."
		end if
		return s
	else if (detSource of detection) is "rotation" then
		return "Direction suggested from the layer's own rotation."
	end if
	return "Direction below is your last-used value."
end describeDetection

-- isAutoKeyword: true when the direction field asks for detection.
on isAutoKeyword(fieldText)
	set t to fieldText
	try
		set t to do shell script "printf %s " & quoted form of t & " | tr 'A-Z' 'a-z'"
	end try
	return (t is "auto") or (t is "a")
end isAutoKeyword

-- normDeg: fold any angle into 0-360.
on normDeg(d)
	repeat while d < 0
		set d to d + 360
	end repeat
	repeat while d ≥ 360
		set d to d - 360
	end repeat
	return d
end normDeg

-- roundedText: whole degrees as text, for dialogs and prefilled fields.
on roundedText(d)
	return (round d) as text
end roundedText

-- ============================================================
-- detectDirection: work out which way the layer is pointing.
--
-- Returns a record:
--   detOK      — was anything determined at all
--   detFacing  — the direction the object FACES, in this script's
--                convention (0 = right, 90 = down, Y increases down).
--                The caller adds 180 to get "came from".
--   detSource  — "shape" or "rotation", for the confirmation dialog
--   detElong   — long:short axis ratio (shape only)
--   detMargin  — nose-vs-tail width margin, 0-1 (shape only).
--                Low means "which END is the front" is a guess.
--   detNote    — human-readable explanation, always set
--
-- HOW: the layer is soloed (every other top-level layer hidden), the
-- document exported to a temp PNG, and the alpha channel analysed in
-- Python. Visibility is ALWAYS restored, including on failure — the
-- restore runs outside the try that does the hiding and exporting.
-- This is the same solo-export-analyse pattern PixProSimplify uses.
--
-- If the silhouette has no usable long axis (a circle measures
-- exactly 1.00 : 1) the layer's own `rotation` is used instead, which
-- is the only sensible signal for a round object.
-- ============================================================
on detectDirection(layerIdx)
	set expPath to "/tmp/pixprospeed_detect.png"
	do shell script "rm -f " & quoted form of expPath

	set layerRotation to 0
	set exportOK to false
	set layerCount to 0
	set savedVis to {}

	tell application id "com.pixelmatorteam.pixelmator.x"
		tell front document
			set layerCount to (count layers)
			try
				set layerRotation to rotation of layer layerIdx
			end try
			repeat with i from 1 to layerCount
				set end of savedVis to (visible of layer i)
			end repeat
		end tell

		-- Solo the source layer and export it on its own.
		try
			tell front document
				repeat with i from 1 to layerCount
					set visible of layer i to (i = layerIdx)
				end repeat
			end tell
			export front document to (POSIX file expPath) as PNG
			set exportOK to true
		on error errMsg
			my spLog("solo/export failed: " & errMsg)
		end try

		-- Restore visibility unconditionally — never leave the document
		-- soloed because something above threw.
		try
			tell front document
				repeat with i from 1 to layerCount
					set visible of layer i to (item i of savedVis)
				end repeat
			end tell
		end try
	end tell

	-- ── Shape analysis ────────────────────────────────────────
	set shapeUsable to false
	set elongVal to 0
	set axisVal to 0
	set noseVal to 0
	set marginVal to 0
	set coverVal to 0
	set analysisNote to ""

	if exportOK then
		try
			-- The image is scaled to a fixed size BEFORE measuring, so the
			-- result does not depend on the canvas size — an early version
			-- sub-sampled the raw export and gave different answers for the
			-- same object in a 2400px document vs an 800px one.
			-- End "width" is a MEAN half-width (area-based) rather than the
			-- extreme min-to-max, which a single stray pixel could swing.
			set pyScript to "import sys, math" & linefeed & ¬
				"from PIL import Image" & linefeed & ¬
				"im = Image.open(sys.argv[1]).convert('RGBA')" & linefeed & ¬
				"im.thumbnail((420, 420), Image.LANCZOS)" & linefeed & ¬
				"w, h = im.size" & linefeed & ¬
				"a = im.split()[3].load()" & linefeed & ¬
				"pts = [(x, y) for y in range(h) for x in range(w) if a[x, y] > 32]" & linefeed & ¬
				"n = len(pts)" & linefeed & ¬
				"cover = float(n) / max(w * h, 1)" & linefeed & ¬
				"if n < 24:" & linefeed & ¬
				"    print('EMPTY 0 0 0 0 %.4f' % cover); sys.exit()" & linefeed & ¬
				"mx = sum(p[0] for p in pts) / float(n)" & linefeed & ¬
				"my = sum(p[1] for p in pts) / float(n)" & linefeed & ¬
				"sxx = syy = sxy = 0.0" & linefeed & ¬
				"for x, y in pts:" & linefeed & ¬
				"    dx = x - mx; dy = y - my" & linefeed & ¬
				"    sxx += dx * dx; syy += dy * dy; sxy += dx * dy" & linefeed & ¬
				"sxx /= n; syy /= n; sxy /= n" & linefeed & ¬
				"half = (sxx + syy) / 2.0" & linefeed & ¬
				"root = math.sqrt(((sxx - syy) / 2.0) ** 2 + sxy * sxy)" & linefeed & ¬
				"lam1 = half + root; lam2 = half - root" & linefeed & ¬
				"elong = math.sqrt(lam1 / lam2) if lam2 > 1e-9 else 999.0" & linefeed & ¬
				"th = 0.5 * math.atan2(2 * sxy, sxx - syy)" & linefeed & ¬
				"ex, ey = math.cos(th), math.sin(th)" & linefeed & ¬
				"axis = math.degrees(math.atan2(ey, ex)) % 360.0" & linefeed & ¬
				"proj = [((x-mx)*ex + (y-my)*ey, -(x-mx)*ey + (y-my)*ex) for x, y in pts]" & linefeed & ¬
				"tmin = min(t for t, _ in proj); tmax = max(t for t, _ in proj)" & linefeed & ¬
				"span = max(tmax - tmin, 1e-9)" & linefeed & ¬
				"def ew(lo, hi):" & linefeed & ¬
				"    s = [abs(p) for t, p in proj if lo <= t <= hi]" & linefeed & ¬
				"    return (sum(s) / len(s)) if s else 0.0" & linefeed & ¬
				"wpos = ew(tmax - 0.25 * span, tmax)" & linefeed & ¬
				"wneg = ew(tmin, tmin + 0.25 * span)" & linefeed & ¬
				"nose = axis if wpos < wneg else (axis + 180.0) % 360.0" & linefeed & ¬
				"margin = abs(wpos - wneg) / max(wpos, wneg, 1e-9)" & linefeed & ¬
				"print('OK %.4f %.3f %.3f %.4f %.4f' % (elong, axis, nose, margin, cover))"
			set pyOut to do shell script "python3 -c " & quoted form of pyScript & " " & quoted form of expPath
			set AppleScript's text item delimiters to " "
			set pyParts to text items of pyOut
			set AppleScript's text item delimiters to ""
			if (item 1 of pyParts) is "OK" then
				set elongVal to (item 2 of pyParts) as number
				set axisVal to (item 3 of pyParts) as number
				set noseVal to (item 4 of pyParts) as number
				set marginVal to (item 5 of pyParts) as number
				set coverVal to (item 6 of pyParts) as number
				if coverVal > opaqueCoverageLimit then
					set analysisNote to "That layer is almost entirely opaque, so it has no outline to measure — most likely a photo with its background still on." & return & return & "Switch on Remove background and run auto again, and the cut-out subject can be measured."
				else if elongVal ≥ shapeMinElongation then
					set shapeUsable to true
				else
					set analysisNote to "That shape is too round to have a direction (it measures " & my oneDecimal(elongVal) & " : 1)."
				end if
			else
				set analysisNote to "That layer looks empty — nothing opaque to measure."
			end if
			my spLog("detect: elong=" & (elongVal as text) & " axis=" & (axisVal as text) & " nose=" & (noseVal as text) & " margin=" & (marginVal as text) & " cover=" & (coverVal as text))
		on error errMsg
			my spLog("detect analysis failed: " & errMsg)
			set analysisNote to "Could not analyse the layer shape. This needs python3 with the Pillow imaging library installed."
		end try
	else
		set analysisNote to "Could not export the layer to measure it."
	end if

	do shell script "rm -f " & quoted form of expPath

	-- detIsFacing says how to read detFacing:
	--   true  — it is the direction the object POINTS, so the caller
	--           adds 180 to get "came from" (shape analysis).
	--   false — it is already the "came from" Direction value and is
	--           used as-is (layer rotation; see rotationSign).
	if shapeUsable then
		return {detOK:true, detFacing:noseVal, detIsFacing:true, detSource:"shape", detElong:elongVal, detMargin:marginVal, detNote:""}
	end if

	-- ── Fall back to the layer's own rotation ─────────────────
	-- A round object has no axis to find, so the only thing that can
	-- say where it is going is how the layer has been rotated.
	if layerRotation is not 0 then
		return {detOK:true, detFacing:my normDeg(rotationSign * layerRotation), detIsFacing:false, detSource:"rotation", detElong:0, detMargin:1, detNote:""}
	end if

	return {detOK:false, detFacing:0, detIsFacing:true, detSource:"none", detElong:elongVal, detMargin:0, detNote:analysisNote & return & return & "Its rotation is 0, so there is no direction to read from it either. Rotate the layer to point it where it is going, then try auto again."}
end detectDirection

-- oneDecimal: a real formatted to one decimal place, for dialogs.
on oneDecimal(x)
	set scaled to (round (x * 10)) / 10
	return scaled as text
end oneDecimal

-- ============================================================
-- confirmDirection: show what was detected and let the user accept
-- it, flip it 180, or go back and type an angle.
-- The suggestion is NEVER applied without passing through here — a
-- silhouette gives an axis, and which END is the front is the part
-- most likely to be wrong, so it has to be a human call.
-- Returns "use", "flip", or "manual".
-- ============================================================
on confirmDirection(suggestedDir, flippedDir, detection)
	set srcText to detSource of detection
	if srcText is "shape" then
		set detail to "Measured from the layer outline: it is " & my oneDecimal(detElong of detection) & " times longer than it is wide, so it has a clear long axis."
		if (detMargin of detection) < noseConfidentMargin then
			set detail to detail & return & return & "WHICH END IS THE FRONT is uncertain — both ends of this shape are a similar width. If the trail comes out on the wrong side, use Flip."
		else
			set detail to detail & return & return & "The narrow end reads clearly as the front."
		end if
	else
		set detail to "That shape is too round to have a direction, so the layer's own rotation was used instead — it is rotated to " & my roundedText(suggestedDir) & "°."
	end if

	set msg to "Suggested direction:  " & my roundedText(suggestedDir) & "°" & return & return & ¬
		detail & return & return & ¬
		"That puts the trail behind the object, as if it came from " & my roundedText(suggestedDir) & "°." & return & ¬
		"Flipping gives " & my roundedText(flippedDir) & "° instead."

	try
		tell me to activate
		delay 0.2
		set theAlert to current application's NSAlert's alloc()'s init()
		theAlert's setMessageText:("PixProSpeed " & scriptVersion & " — direction detected")
		theAlert's setInformativeText:msg
		theAlert's addButtonWithTitle:("Use " & my roundedText(suggestedDir) & "°")
		theAlert's addButtonWithTitle:("Flip to " & my roundedText(flippedDir) & "°")
		theAlert's addButtonWithTitle:"Enter manually"
		try
			theAlert's |window|'s setLevel:3
		end try
		current application's NSApplication's sharedApplication()'s activateIgnoringOtherApps:true
		set r to (theAlert's runModal()) as integer
		if r is 1000 then return "use"
		if r is 1001 then return "flip"
		return "manual"
	on error errMsg
		my spLog("confirmDirection NSAlert failed (" & errMsg & ") — using display dialog")
	end try

	tell me to activate
	set dlg to display dialog msg buttons {"Enter manually", "Flip to " & my roundedText(flippedDir) & "°", "Use " & my roundedText(suggestedDir) & "°"} default button 3
	set b to button returned of dlg
	if b is ("Use " & my roundedText(suggestedDir) & "°") then return "use"
	if b is ("Flip to " & my roundedText(flippedDir) & "°") then return "flip"
	return "manual"
end confirmDirection

-- showAlert: warnings are shown BY THIS APPLET, not from inside a
-- `tell application "Pixelmator Pro"` block. An alert raised inside
-- that block belongs to Pixelmator, and if Pixelmator is not the
-- front app it can sit unseen behind another window.
on showAlert(theMessage)
	tell me to activate
	display alert ("PixProSpeed " & scriptVersion) message theMessage
end showAlert

-- spLog: appends a line to ~/Desktop/pixprospeed_debug.txt.
-- Guarded INSIDE the handler — a `property debugMode : false` at the
-- top does not stop callers, so without this guard the shell echo
-- runs on every call (the PixProShadow 7.1.2 bug).
on spLog(msg)
	if debugMode then
		do shell script "echo " & quoted form of msg & " >> ~/Desktop/pixprospeed_debug.txt"
	end if
end spLog

-- absVal: AppleScript has no abs().
on absVal(x)
	if x < 0 then return -x
	return x
end absVal

-- sinDeg / cosDeg: fallback trig for when the Python call fails.
-- The angle is folded into 0-90° first because a plain Taylor series
-- is only accurate near zero — evaluating it at π directly is off by
-- more than 20%, which would point the trail the wrong way.
on sinDeg(d)
	repeat while d < 0
		set d to d + 360
	end repeat
	repeat while d ≥ 360
		set d to d - 360
	end repeat
	if d ≤ 90 then return my sinSmall(d)
	if d ≤ 180 then return my sinSmall(180 - d)
	if d ≤ 270 then return -(my sinSmall(d - 180))
	return -(my sinSmall(360 - d))
end sinDeg

on cosDeg(d)
	return my sinDeg(d + 90)
end cosDeg

-- sinSmall: sin(x) for 0-90° via Taylor series, accurate to ~1e-7
-- over that reduced range. x arrives in DEGREES.
on sinSmall(deg)
	set x to deg * (3.14159265358979 / 180)
	set x2 to x * x
	set term to x
	set total to x
	repeat with k from 1 to 6
		set term to -term * x2 / ((2 * k) * (2 * k + 1))
		set total to total + term
	end repeat
	return total
end sinSmall
