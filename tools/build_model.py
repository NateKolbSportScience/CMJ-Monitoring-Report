"""Copies the readable Power Query files in queries/ into the Power BI model (TMDL) and embeds
sample_data/forcedecks_cmj_demo.csv as the built-in demo export.

Run after editing queries/*.m or regenerating the demo data:
    python tools/make_demo_data.py
    python tools/build_model.py
"""
import base64
import re
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TABLES = ROOT / "CMJMonitoringReport.SemanticModel" / "definition" / "tables"


def deflate_b64(data: bytes) -> str:
    c = zlib.compressobj(9, zlib.DEFLATED, -15)          # raw deflate = Power Query Compression.Deflate
    return base64.b64encode(c.compress(data) + c.flush()).decode()


def table_file(name: str) -> Path:
    """The .tmdl file that declares this table (Power BI may not have renamed the file yet)."""
    decl = re.compile(r"^table (?:'" + re.escape(name) + r"'|" + re.escape(name) + r")\s*$", re.M)
    for f in TABLES.glob("*.tmdl"):
        if decl.search(f.read_text(encoding="utf-8")):
            return f
    raise SystemExit(f"no table '{name}' in {TABLES}")


def set_partition(table_file: Path, m_code: str):
    text = table_file.read_text(encoding="utf-8")
    body = "\n".join("\t\t\t\t" + line for line in m_code.rstrip("\n").split("\n"))
    new, n = re.subn(r"(\tpartition [^\n]+ = m\n\t\tmode: import\n\t\tsource =\n)(.*?)(\n\n\tannotation )",
                     lambda m: m.group(1) + body + m.group(3), text, count=1, flags=re.S)
    if n != 1:
        raise SystemExit(f"partition not found in {table_file.name}")
    table_file.write_text(new, encoding="utf-8")


if __name__ == "__main__":
    demo = (ROOT / "sample_data" / "forcedecks_cmj_demo.csv").read_bytes()
    cmj = (ROOT / "queries" / "CMJ Data.m").read_text(encoding="utf-8").replace("DEMO_DATA_BASE64", deflate_b64(demo))
    set_partition(table_file("CMJ Data"), cmj)
    for name in ("athleteid",):
        set_partition(table_file(name), (ROOT / "queries" / f"{name}.m").read_text(encoding="utf-8"))
    print("model queries updated")
