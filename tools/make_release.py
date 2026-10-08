"""Build the download zip for a GitHub Release: dist/CMJ-Monitoring-Report.zip

Contents (at the top of the zip, so Windows' Extract All gives one CMJ-Monitoring-Report folder):
    CMJ Monitoring Report.pbit      export it from Power BI first: File > Export > Power BI template
    data/PUT YOUR CSV EXPORTS HERE.txt
    START HERE.pdf                  docs/START HERE.pdf (the getting-started guide)

No sample data and no real exports go in the zip.

    python tools/make_release.py
"""
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FILES = {
    ROOT / "CMJ Monitoring Report.pbit": "CMJ Monitoring Report.pbit",
    ROOT / "data" / "PUT YOUR CSV EXPORTS HERE.txt": "data/PUT YOUR CSV EXPORTS HERE.txt",
    ROOT / "docs" / "START HERE.pdf": "START HERE.pdf",
}

missing = [str(p.relative_to(ROOT)) for p in FILES if not p.exists()]
if missing:
    sys.exit("Missing: " + ", ".join(missing))

out = ROOT / "dist" / "CMJ-Monitoring-Report.zip"
out.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for src, name in FILES.items():
        z.write(src, name)
print(f"Built {out.relative_to(ROOT)} ({out.stat().st_size // 1024} KB)")
print("Attach it to a new release on GitHub: Releases > Draft a new release > attach the zip > Publish.")
