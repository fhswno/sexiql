import os

app_path = defines.get("app", "build/SexiQL.app")

format = "UDZO"
size = None

files = [app_path]
symlinks = {"Applications": "/Applications"}
background = "Assets/dmg-background.png"

icon_size = 128
default_view = "icon-view"
window_rect = ((200, 200), (660, 400))
show_icon_preview = False

app_name = os.path.basename(app_path)
icon_locations = {
    app_name: (205, 168),
    "Applications": (455, 168),
}
