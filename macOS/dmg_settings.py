# The installer's window, for dmgbuild (build_app.sh with DMG=1). Isola on the left, Applications on the right, over
# Resources/DMGBackground.png (and its @2x), which is drawn in Resources/DMGBackground.html to fit these positions.
# Paths are relative to macOS/; build_app.sh passes the app with -D app=build/Isola.app.

files = [defines["app"]]  # noqa: F821, dmgbuild provides defines
symlinks = {"Applications": "/Applications"}
# No hide_extensions: with it, Finder showed Isola greyed out with an hourglass, as if still copying. Finder leaves .app
# off anyway unless it is set to show every extension.

icon = "Resources/AppIcon.icns"
background = "Resources/DMGBackground.png"
format = "ULFO"
filesystem = "HFS+"

window_rect = ((200, 140), (660, 440))
default_view = "icon-view"
icon_size = 128
text_size = 13
icon_locations = {
    "Isola.app": (170, 220),
    "Applications": (490, 220),
    # Out of sight below the window, for anyone who shows hidden files.
    ".background.tiff": (110, 640),
    ".VolumeIcon.icns": (330, 640),
    ".fseventsd": (550, 640),
}
