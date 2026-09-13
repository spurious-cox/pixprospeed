-- ============================================================
-- engine.applescript — PixProSpeed build engine
-- Version 1.0.3  (2026-08-07)
--
-- Copyright (c) 2026 Tim McCoy. All rights reserved.
-- Developed with assistance from Claude (Anthropic).
--
-- The layer-building half of PixProSpeed, with every dialog and all
-- detection removed. The floating panel (PixProSpeedPanel.app) owns
-- the user interface and calls this with finished numbers:
--
--   osascript engine.scpt <direction> <distance> <subimages> <removebg>
--
--   direction  degrees, 0 = right, 90 = down (screen angles, Y down)
--   distance   pixels, ALREADY resolved — no mm or math here
--   subimages  count of stutter ghosts, 0 or more
--   removebg   1 or 0
--
-- Prints "OK <groupname>" on success, or "ERR <message>". The panel
-- shows whatever comes back, so nothing here ever opens a dialog —
-- a dialog would block the panel's run loop with no way to dismiss it.
--
-- All the index arithmetic, the merge behaviour and the flipped-layer
-- guard are carried over unchanged from PixProSpeed.applescript 1.2.2,
-- which is the version whose output Tim verified on screen. See that
-- file's header and PixProSpeed-README.txt for why each step is shaped
-- the way it is; the notes are not repeated here.
-- ============================================================

property smearDensity : 6
property minSmearCopies : 8
property maxSmearCopies : 90
property smearStartOpacity : 45
property smearEndOpacity : 2
property smearSoftness : 6
property ghostStartOpacity : 45
property ghostEndOpacity : 12
property ghostStartBlur : 2
property ghostEndBlur : 20
-- MEASURED 2026-08-07: a motion effect requested at 0/45/90 renders a
-- smear axis of exactly 0/45/90 in SCREEN space (Y down) — the same
-- frame these directions use — so the angle passes through unchanged.
-- Was -1 until PixProSpeed 1.3.0, which aimed the blur up to 90 degrees
-- ACROSS the trail and produced banding perpendicular to the travel.
property motionAngleSign : 1
property maxBlurRadius : 100

