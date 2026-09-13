"""PixProSpeedPanel — a floating control panel for PixProSpeed.

Copyright (c) 2026 Tim McCoy. All rights reserved.
Developed with assistance from Claude (Anthropic).

Version 2.5.1 (2026-09-13)

A persistent alternative to the PixProSpeed applet's one-shot dialog.
The panel stays on screen beside Pixelmator Pro: pick a layer, set the
numbers, hit Create Speed, adjust, go again. Dismiss (or closing the
window) quits.

WHY A PANEL AND NOT A DIALOG. The applet's NSAlert is modal, so it has
to be answered and dismissed for every single trail. Iterating on an
effect means relaunching the app each time.

WHY NONACTIVATING. NSWindowStyleMaskNonactivatingPanel plus
NSFloatingWindowLevel means clicking the panel does NOT pull focus away
from Pixelmator, and LSUIElement keeps it out of the Dock and the menu
bar. Same arrangement PixProGrid uses.

MEASURING IS AUTOMATIC, AND THE BUTTON STAYS. Shape detection has to
solo the layer and export it, which flickers the canvas, so the two FREE
signals — a remembered correction and the layer's own rotation — are
applied the instant the selection changes, and the expensive one runs
right after it (AUTO_MEASURE). Measure re-runs that measurement on
demand; set AUTO_MEASURE False to make it the only way in.

THE NOSE PROBLEM. Shape detection finds an axis, not an arrow, and on
car-like silhouettes deciding which end is the front is close to a coin
toss. Rather than guess harder, Flip remembers the correction against
the layer's name and applies it automatically from then on.
"""

import os
import sys
import tempfile
import threading
import time
import traceback

from AppKit import (
    NSApp,
    NSApplication,
    NSBackingStoreBuffered,
    NSBezelStyleRounded,
    NSBox,
    NSButton,
    NSColor,
    NSFontAttributeName,
    NSForegroundColorAttributeName,
    NSFloatingWindowLevel,
    NSFont,
    NSMakeRect,
    NSPanel,
    NSScreen,
    NSStatusWindowLevel,
    NSSwitch,
    NSTextField,
    NSWindowStyleMaskClosable,
    NSWindowStyleMaskNonactivatingPanel,
    NSWindowStyleMaskTitled,
    NSWindowStyleMaskUtilityWindow,
)
from AppKit import (
    NSWindowCollectionBehaviorCanJoinAllSpaces,
    NSWindowCollectionBehaviorFullScreenAuxiliary,
    NSWindowCollectionBehaviorStationary,
)
import objc
from Foundation import NSAttributedString, NSObject, NSTimer
from PyObjCTools import AppHelper

from pixprospeed import detect, pixelmator, state

VERSION = "2.5.1"

PANEL_W = 316
POLL_SECONDS = 1.0
LOG_PATH = os.path.expanduser("~/Library/Logs/PixProSpeed.log")
# Measure a newly selected layer automatically instead of waiting for the
# Measure button. This solos the layer and exports the document, so the
# canvas flickers each time the selection changes — Tim asked for it that
# way, preferring the flicker to clicking Measure for every new object.
# Set False to go back to measuring only on demand.
AUTO_MEASURE = True


def resource(name):
    """Path to a file inside the bundle's Resources, or beside main.py."""
    if getattr(sys, "frozen", None) or ".app/Contents/" in os.path.abspath(__file__):
        base = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Resources")
        candidate = os.path.join(base, name)
        if os.path.exists(candidate):
            return candidate
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), name)


