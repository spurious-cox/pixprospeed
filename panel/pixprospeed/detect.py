"""Work out which way a layer is pointing.

Copyright (c) 2026 Tim McCoy. All rights reserved.
Developed with assistance from Claude (Anthropic).

Two detectors, tried in order:

1. SHAPE — the principal axis (PCA) of the layer's opaque pixels. Good
   for anything that moves nose-first: cars, rockets, arrows, planes.
   Measured on real artwork:
       circle 1.00 : 1     square 1.00 : 1     <- no usable axis
       car    4.22 : 1     rocket 3.59 : 1     <- usable
   MIN_ELONGATION separates them cleanly.

2. ROTATION — for round or featureless objects, which have no long axis
   at all. The layer's own `rotation` is the only thing that can say
   where a circle is going.

WHAT THIS CANNOT DO. PCA yields an AXIS, not an arrow: 358 and 178 are
the same line to it. Which end is the FRONT is a separate heuristic (the
narrower end is taken as the nose) and it is genuinely unreliable — two
renderings of the same car gave OPPOSITE answers, margin ~0.10 both
times, while a rocket scored 0.63. So a low margin is reported as
uncertain rather than presented as fact, and the panel remembers the
user's correction per layer instead of pretending to be smarter.

Also: the long axis equals the direction of travel only for things that
move nose-first. A running figure is tall but travels sideways.

Angles are in the PixProSpeed convention — 0 = right, 90 = down, screen
space with Y increasing downward.
"""

import math

# Long:short ratio a shape needs before it counts as having a direction.
MIN_ELONGATION = 1.35
# Below this nose-vs-tail margin the front/back call is flagged uncertain.
CONFIDENT_MARGIN = 0.25
# Above this opaque fraction there is no silhouette to measure — almost
# certainly a photo with its background still on.
OPAQUE_LIMIT = 0.9
# Measure at a fixed size so the answer does not depend on canvas size.
# Sub-sampling the raw export gave different results for the same object
# in a 2400px document versus an 800px one.
ANALYSIS_SIZE = 420


def measure_shape(png_path):
    """PCA over the alpha channel of a solo-exported layer.

    Returns a dict: ok, elongation, axis, nose, margin, coverage, note.
    """
    try:
        from PIL import Image
    except ImportError:
        return {"ok": False, "note": "The imaging library is missing from this build."}

    try:
        im = Image.open(png_path).convert("RGBA")
    except Exception:
        return {"ok": False, "note": "Could not read the exported layer."}

    im.thumbnail((ANALYSIS_SIZE, ANALYSIS_SIZE), Image.LANCZOS)
    w, h = im.size
    alpha = im.split()[3].load()
    pts = [(x, y) for y in range(h) for x in range(w) if alpha[x, y] > 32]
    n = len(pts)
    if n < 24:
        return {"ok": False, "note": "Nothing opaque on that layer to measure."}

    coverage = float(n) / max(w * h, 1)
    if coverage > OPAQUE_LIMIT:
        return {"ok": False, "coverage": coverage, "note":
                "Almost entirely opaque, so there is no outline to measure. "
                "Switch on Remove background and try again."}

    mx = sum(p[0] for p in pts) / float(n)
    my = sum(p[1] for p in pts) / float(n)
    sxx = syy = sxy = 0.0
    for x, y in pts:
        dx, dy = x - mx, y - my
        sxx += dx * dx
        syy += dy * dy
        sxy += dx * dy
    sxx /= n
    syy /= n
    sxy /= n

    half = (sxx + syy) / 2.0
    root = math.sqrt(((sxx - syy) / 2.0) ** 2 + sxy * sxy)
    lam1, lam2 = half + root, half - root
    elongation = math.sqrt(lam1 / lam2) if lam2 > 1e-9 else 999.0

    theta = 0.5 * math.atan2(2 * sxy, sxx - syy)
    ex, ey = math.cos(theta), math.sin(theta)
    axis = math.degrees(math.atan2(ey, ex)) % 360.0

    if elongation < MIN_ELONGATION:
        return {"ok": False, "elongation": elongation, "note":
                "Too round for an axis (%.1f : 1)." % elongation}

    # Project onto the axis and compare the two ends. Mean half-width is
    # area-based; an extreme min-to-max could be swung by one stray pixel.
    proj = [((x - mx) * ex + (y - my) * ey, -(x - mx) * ey + (y - my) * ex)
            for x, y in pts]
    tmin = min(t for t, _ in proj)
    tmax = max(t for t, _ in proj)
    span = max(tmax - tmin, 1e-9)

    def mean_halfwidth(lo, hi):
        s = [abs(p) for t, p in proj if lo <= t <= hi]
        return (sum(s) / len(s)) if s else 0.0

    w_pos = mean_halfwidth(tmax - 0.25 * span, tmax)
    w_neg = mean_halfwidth(tmin, tmin + 0.25 * span)
    nose = axis if w_pos < w_neg else (axis + 180.0) % 360.0
    margin = abs(w_pos - w_neg) / max(w_pos, w_neg, 1e-9)

    return {"ok": True, "elongation": elongation, "axis": axis,
            "nose": nose, "margin": margin, "coverage": coverage, "note": ""}


def facing_to_direction(facing):
    """Convert 'which way it points' to the Direction field's 'came from'."""
    return (facing + 180.0) % 360.0


def describe(result, source):
    """One line for the panel explaining where a suggestion came from."""
    if source == "shape":
        text = "Outline is %.1f : 1." % result.get("elongation", 0)
        if result.get("margin", 0) < CONFIDENT_MARGIN:
            text += " Which end is the front is uncertain — use Flip if the trail runs the wrong way."
        else:
            text += " The narrow end reads clearly as the front."
        return text
    if source == "rotation":
        return "Too round for an axis — used the layer's rotation."
    if source == "remembered":
        return "Using the direction you corrected for this layer before."
    return "Enter a direction in degrees."


def footprint(png_path):
    """True rendered size of a solo-exported layer, in document pixels.

    Returns (width, height), or (0, 0) if it cannot be read.

    This is deliberately NOT measure_shape(): that one thumbnails to
    ANALYSIS_SIZE for a PCA over the outline, which is fine for finding an
    axis but useless as a size. The step maths needs real pixels.

    Why it exists at all: Pixelmator's `width of layer` reports the SHAPE's
    path bounds, and a stroke renders outside (or inside) that path, so the
    two disagree -- by 7px in width and 9px in height, in OPPOSITE
    directions, on the heart that exposed this. Feeding the wrong extent to
    the smear step count spaces the copies too far apart and the trail
    develops gaps along its flanks.
    """
    try:
        from PIL import Image
    except ImportError:
        return (0, 0)
    try:
        im = Image.open(png_path).convert("RGBA")
    except Exception:
        return (0, 0)
    bbox = im.split()[3].getbbox()
    if not bbox:
        return (0, 0)
    return (bbox[2] - bbox[0], bbox[3] - bbox[1])
