#!/usr/bin/env python3
"""Build reshelf's styled install DMG with dmgbuild.

    python3 scripts/dmg/build_dmg.py --app <reshelf.app> --out <reshelf-x.y.z.dmg> --volname "reshelf x.y.z"

Called by scripts/release.sh (signing and notarizing stay there). Adapted from
cotabby's build_release_dmg.py: the background art is drawn in background.svg
(660x400 pt), rendered at 1x and 2x and combined into one multi-resolution
TIFF so Finder picks the sharp one on Retina screens. The app and Applications
icons sit centered in the two drop spots drawn in that art — move them
together.
"""
import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
WIDTH, HEIGHT = 660, 400
# dmgbuild's window_rect is Finder's whole window, title bar included; without
# this the bottom of the art is cut off until the window is resized.
TITLE_BAR = 28
ICON_SIZE = 96
APP_ICON_CENTER = (180, 192)
APPLICATIONS_CENTER = (480, 192)


def run(cmd):
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        sys.stderr.write(result.stdout + result.stderr)
        raise SystemExit(f"failed: {' '.join(map(str, cmd))}")


def render_background(workdir: Path) -> Path:
    svg = HERE / "background.svg"
    one, two = workdir / "bg.png", workdir / "bg@2x.png"
    run(["rsvg-convert", "-w", str(WIDTH), "-h", str(HEIGHT), str(svg), "-o", str(one)])
    run(["rsvg-convert", "-w", str(WIDTH * 2), "-h", str(HEIGHT * 2), str(svg), "-o", str(two)])
    tiff = workdir / "background.tiff"
    run(["tiffutil", "-cathidpicheck", str(one), str(two), "-out", str(tiff)])
    return tiff


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--volname", required=True)
    args = parser.parse_args()

    try:
        import dmgbuild
    except ImportError:
        raise SystemExit("dmgbuild is missing — release.sh installs it into .build/dmgbuild-venv.")

    app = args.app.resolve()
    if not (app / "Contents" / "Info.plist").exists():
        raise SystemExit(f"not an app bundle: {app}")

    with tempfile.TemporaryDirectory() as tmp:
        background = render_background(Path(tmp))
        settings = {
            "files": [str(app)],
            "symlinks": {"Applications": "/Applications"},
            "format": "UDZO",
            "default_view": "icon-view",
            "show_status_bar": False,
            "show_tab_view": False,
            "show_toolbar": False,
            "show_pathbar": False,
            "show_sidebar": False,
            "background": str(background),
            "window_rect": ((200, 160), (WIDTH, HEIGHT + TITLE_BAR)),
            "icon_size": ICON_SIZE,
            "text_size": 12,
            "label_pos": "bottom",
            "arrange_by": None,
            "icon_locations": {
                app.name: APP_ICON_CENTER,
                "Applications": APPLICATIONS_CENTER,
            },
        }
        args.out.parent.mkdir(parents=True, exist_ok=True)
        if args.out.exists():
            args.out.unlink()
        dmgbuild.build_dmg(str(args.out), args.volname, settings=settings)
    print(f"DMG: {args.out}")


if __name__ == "__main__":
    main()
