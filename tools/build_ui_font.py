"""Build the two licensed Google Fonts used by the game UI."""

from pathlib import Path
from io import BytesIO
from urllib.request import urlopen

from fontTools import subset
from fontTools.ttLib import TTFont


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/fonts"


def main() -> None:
    chars = set(range(32, 127))
    for high in range(0xA1, 0xF8):
        for low in range(0xA1, 0xFF):
            try:
                chars.update(ord(c) for c in bytes((high, low)).decode("gb2312"))
            except UnicodeDecodeError:
                pass
    for folder in ("scripts", "scenes", "ui"):
        for path in (ROOT / folder).rglob("*"):
            if path.suffix in {".gd", ".tscn", ".tres", ".json", ".csv"}:
                chars.update(ord(c) for c in path.read_text(encoding="utf-8") if ord(c) > 127)
    for family, source, target, points in (
        ("notosanssc", "NotoSansSC%5Bwght%5D.ttf", "NotoSansSC-UI.ttf", chars),
        ("raleway", "Raleway%5Bwght%5D.ttf", "Raleway-UI.ttf", set(range(32, 127))),
    ):
        base = f"https://raw.githubusercontent.com/google/fonts/main/ofl/{family}/"
        font = TTFont(BytesIO(urlopen(base + source).read()))
        worker = subset.Subsetter()
        worker.populate(unicodes=points)
        worker.subset(font)
        font.save(OUT / target)
        (OUT / f"OFL-{family}.txt").write_bytes(urlopen(base + "OFL.txt").read())
        print(f"{target}: {(OUT / target).stat().st_size / 1024 / 1024:.1f} MiB")


if __name__ == "__main__":
    main()
