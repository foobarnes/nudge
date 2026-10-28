# dmgbuild settings for the Nudge install window. Called by scripts/make-dmg.sh, which passes:
#   -D app=<path to Nudge.app>  -D background=<path to background.png>  -D icon=<.icns for the volume, optional>
# dmgbuild writes the window's .DS_Store directly, so no Finder or AppleScript is needed (headless CI is fine).
# Positions match scripts/dmg/render.swift, which draws the background.
import os

_app = defines["app"]  # noqa: F821 (injected by dmgbuild)

format = "UDZO"
filesystem = "HFS+"
files = [_app]
symlinks = {"Applications": "/Applications"}
icon = defines.get("icon") or None  # noqa: F821

# dmgbuild pairs background.png with background@2x.png into one HiDPI TIFF.
background = defines["background"]  # noqa: F821
# Finder's window_rect is the frame, title bar included; 432 leaves the 400 pt background fully visible.
window_rect = ((200, 120), (660, 432))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True
include_list_view_settings = False

icon_size = 128
text_size = 13
label_pos = "bottom"
arrange_by = None
icon_locations = {
    os.path.basename(_app): (180, 176),
    "Applications": (480, 176),
}