class Controller(NSObject):

    def init(self):
        self = objc.super(Controller, self).init()
        if self is None:
            return None
        self.layer_name = None
        self.layer_rotation = 0.0
        self.suggestion_source = None
        self.flipped = False
        self.busy = False
        self.engine = resource("engine.scpt")
        self._build_panel()
        self._start_timer()
        return self

    # ── UI ───────────────────────────────────────────────────────────
    #
    # Sized and coloured to Tim's mockup: larger type throughout, the
    # layer name prominent, Flip on its own centred row, and the two
    # committing buttons side by side at the bottom — green Create
    # Speed, red Dismiss. setBezelColor_ is what tints a rounded
    # NSButton; setBackgroundColor has no effect on one.

    @objc.python_method
    def _label(self, text, x, y, w, h, size=13, bold=False, color=None, wrap=False):
        f = NSTextField.alloc().initWithFrame_(NSMakeRect(x, y, w, h))
        f.setStringValue_(text)
        f.setBezeled_(False)
        f.setDrawsBackground_(False)
        f.setEditable_(False)
        f.setSelectable_(False)
        f.setFont_(NSFont.boldSystemFontOfSize_(size) if bold
                   else NSFont.systemFontOfSize_(size))
        if color:
            f.setTextColor_(color)
        if wrap:
            f.setUsesSingleLineMode_(False)
            f.cell().setWraps_(True)
        self.panel.contentView().addSubview_(f)
        return f

    @objc.python_method
    def _field(self, value, x, y, w, h=26, size=15):
        f = NSTextField.alloc().initWithFrame_(NSMakeRect(x, y, w, h))
        f.setStringValue_(str(value))
        f.setFont_(NSFont.systemFontOfSize_(size))
        self.panel.contentView().addSubview_(f)
        return f

    @objc.python_method
    def _color_button(self, title, x, y, w, h, action, fill, size=13):
        """A solidly coloured button.

        setBezelColor_ is the obvious call and it does NOT survive here:
        this panel is nonactivating, so its buttons draw in their inactive
        state and the tint is dropped. Drawing the fill on the button's own
        layer renders identically whether the panel is active or not.
        """
        b = NSButton.alloc().initWithFrame_(NSMakeRect(x, y, w, h))
        b.setBordered_(False)
        b.setWantsLayer_(True)
        b.layer().setBackgroundColor_(fill.CGColor())
        b.layer().setCornerRadius_(7.0)
        b.setAttributedTitle_(
            NSAttributedString.alloc().initWithString_attributes_(
                title,
                {NSForegroundColorAttributeName: NSColor.blackColor(),
                 NSFontAttributeName: NSFont.boldSystemFontOfSize_(size)}))
        b.setTarget_(self)
        b.setAction_(action)
        self.panel.contentView().addSubview_(b)
        return b

    @objc.python_method
    def _button(self, title, x, y, w, h, action, size=14, bezel=None, default=False):
        b = NSButton.alloc().initWithFrame_(NSMakeRect(x, y, w, h))
        b.setTitle_(title)
        b.setBezelStyle_(NSBezelStyleRounded)
        b.setFont_(NSFont.systemFontOfSize_(size))
        b.setTarget_(self)
        b.setAction_(action)
        if bezel is not None:
            b.setBezelColor_(bezel)
        if default:
            b.setKeyEquivalent_("\r")
        self.panel.contentView().addSubview_(b)
        return b

    @objc.python_method
    def _build_panel(self):
        W, H = PANEL_W, 350
        panel = NSPanel.alloc().initWithContentRect_styleMask_backing_defer_(
            NSMakeRect(0, 0, W, H),
            NSWindowStyleMaskTitled
            | NSWindowStyleMaskClosable
            | NSWindowStyleMaskUtilityWindow
            | NSWindowStyleMaskNonactivatingPanel,
            NSBackingStoreBuffered,
            False,
        )
        panel.setTitle_("PixProSpeed %s" % VERSION)
        # A utility panel hides itself whenever its own app is deactivated,
        # and since this app is LSUIElement + nonactivating it is ALWAYS
        # deactivated the moment you click back into Pixelmator — the panel
        # simply vanished. setHidesOnDeactivate_(False) alone was not
        # enough; the collection behaviour is what actually keeps a
        # palette on screen across app switches and Spaces.
        panel.setLevel_(NSStatusWindowLevel)
        panel.setHidesOnDeactivate_(False)
        panel.setCollectionBehavior_(
            NSWindowCollectionBehaviorCanJoinAllSpaces
            | NSWindowCollectionBehaviorFullScreenAuxiliary
            | NSWindowCollectionBehaviorStationary
        )
        # Never take key focus away from Pixelmator just by being clicked.
        panel.setBecomesKeyOnlyIfNeeded_(True)
        panel.setReleasedWhenClosed_(False)
        panel.setDelegate_(self)
        self.panel = panel

        M = 14                     # margin
        LBL_W = 78                 # "Direction" / "Distance" / "Subimages"
        FLD_X = M + LBL_W + 6
        FLD_W = 66
        HINT_X = FLD_X + FLD_W + 10

        y = H - 42
        self.layer_label = self._label("Waiting for Pixelmator…", M, y, W - 2 * M, 20,
                                       size=14, bold=True)
        y -= 50
        # Three lines. Measured: the longest note (shape + an applied Flip
        # correction) needs 39pt at this width and font; two lines was
        # cutting it off mid-sentence.
        self.note_label = self._label("", M, y, W - 2 * M, 44, size=10,
                                      color=NSColor.secondaryLabelColor(), wrap=True)

        y -= 40
        self._label("Direction", M, y + 3, LBL_W, 18, size=12)
        self.direction_field = self._field(state.get("direction"), FLD_X, y, FLD_W, h=22, size=12)
        self.measure_button = self._button("Measure", HINT_X, y - 2, 92, 26, b"measure:", size=12)

        y -= 34
        self._label("Distance", M, y + 3, LBL_W, 18, size=12)
        self.distance_field = self._field(state.get("distance"), FLD_X, y, FLD_W, h=22, size=12)
        self._label("px, mm or math", HINT_X, y + 3, 130, 18, size=10,
                    color=NSColor.secondaryLabelColor())

        y -= 34
        self._label("Subimages", M, y + 3, LBL_W, 18, size=12)
        self.subimages_field = self._field(state.get("subimages"), FLD_X, y, FLD_W, h=22, size=12)
        self._label("stutter ghosts", HINT_X, y + 3, 130, 18, size=10,
                    color=NSColor.secondaryLabelColor())

        y -= 36
        self.bg_switch = NSSwitch.alloc().initWithFrame_(NSMakeRect(FLD_X, y, 38, 22))
        self.bg_switch.setState_(1 if state.get_remove_bg() else 0)
        self.panel.contentView().addSubview_(self.bg_switch)
        self._label("Remove background", HINT_X, y + 2, 170, 18, size=12)

        y -= 34
        self.flip_button = self._button("Flip 180°", (W - 118) / 2, y, 118, 26,
                                        b"flip:", size=12)

        y -= 26
        self.status_label = self._label("", M, y, W - 2 * M, 18, size=10,
                                        color=NSColor.secondaryLabelColor())

        y -= 38
        gap = 12
        bw = (W - 2 * M - gap) / 2
        self.create_button = self._color_button(
            "Create Speed", M, y, bw, 32, b"create:",
            NSColor.systemGreenColor())
        self.dismiss_button = self._color_button(
            "Dismiss", M + bw + gap, y, bw, 32, b"dismiss:",
            NSColor.systemRedColor())

        self._place_panel()
        panel.orderFrontRegardless()

    @objc.python_method
    def _place_panel(self):
        """Sit on the right of the main screen, clear of Pixelmator's canvas."""
        screen = NSScreen.mainScreen()
        if screen is None:
            self.panel.center()
            return
        vf = screen.visibleFrame()
        x = vf.origin.x + vf.size.width - PANEL_W - 40
        y = vf.origin.y + vf.size.height - self.panel.frame().size.height - 60
        self.panel.setFrameOrigin_((x, y))

    # ── Polling ──────────────────────────────────────────────────────

    @objc.python_method
    def _start_timer(self):
        self.timer = NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats_(
            POLL_SECONDS, self, b"poll:", None, True)

    def poll_(self, _timer):
        """Track the selected layer and measure it when it changes.

        The two FREE signals — a remembered Flip, then the layer's own
        rotation — are applied immediately from a single property read.
        Shape detection is the expensive one: it solos the layer and
        exports the document, so the canvas flickers. With AUTO_MEASURE
        on it runs anyway on every change; `busy` keeps clicking quickly
        through layers from stacking up measurements.
        """
        if self.busy:
            return
        info = pixelmator.selected_layer()
        if "error" in info:
            self.layer_label.setStringValue_(info["error"])
            if self.layer_name is not None:
                self.layer_name = None
                self.note_label.setStringValue_("")
            return

        if info.get("nested"):
            self.layer_label.setStringValue_("Layer:  %s  (inside a group)" % info["name"])
            self.note_label.setStringValue_(
                "Inside a group — drag it to the top level first, or "
                "PixProSpeed builds from the wrong layer.")
            self.layer_name = None
            return

        if info["name"] == self.layer_name:
            return

        # Selection changed — apply the FREE signals only.
        self.layer_name = info["name"]
        self.layer_rotation = info["rotation"]
        self.flipped = False
        self.layer_label.setStringValue_("Layer:  %s" % info["name"])
        self.status_label.setStringValue_("")

        remembered = state.remembered_flip(info["name"])
        if info["rotation"] != 0:
            direction = info["rotation"] % 360.0
            if remembered:
                direction = (direction + 180.0) % 360.0
                self.flipped = True
            self.direction_field.setStringValue_("%d" % round(direction))
            self.suggestion_source = "rotation"
            note = detect.describe({}, "rotation")
            if remembered:
                note += " Your correction for this layer is applied."
            self.note_label.setStringValue_(note)
        else:
            self.suggestion_source = None
            self.note_label.setStringValue_(
                "No rotation set on this layer.")

        # Then measure the shape, which overrides the free signal whenever
        # the outline actually has a usable axis. measureFinished_ falls
        # back to the rotation reading if it does not.
        if AUTO_MEASURE and not self.busy:
            self.set_busy(True)
            self.note_label.setStringValue_("Measuring the shape…")
            self.setStatus_("Measuring…")
            threading.Thread(target=self._do_measure, args=(info,), daemon=True).start()

    # ── Actions ──────────────────────────────────────────────────────
    #
    # ANYTHING SLOW RUNS ON A BACKGROUND THREAD. Calling the engine
    # straight from a button handler blocked the main run loop for the
    # whole build, which left the panel unresponsive — and an
    # unresponsive LSUIElement panel is exactly what macOS makes vanish.
    # That is why the panel "went away" after Create Speed. UI updates
    # come back through performSelectorOnMainThread_, the same pattern
    # PixProGrid uses.
    #
    # Every handler is also wrapped: an exception escaping a PyObjC
    # action goes into the Objective-C runtime and can take the whole
    # app down with no message. Anything unexpected now lands in
    # ~/Library/Logs/PixProSpeed.log instead.

    @objc.python_method
    def log(self, msg):
        try:
            with open(LOG_PATH, "a") as f:
                f.write("%s  %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg))
        except Exception:
            pass

    def setStatus_(self, text):
        try:
            self.status_label.setStringValue_(text)
        except Exception:
            pass

    @objc.python_method
    def post_status(self, text):
        self.performSelectorOnMainThread_withObject_waitUntilDone_(b"setStatus:", text, False)

    @objc.python_method
    def set_busy(self, busy):
        self.busy = busy
        # Dismiss deliberately stays enabled, so a long build is never a trap.
        for b in (self.create_button, self.measure_button, self.flip_button):
            b.setEnabled_(not busy)
        # A borderless coloured button shows no disabled state of its own,
        # so fade it by hand while a build is running.
        try:
            self.create_button.layer().setOpacity_(0.45 if busy else 1.0)
        except Exception:
            pass

    # ---- measure ----

    def measure_(self, _sender):
        try:
            if self.busy:
                return
            info = pixelmator.selected_layer()
            if "error" in info:
                self.setStatus_(info["error"])
                return
            if info.get("nested"):
                self.setStatus_("That layer is inside a group — drag it to the top level.")
                return
            self.set_busy(True)
            self.setStatus_("Measuring…")
            threading.Thread(target=self._do_measure, args=(info,), daemon=True).start()
        except Exception:
            self.log("measure_ failed:\n" + traceback.format_exc())
            self.set_busy(False)
            self.setStatus_("Measure failed — see ~/Library/Logs/PixProSpeed.log")

    @objc.python_method
    def _do_measure(self, info):
        result = None
        try:
            png = os.path.join(tempfile.gettempdir(), "pixprospeed_detect.png")
            if pixelmator.solo_export(info["index"], png):
                result = detect.measure_shape(png)
            try:
                os.remove(png)
            except OSError:
                pass
        except Exception:
            self.log("_do_measure failed:\n" + traceback.format_exc())
        self.performSelectorOnMainThread_withObject_waitUntilDone_(
            b"measureFinished:", (info, result), False)

    def measureFinished_(self, args):
        try:
            info, result = args
            if result is None:
                self.setStatus_("Could not export the layer to measure it.")
                return
            if not result.get("ok"):
                if info["rotation"] != 0:
                    self.direction_field.setStringValue_("%d" % round(info["rotation"] % 360.0))
                    self.suggestion_source = "rotation"
                    self.note_label.setStringValue_(
                        result.get("note", "") + " Used the layer's rotation.")
                else:
                    self.note_label.setStringValue_(
                        result.get("note", "Could not measure that layer."))
                self.setStatus_("")
                return
            direction = detect.facing_to_direction(result["nose"])
            self.flipped = False
            if state.remembered_flip(info["name"]):
                direction = (direction + 180.0) % 360.0
                self.flipped = True
            self.direction_field.setStringValue_("%d" % round(direction))
            self.suggestion_source = "shape"
            note = detect.describe(result, "shape")
            if self.flipped:
                note += " Your correction for this layer is applied."
            self.note_label.setStringValue_(note)
            self.setStatus_("")
        except Exception:
            self.log("measureFinished_ failed:\n" + traceback.format_exc())
            self.setStatus_("Measure failed — see the log.")
        finally:
            self.set_busy(False)

    # ---- flip ----

    def flip_(self, _sender):
        try:
            current = float(self.direction_field.stringValue().strip())
        except ValueError:
            self.setStatus_("Direction is not a number.")
            return
        try:
            self.direction_field.setStringValue_("%d" % round((current + 180.0) % 360.0))
            self.flipped = not self.flipped
            if self.layer_name:
                state.remember_flip(self.layer_name, self.flipped)
                self.setStatus_("Remembered for %s." % self.layer_name if self.flipped
                                else "Correction for %s cleared." % self.layer_name)
        except Exception:
            self.log("flip_ failed:\n" + traceback.format_exc())

    # ---- create ----

    def create_(self, _sender):
        try:
            if self.busy:
                return
            try:
                direction = float(self.direction_field.stringValue().strip())
            except ValueError:
                self.setStatus_("Direction must be a number in degrees.")
                return

            distance = self._resolve_distance(self.distance_field.stringValue().strip())
            if distance is None:
                self.setStatus_("Distance must be a number, 5mm, or math.")
                return
            if distance < 1:
                self.setStatus_("Distance must be at least 1 pixel.")
                return

            try:
                subimages = int(float(self.subimages_field.stringValue().strip()))
            except ValueError:
                self.setStatus_("Subimages must be a number.")
                return
            subimages = max(0, min(24, subimages))

            remove_bg = self.bg_switch.state() == 1
            state.set_settings(int(round(direction)), int(round(distance)),
                               subimages, remove_bg)

            self.set_busy(True)
            self.setStatus_("Building…")
            self.log("build start: dir=%d dist=%d subs=%d bg=%s"
                     % (round(direction), round(distance), subimages, remove_bg))
            threading.Thread(
                target=self._do_build,
                args=(int(round(direction)), distance, subimages, remove_bg),
                daemon=True).start()
        except Exception:
            self.log("create_ failed:\n" + traceback.format_exc())
            self.set_busy(False)
            self.setStatus_("Build failed — see ~/Library/Logs/PixProSpeed.log")

    @objc.python_method
    def _do_build(self, direction, distance, subimages, remove_bg):
        try:
            # True rendered footprint, measured from pixels rather than taken
            # from `width of layer` -- a stroke renders outside (or inside)
            # the shape's path, so the two disagree and the smear step count
            # comes out wrong, leaving gaps along the trail's flanks.
            #
            # Skipped when Remove background is on: the export still has the
            # background, so the measurement would cover the whole rectangle.
            # (0, 0) tells the engine to fall back to `width of layer`.
            foot_w = foot_h = 0
            if not remove_bg:
                info = pixelmator.selected_layer()
                if "error" not in info:
                    foot_w, foot_h = pixelmator.footprint(info["index"])
                    self.log("footprint measured: %sx%s (layer reports %sx%s)"
                             % (foot_w, foot_h,
                                abs(info.get("width", 0)), abs(info.get("height", 0))))
            ok, message = pixelmator.run_engine(
                self.engine, direction, distance, subimages, remove_bg,
                foot_w, foot_h)
        except Exception:
            self.log("_do_build failed:\n" + traceback.format_exc())
            ok, message = False, "Build failed — see the log."
        self.log("build done: ok=%s msg=%s" % (ok, message))
        self.performSelectorOnMainThread_withObject_waitUntilDone_(
            b"buildFinished:", (ok, message), False)

    def buildFinished_(self, args):
        try:
            ok, message = args
            self.setStatus_(("Built %s." % message) if ok else message)
            # The engine groups the layers, so whatever is selected now is
            # not what we measured. Force the next poll to re-read it.
            self.layer_name = None
        except Exception:
            self.log("buildFinished_ failed:\n" + traceback.format_exc())
        finally:
            self.set_busy(False)

    @objc.python_method
    def _resolve_distance(self, text):
        """Pixels, millimetres (5mm), or arithmetic (72/25.4*5).

        eval() is fenced: the string must match a strict numeric/operator
        pattern first, and it runs with no builtins.
        """
        import re
        if not text:
            return None
        expr = re.sub(r"([0-9.]+)\s*mm",
                      lambda m: str(float(m.group(1)) * 72.0 / 25.4), text)
        if not re.fullmatch(r"[0-9+\-*/(). ]+", expr):
            return None
        try:
            return float(eval(expr, {"__builtins__": {}}, {}))
        except Exception:
            return None

    def applicationShouldHandleReopen_hasVisibleWindows_(self, _app, _flag):
        """Clicking the Dock icon again brings the panel back to the front.

        The app is LSUIElement, so it has no Dock icon of its own while
        running — but it can sit in the Dock as a launcher, and clicking
        that should re-show the panel rather than do nothing.
        """
        try:
            self.panel.orderFrontRegardless()
        except Exception:
            pass
        return True

    def dismiss_(self, _sender):
        NSApp().terminate_(self)

    def windowShouldClose_(self, _sender):
        NSApp().terminate_(self)
        return True


def main():
    app = NSApplication.sharedApplication()
    controller = Controller.alloc().init()
    app.setDelegate_(controller)
    AppHelper.runEventLoop()


if __name__ == "__main__":
    main()
