#!/bin/zsh
# Build, sign and install PixProSpeed.app — v2.0.0
#
# Signing uses the Apple Development certificate (renewed 2026-08-05, valid to
# 2027-08-05), selected by SHA-1 HASH rather than by name: the expired 2023
# certificate is still in the keychain under exactly the same name, and signing
# by name can silently pick the dead one.
#
# --timestamp is not optional. A timestamped signature stays valid after the
# certificate expires; without it this app breaks in Aug 2027.
#
# A STABLE identity also matters because macOS ties the Automation grant
# ("PixProSpeed wants to control Pixelmator Pro") to the code signature.
#
# When the certificate is renewed again, put the new hash here:
#   security find-identity -p codesigning | grep "Developer ID Application"
set -e
cd "${0:A:h}"

SIGN_ID="4208ABA3EC12F24C1F09C7BB624EFF68B44259DB"   # Developer ID Application (was Apple Development)

if ! security find-identity -p codesigning | grep -q "$SIGN_ID"; then
    echo "error: signing identity $SIGN_ID not in keychain (renewed cert?)" >&2
    exit 1
fi

echo "==> killing any running instance"
pkill -x PixProSpeed 2>/dev/null || true
sleep 1

echo "==> compiling the AppleScript engine"
rm -f engine.scpt
osacompile -o engine.scpt engine.applescript

echo "==> building"
rm -rf build dist
./venv/bin/python setup.py py2app >/dev/null

# py2app copies liblzma.5.dylib (pulled in by Pillow) in a state codesign
# rejects: it strips the signature but leaves the LC_CODE_SIGNATURE load
# command pointing at a blob that is no longer there, so codesign reports
# "main executable failed strict validation" and then "internal error in
# Code Signing subsystem" when asked to re-sign it. --remove-signature
# cannot repair it either. Copying the pristine dylib back over the top and
# restoring the install name py2app gave it fixes it. Of the 85 nested
# binaries this is the only one affected.
LZMA="dist/PixProSpeed.app/Contents/Frameworks/liblzma.5.dylib"
if [ -f "$LZMA" ] && ! codesign --verify --strict "$LZMA" 2>/dev/null; then
    echo "==> repairing liblzma.5.dylib (py2app leaves it unsignable)"
    cp -f /opt/homebrew/opt/xz/lib/liblzma.5.dylib "$LZMA"
    chmod u+w "$LZMA"
    install_name_tool -id "@executable_path/../Frameworks/liblzma.5.dylib" "$LZMA" 2>/dev/null
fi

# Sign nested binaries individually, then the bundle. --deep is deprecated
# and gives a useless error when one nested file is the problem.
#
# Match on WHAT A FILE IS, not what it is called. Globbing *.dylib and *.so
# missed Contents/MacOS/python and the Python framework binary, both Mach-O
# with no extension, and Apple rejected the notarization for exactly those:
#   "The binary is not signed with a valid Developer ID certificate."
#   "The executable does not have the hardened runtime enabled."
echo "==> signing nested binaries with Developer ID ($SIGN_ID)"
find dist/PixProSpeed.app -type f -print0 | while IFS= read -r -d $'\0' f; do
    if file -b "$f" 2>/dev/null | grep -q 'Mach-O'; then
        codesign --force --timestamp --options runtime --sign "$SIGN_ID" "$f" 2>/dev/null || true
    fi
done
find dist/PixProSpeed.app -name '*.framework' -print0 2>/dev/null \
    | xargs -0 -n1 -I{} codesign --force --timestamp --options runtime --sign "$SIGN_ID" {} 2>/dev/null || true

echo "==> signing the bundle"
codesign --force --timestamp --options runtime \
    --entitlements "$HOME/My_Applications/_signing/pixpro.entitlements" --sign "$SIGN_ID" dist/PixProSpeed.app
codesign --verify --strict dist/PixProSpeed.app

echo "==> installing to /Applications"
rm -rf /Applications/PixProSpeed.app
cp -R dist/PixProSpeed.app /Applications/
xattr -dr com.apple.quarantine /Applications/PixProSpeed.app 2>/dev/null || true

echo "==> installed:"
codesign -dv /Applications/PixProSpeed.app 2>&1 | grep -E "Identifier=|Authority=|Timestamp="
plutil -extract CFBundleShortVersionString raw /Applications/PixProSpeed.app/Contents/Info.plist
echo "==> engine present: $(test -f /Applications/PixProSpeed.app/Contents/Resources/engine.scpt && echo yes || echo NO)"
echo "==> running instances: $(pgrep -x PixProSpeed | wc -l | tr -d ' ')"
echo
echo "The panel is LSUIElement: no Dock icon and no menu bar."
echo "Dismiss, or closing the window, quits it."