on run argv
	if (count argv) < 7 then return "ERR engine needs 7 arguments: direction distance subimages removebg apppath footw footh"

	try
		set chosenDirection to (item 1 of argv) as number
		set travelDistance to (item 2 of argv) as number
		set subImageCount to ((item 3 of argv) as number) as integer
		set wantsBGRemoval to ((item 4 of argv) as text) is "1"
		-- Which Pixelmator build to drive. Resolved by the panel (pixelmator.target())
		-- and passed in, so the engine never has to guess between the two installs.
		set pixApp to (item 5 of argv) as text
		-- TRUE rendered footprint, measured from the exported alpha by the
		-- panel. 0 means "not measured, use width of layer" (the panel skips
		-- the measurement when Remove background is on).
		set footW to (item 6 of argv) as number
		set footH to (item 7 of argv) as number
	on error
		return "ERR could not read the engine arguments"
	end try

	if travelDistance < 1 then return "ERR distance must be at least 1 pixel"
	if subImageCount < 0 then set subImageCount to 0

	-- Direction vector in SCREEN space (Y increases downward), so 335
	-- runs right-and-up. Trig via Python; AppleScript has none.
	try
		set trigOut to do shell script "python3 -c " & quoted form of ¬
			("import math; a = math.radians(" & (chosenDirection as text) & "); print(math.cos(a), math.sin(a))")
		set AppleScript's text item delimiters to " "
		set trigParts to text items of trigOut
		set AppleScript's text item delimiters to ""
		set dirX to (item 1 of trigParts) as number
		set dirY to (item 2 of trigParts) as number
	on error
		set dirX to my cosDeg(chosenDirection)
		set dirY to my sinDeg(chosenDirection)
	end try

	set motionAngle to my normDeg(motionAngleSign * chosenDirection)

	using terms from application "Pixelmator Pro"
	tell application pixApp
		if (count documents) = 0 then return "ERR no document is open"
		tell front document
			if not ((count selected layers) = 1) then return "ERR select exactly one layer"

			-- A nested layer's index is relative to its GROUP, but every
			-- operation below is document-level, so building from one would
			-- silently target the wrong top-level layer.
			set layerIsNested to false
			try
				if class of (parent of current layer) is group layer then set layerIsNested to true
			end try
			if layerIsNested then return "ERR that layer is inside a group - drag it to the top level first"

			set originalLayerName to name of current layer
			set originalLayerIndex to index of current layer

			-- Pixel source: duplicate, convert the DUPLICATE. The real
			-- original is never modified.
			duplicate layer originalLayerIndex
			tell layer originalLayerIndex to convert into pixels
			set pixelLayerIndex to originalLayerIndex

			if wantsBGRemoval then
				set current layer to layer pixelLayerIndex
				try
					remove background
				end try
			end if

			set {coordX, coordY} to position of layer pixelLayerIndex
			set objWidth to width of layer pixelLayerIndex
			set objHeight to height of layer pixelLayerIndex

			-- absVal on the size: a FLIPPED layer reports a NEGATIVE
			-- width/height, which would wreck the step count.
			--
			-- Prefer the measured footprint. `width of layer` is the SHAPE's
			-- PATH bounds, but a stroke renders outside (or inside) that
			-- path, so the two disagree -- on the heart that exposed this,
			-- by -7px in width and +9px in height, in opposite directions.
			-- Overstating the extent spaces the smear copies too far apart
			-- and the trail develops gaps along its flanks; an OUTSIDE
			-- stroke inflates every side, which is why it was worst there.
			set useW to my absVal(objWidth)
			set useH to my absVal(objHeight)
			if footW > 0 and footH > 0 then
				set useW to footW
				set useH to footH
			end if
			set objExtent to (my absVal(dirX)) * useW + (my absVal(dirY)) * useH
			if objExtent < 1 then set objExtent to 1
			set smearCopies to (round (travelDistance / (objExtent / smearDensity)))
			-- The blur must BRIDGE the gap between copies or the steps
			-- never fuse and their edges band across the trail. Radius is
			-- smearSpacing * 1.5, capped at 100 by Pixelmator.
			set spacingLimit to maxBlurRadius / 1.5
			set copiesForBlur to (round (travelDistance / spacingLimit)) + 1
			if smearCopies < copiesForBlur then set smearCopies to copiesForBlur
			if smearCopies < minSmearCopies then set smearCopies to minSmearCopies
			if smearCopies > maxSmearCopies then set smearCopies to maxSmearCopies
			set smearSpacing to travelDistance / smearCopies

			-- Sharp face copy on top
			set faceIndex to pixelLayerIndex
			duplicate layer pixelLayerIndex
			set pixelLayerIndex to pixelLayerIndex + 1
			set name of layer faceIndex to originalLayerName & ".pixel"
			set position of layer faceIndex to {coordX, coordY}

			-- Stutter subimages, each keeping its own live effect
			set ghostIndex to pixelLayerIndex
			repeat with i from 1 to subImageCount
				duplicate layer ghostIndex
				set pixelLayerIndex to pixelLayerIndex + 1
				set ghostOffset to travelDistance * (i / (subImageCount + 1))
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
				set ghostIndex to ghostIndex + 1
			end repeat

			-- Smear stack
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

			-- Merge. The merged position is used AS-IS (PixProSurround 1.0.9).
			set layersToMerge to {}
			repeat with i from smearTop to smearBottom
				set end of layersToMerge to layer i
			end repeat
			set smearLayer to merge layers layersToMerge
			set pixelLayerIndex to pixelLayerIndex - (smearCopies - 1)
			set name of smearLayer to originalLayerName & " smear"

			set smearBlur to round (smearSpacing * 1.5)
			if smearBlur < 4 then set smearBlur to 4
			if smearBlur > maxBlurRadius then set smearBlur to maxBlurRadius
			tell smearLayer to make new motion effect at the beginning of effects with properties {radius:smearBlur, angle:motionAngle}
			if smearSoftness > 0 then
				tell smearLayer to make new gaussian effect at the beginning of effects with properties {radius:smearSoftness}
			end if

			-- Drop the scratch pixel source; the original rises into its slot
			delete layer pixelLayerIndex
			set originalNowAt to pixelLayerIndex

			-- Hide the preserved original. It is kept so nothing is ever
			-- destroyed, but it sits directly under <name>.pixel and would
			-- show through the moment the .pixel copy is moved or edited.
			-- Being the one hidden layer in the group also marks which one
			-- is the untouched original.
			set visible of layer originalNowAt to false

			-- Group by INDEX (adjacent layers; avoids the name-collision trap)
			set layersToGroup to {}
			repeat with i from faceIndex to originalNowAt
				set end of layersToGroup to layer i
			end repeat
			set theGroup to make group from layersToGroup
			set name of theGroup to originalLayerName

			return "OK " & originalLayerName
		end tell
	end tell
	end using terms from
end run

on absVal(x)
	if x < 0 then return -x
	return x
end absVal

on normDeg(d)
	repeat while d < 0
		set d to d + 360
	end repeat
	repeat while d ≥ 360
		set d to d - 360
	end repeat
	return d
end normDeg

on sinDeg(d)
	set d to my normDeg(d)
	if d ≤ 90 then return my sinSmall(d)
	if d ≤ 180 then return my sinSmall(180 - d)
	if d ≤ 270 then return -(my sinSmall(d - 180))
	return -(my sinSmall(360 - d))
end sinDeg

on cosDeg(d)
	return my sinDeg(d + 90)
end cosDeg

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
