"""Checks a CMJ export (or a folder of them) against the report's import rules.

Mirrors the Power Query in queries/CMJ Data.m: header normalisation, column aliases,
CMJ-row filtering, unit conversion (inch ForceDecks exports and Hawkin Dynamics exports),
asymmetry parsing and athlete IDs. Works for VALD ForceDecks and Hawkin Dynamics CSVs. Run it to see
what the report will load before opening Power BI.

Usage:  python tools/check_export.py "C:\\path\\to\\exports"   (defaults to sample_data/)
"""
import csv
import io
import re
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
QUERY = (ROOT / "queries" / "CMJ Data.m").read_text()
SPEC = [(o, re.findall(r'"([^"]+)"', a), t) for o, a, t in re.findall(r'\{"([^"]+)", \{([^}]*)\}, "(\w+)"\}', QUERY)]


def key(h):
    h = (h or "").replace("\ufeff", "").replace("[", "(").replace("]", ")")
    return "".join(h.strip().lower().replace(".", " ").split())


def number(v):
    t = (v or "").replace("%", "").replace(" ", "").replace("\xa0", "")
    try:
        return float(t) if t else None
    except ValueError:
        return None


def to_date(v):
    m = re.match(r"(\d{4})[/.-](\d{1,2})[/.-](\d{1,2})", (v or "").strip())
    if m:  # year first, e.g. 2026/09/08
        try:
            return datetime(*map(int, m.groups())).date()
        except ValueError:
            return None
    for fmt in ("%m/%d/%Y", "%Y-%m-%d", "%m/%d/%Y %I:%M %p", "%m/%d/%Y %H:%M"):
        try:
            return datetime.strptime((v or "").strip(), fmt).date()
        except ValueError:
            pass
    return None


def asym(v):
    tokens = [x for x in re.split(r"[ ()\xa0]", (v or "").upper().replace("%", "")) if x]
    nums = [number(x) for x in tokens if number(x) is not None]
    if not nums:
        return None
    return -abs(nums[0]) if ("L" in tokens or "LEFT" in tokens) else abs(nums[0])


CONVERT = {"text": lambda v: (v or "").strip() or None, "number": number,
           "int": lambda v: None if number(v) is None else round(number(v)), "date": to_date,
           "time": lambda v: (v or "").strip() or None}


def read(p):
    raw = p.read_bytes().decode("utf-8-sig")
    first = raw.split("\n", 1)[0]
    rows = list(csv.reader(io.StringIO(raw), delimiter=";" if first.count(";") > first.count(",") else ","))
    keys, seen = [], []
    for i, h in enumerate(rows[0]):
        k = key(h)
        keys.append(f"{k} #{i}" if k in seen else k)
        seen.append(k)
    out = [dict(zip(keys, r)) for r in rows[1:] if any(c.strip() for c in r)]
    return units(out, keys)


def units(rows, keys):
    """Hawkin exports without units in the headers: work the unit out from the file's typical value."""
    import statistics
    rules = {"jumpheight": lambda m: "m" if m < 1.5 else "in" if m < 28 else "cm",
             "countermovementdepth": lambda m: "m" if m < 1.5 else "in" if m < 20 else "cm",
             "timetotakeoff": lambda m: "s" if m < 5 else "ms",
             "unweightingphase": lambda m: "s" if m < 5 else None,
             "brakingphase": lambda m: "s" if m < 5 else None,
             "systemweight": lambda m: "n" if m > 400 else "lb" if m > 140 else "kg"}
    for col, rule in rules.items():
        if col not in keys:
            continue
        vals = [abs(number(r.get(col))) for r in rows if number(r.get(col)) is not None]
        u = rule(statistics.median(vals)) if vals else None
        if u is None or f"{col}({u})" in keys:
            continue
        for r in rows:
            r[f"{col}({u})"] = r.pop(col, None)
    return rows


REP_DROP_PERCENT = 10  # keep in step with RepDropPercent in queries/CMJ Data.m


