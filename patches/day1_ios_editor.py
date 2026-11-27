from pathlib import Path
import re

# 1. Allow target=editor in platform/ios/detect.py if blocked
detect_path = Path("platform/ios/detect.py")
text = detect_path.read_text()
patched = re.sub(
    r'if\s+env\.editor_build\s*:\s*\n(\s+.*?sys\.exit\([^)]*\))',
    'if False: # iGodot: allow iOS editor build\n\\1',
    text,
    flags=re.DOTALL,
)
if patched != text:
    detect_path.write_text(patched)
    print("Patched platform/ios/detect.py to allow target=editor")
else:
    print("platform/ios/detect.py did not block editor_build")

# 2. Ensure iOS Xcode Info.plist exposes Documents to Files / Xogot / Desktop sync
plist_path = Path("misc/dist/ios_xcode/godot_ios-Info.plist")
if plist_path.exists():
    plist = plist_path.read_text()
    if "UIFileSharingEnabled" not in plist:
        inject = (
            "\t<key>UIFileSharingEnabled</key>\n\t<true/>\n"
            "\t<key>LSSupportsOpeningDocumentsInPlace</key>\n\t<true/>\n"
            "</dict>"
        )
        plist = plist.replace("</dict>", inject, 1)
        plist_path.write_text(plist)
        print("Enabled Files app document sharing in Info.plist")
