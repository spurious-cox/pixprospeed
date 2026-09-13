"""py2app build for PixProSpeed.app — v2.0.0

This IS PixProSpeed now. The floating panel replaced the AppleScript
applet as the app of that name, so there is one app and one icon rather
than two that looked identical. The applet is preserved at
~/My_Applications/PixProSpeed/PixProSpeed.app if it is ever wanted back.

    ./venv/bin/python setup.py py2app

Use build.sh instead: it also compiles the AppleScript engine, signs with
the Apple Development certificate (by hash, timestamped) and installs.

Pillow is bundled INTO the app, so shape detection no longer depends on
a homebrew python that a brew upgrade can move out from under it.
"""

from setuptools import setup

APP = ["main.py"]

# The build engine ships as a compiled .scpt in Resources and is invoked
# with osascript. Keeping it as a separate file means the layer-building
# logic stays readable AppleScript rather than a Python string.
# The README ships INSIDE the bundle (Contents/Resources) so it travels
# with the app and nothing depends on ~/My_Applications existing.
DATA_FILES = ["engine.scpt", "../PixProSpeed-README.txt"]

OPTIONS = {
    "argv_emulation": False,
    "iconfile": "../PixProSpeed.icns",
    # PIL must be a PACKAGE, not an include. As an "include" py2app buries it
    # inside Contents/Resources/lib/python314.zip -- and Pillow ships its own
    # dylibs (libjpeg, libpng, liblcms2, libbrotli*, libxcb) in PIL/.dylibs.
    # Nothing can codesign a file inside a zip, so all of them stayed unsigned
    # and Apple rejected the submission with 36 errors:
    #   "The binary is not signed with a valid Developer ID certificate."
    #   "The signature does not include a secure timestamp."
    # Listing it under "packages" copies PIL out as a real directory, where
    # the signing pass can actually reach those dylibs.
    "packages": ["pixprospeed", "PIL"],
    "plist": {
        "CFBundleName": "PixProSpeed",
        "CFBundleDisplayName": "PixProSpeed",
        "CFBundleIdentifier": "com.timmccoy.pixprospeed",
        "CFBundleShortVersionString": "2.6.0",
        "CFBundleVersion": "2.6.0",
        "LSMinimumSystemVersion": "13.0",
        "NSHighResolutionCapable": True,
        # A floating utility panel, not an app to switch to: no Dock icon,
        # no menu bar. Dismiss or closing the panel quits it.
        "LSUIElement": True,
        # Needed to drive Pixelmator Pro over Apple events.
        "NSAppleEventsUsageDescription":
            "PixProSpeed controls Pixelmator Pro to build speed trails on your layers.",
        "NSHumanReadableCopyright": "Copyright © 2026 Tim McCoy. All rights reserved.",
        "CFBundleGetInfoString":
            "PixProSpeed — floating controls for motion / speed trails in Pixelmator Pro.",
    },
}

setup(
    name="PixProSpeed",
    app=APP,
    data_files=DATA_FILES,
    options={"py2app": OPTIONS},
    setup_requires=["py2app"],
)