def load(folder: Path):
    folder = Path(str(folder).strip().strip('"'))
    files = [folder] if folder.is_file() else sorted(p for p in folder.rglob("*.csv") if not p.name.startswith("~$"))
    rows = [r for f in files for r in read(f)]
    type_col = next((c for c in ("testtype", "type") if any(c in r for r in rows)), None)
    if type_col:
        def is_cmj(t):
            t = (t or "").lower()
            return ("cmj" in t or "countermovement" in t) and not any(x in t for x in ("sl", "single", "rebound"))
        rows = [r for r in rows if is_cmj(r.get(type_col))]
    cols = set().union(*(r.keys() for r in rows)) if rows else set()
    resolved = {o: next((key(a) for a in al if key(a) in cols), None) for o, al, _ in SPEC}
    out = []
    for r in rows:
        o = {name: (CONVERT[t](r.get(resolved[name])) if resolved[name] else None) for name, _, t in SPEC}
        scale = lambda x, f: None if x is None else x * f
        if o["BW [KG]"] is None:
            o["BW [KG]"] = scale(o["__SystemWeightN"], 1 / 9.81) if o["__SystemWeightN"] is not None else scale(o["__SystemWeightLb"], 1 / 2.20462)
        if o["Jump Height (Imp-Mom) (cm)"] is None:
            o["Jump Height (Imp-Mom) (cm)"] = scale(o["__JumpHeightIn"], 2.54) if o["__JumpHeightIn"] is not None else scale(o["__JumpHeightM"], 100)
        if o["Eccentric Duration (ms)"] is None and o["__UnweightingS"] is not None and o["__BrakingPhaseS"] is not None:
            o["Eccentric Duration (ms)"] = round((o["__UnweightingS"] + o["__BrakingPhaseS"]) * 1000)
        if o["Contraction Time (ms)"] is None and o["__TimeToTakeoffS"] is not None:
            o["Contraction Time (ms)"] = round(o["__TimeToTakeoffS"] * 1000)
        if o["Countermovement Depth [cm] "] is None:
            o["Countermovement Depth [cm] "] = scale(o["__DepthM"], 100) if o["__DepthM"] is not None else scale(o["__DepthIn"], 2.54)
        if o["Bodyweight in Pounds [lbs] "] is None:
            o["Bodyweight in Pounds [lbs] "] = scale(o["BW [KG]"], 2.20462)
        ecc = asym(o["Eccentric Braking Impulse % (Asym) (%)"])
        conc = asym(o["Concentric Impulse % (Asym) (%)"])
        o["Eccentric Braking Impulse % (Asym) Direction"] = ecc if ecc is not None else scale(o["__HawkinBrakingIndex"], -1)
        conc = conc if conc is not None else scale(o["__HawkinPropulsiveIndex"], -1)
        o["Concentric Impulse % (Asym) Direction"] = None if conc is None else int(conc)
        for h in [k for k in o if k.startswith("__")]:
            o.pop(h)
        o["Name"] = " ".join((o["Name"] or "").split()) or None
        if o["Name"] is None and o["ExternalId"]:  # de-identified export: fall back to the ExternalId
            o["Name"] = "ID " + " ".join(o["ExternalId"].split())
        if o["Name"] and o["Date"]:
            out.append(o)
    names = sorted({o["Name"] for o in out})
    ids = {n: i for i, n in enumerate(names, 1)}
    unique = {tuple(sorted((k, str(v)) for k, v in o.items())): o for o in out}
    # one row per test, like the Group By step in the query: per session (athlete + date) drop reps more than
    # REP_DROP_PERCENT below the session's best jump height, then average every metric over the rest
    jh = "Jump Height (Imp-Mom) (cm)"
    text_cols = {n for n, _, ty in SPEC if ty in ("text", "time", "date")}
    groups = {}
    for o in unique.values():
        groups.setdefault((o["Name"], o["Date"]), []).append(o)
    sessions, dropped = [], 0
    for reps in groups.values():
        best = max((r[jh] for r in reps if r[jh] is not None), default=None)
        kept = reps if best is None else [r for r in reps if r[jh] is None or r[jh] >= best * (1 - REP_DROP_PERCENT / 100)]
        dropped += len(reps) - len(kept)
        s = {}
        for k in kept[0]:
            vals = [r[k] for r in kept if r.get(k) is not None]
            s[k] = (vals[0] if vals else None) if k in text_cols else (sum(vals) / len(vals) if vals else None)
        sessions.append(s)
    load.reps, load.dropped = len(unique), dropped
    return files, resolved, sessions, ids


if __name__ == "__main__":
    folder = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "sample_data"
    files, resolved, out, ids = load(folder)
    print(f"Folder: {folder}\nFiles:  {', '.join(f.name for f in files) or 'none'}")
    w = max(2, len(str(len(ids))))
    print(f"Reps:   {load.reps} rows, {load.dropped} dropped (more than {REP_DROP_PERCENT}% below that session's best jump)")
    print(f"Loaded: {len(out)} CMJ tests (reps averaged per session), {len(ids)} athletes -> athlete_{1:0{w}d} ... athlete_{len(ids):0{w}d}")
    if out:
        dates = [o["Date"] for o in out]
        print(f"Dates:  {min(dates)} to {max(dates)}")
    report_cols = [o for o, *_ in SPEC if not o.startswith("__")]
    optional = {"Tags", "ExternalId", "Time", "Additional Load [lb]"}
    if not any(o.get("Concentric Impulse % (Asym) (%)") for o in out):   # Hawkin: numeric L|R index instead of text
        optional |= {"Concentric Impulse % (Asym) (%)", "Eccentric Braking Impulse % (Asym) (%)", "Reps",
                     "Velocity at Peak Power [m/s] "}
    missing = [c for c in report_cols if c not in optional and out and all(o.get(c) is None for o in out)]
    print("Columns the report uses that came through empty:", missing or "none")
    print("RESULT:", "PASS" if out and not missing else ("NO CMJ DATA FOUND" if not out else "CHECK COLUMNS ABOVE"))
