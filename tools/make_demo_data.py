"""Simulated ForceDecks countermovement-jump export for the CMJ Monitoring Report demo.

Built from scratch: no real athlete data is used or derived. Values come from simple
physical relationships (jump height from takeoff velocity, force from bodyweight and
countermovement depth) plus athlete traits, a season-long training/fatigue trend,
return-to-play recovery curves, and test-retest noise in line with published CMJ typical
error (~2-3% for output metrics, ~6-15% for timing and RFD metrics).

Demo Athlete 01 ("Athlete A") is a simulated patellar tendon case for the individual page:
a stable baseline; from mid-May a growing left-side braking bias; from late May a slide in output
with a slower, stiffer-legged strategy that peaks at the end of June; an intervention on 2026-07-20
(training adjusted, interventions added, IDT involved); then a return to baseline while propulsive
asymmetry is slower to return. The shape is illustrative only.

Also writes the same simulated season as a Hawkin Dynamics style export
(sample_data/hawkin_cmj_demo.csv) so the Hawkin import path can be tested.

Output matches the header layout of a ForceDecks CMJ export, including bracketed units
and trailing spaces.
"""
import csv
import math
import random
from datetime import date, timedelta
from pathlib import Path

SEED = 2026
OUT_SIZE = 0.06      # Athlete A: output drop at the worst point
ASYM_SIZE = 10       # Athlete A: extra braking asymmetry (percentage points)
CT_SIZE = 0.06       # Athlete A: slower contraction time at the worst point
CASE_SEED = 4         # noise stream for the case athlete (illustrative demo)
DEPTH_SIZE = 0.04    # Athlete A: shallower countermovement at the worst point
G = 9.81
OUT = Path(__file__).resolve().parent.parent / "sample_data" / "forcedecks_cmj_demo.csv"
OUT_HAWKIN = OUT.with_name("hawkin_cmj_demo.csv")

HAWKIN_HEADERS = ["Athlete", "Test Type", "Date", "Time", "System Weight(N)", "Jump Height(m)",
                  "Peak Relative Propulsive Power(W/kg)", "Braking RFD(N/s)", "Time To Takeoff(s)",
                  "Positive Impulse(N.s)", "Countermovement Depth(m)", "Takeoff Velocity(m/s)",
                  "Stiffness(N/m)", "Force at Min Displacement(N)", "Avg. Propulsive Force(N)",
                  "L|R Braking Impulse Index(%)", "L|R Propulsive Impulse Index(%)",
                  "Unweighting Phase(s)", "Braking Phase(s)"]

CASE_NAME = "Demo Athlete 01"            # Athlete A - simulated patellar tendon case
CASE_ASYM_START = date(2026, 5, 4)      # braking asymmetry starts to build (loading one leg more)
CASE_ASYM_FULL = date(2026, 6, 8)       # asymmetry fully developed
CASE_SLIDE_START = date(2026, 5, 18)     # output and strategy start to slip
CASE_PEAK = date(2026, 6, 29)            # worst point (end of June)
CASE_INTERVENTION = date(2026, 7, 20)    # training adjusted, interventions added, IDT involved

HEADERS = ["Name", "ExternalId", "Test Type", "Date", "Time", "BW [KG]", "Reps", "Tags", "Additional Load [lb]",
           "Jump Height (Imp-Mom) [cm]", "Contraction Time [ms] ", "Peak Power / BM [W/kg] ",
           "Bodyweight in Pounds [lbs] ", "CMJ Stiffness [N/m] ", "Vertical Velocity at Takeoff [m/s] ",
           "Eccentric Braking RFD [N/s] ", "Positive Impulse [N s] ", "Concentric Mean Force [N] ",
           "Concentric Impulse % (Asym) (%)", "Velocity at Peak Power [m/s] ", "Force at Zero Velocity [N] ",
           "Countermovement Depth [cm] ", "Eccentric Braking Impulse % (Asym) (%)", "Eccentric Duration [ms] "]

SEASON_START = date(2026, 2, 16)   # Monday of the first testing week
SEASON_END = date(2026, 9, 28)


def asym_text(value: float) -> str:
    """ForceDecks style: magnitude then the side that is higher, e.g. '6.4 L'."""
    side = "L" if value < 0 else "R"
    return f"{abs(value):.1f} {side}"


def make_athletes(rng: random.Random, n_healthy: int = 16, n_rtp: int = 4):
    athletes = []
    for i in range(n_healthy + n_rtp):
        rtp = i >= n_healthy
        bw = rng.uniform(80, 106)
        if i == 0:
            bw = 92.0
        athletes.append({
            "name": f"Demo Athlete {i + 1:02d}",
            "ext": f"DEMO{i + 1:03d}",
            "bw": bw,
            "jh_in": rng.uniform(14.5, 20.5) - (bw - 92) * 0.04,   # heavier athletes jump slightly less
            "ct_ms": rng.uniform(660, 900),                          # strategy trait: fast vs slow countermovement
            "depth_cm": rng.uniform(27, 38),
            "asym_bias": rng.gauss(0, 3.0),                         # habitual side bias
            "rtp": rtp,
            # return-to-play athletes start testing part-way through the season
            "start": SEASON_START + timedelta(weeks=rng.randint(6, 14)) if rtp else SEASON_START,
            "injured_side": rng.choice([-1, 1]),
            "attendance": rng.uniform(0.8, 0.95),
        })
        if i == 0:
            athletes[-1].update({"jh_in": 18.6, "ct_ms": 760, "depth_cm": 33, "asym_bias": -3.5})
    return athletes


def season_effect(d: date) -> float:
    """Multiplier on output: pre-season build, mild mid-summer fatigue dip, late-season recovery."""
    week = (d - SEASON_START).days / 7
    build = 0.03 * (1 - math.exp(-week / 4))
    fatigue = -0.012 * math.exp(-((week - 22) / 5) ** 2)
    return 1 + build + fatigue


def rtp_effect(weeks_in: float) -> float:
    """Return-to-play recovery: starts ~22% down and closes toward baseline."""
    return 1 - 0.22 * math.exp(-weeks_in / 6)


def ramp(d: date, start: date, full: date) -> float:
    return min(1.0, max(0.0, (d - start).days / (full - start).days))


def case_load(d: date) -> float:
    """Athlete A's output/strategy slide: 0 at baseline, peaks at the end of June, eases slightly, then fades after the intervention."""
    if d < CASE_INTERVENTION:
        return ramp(d, CASE_SLIDE_START, CASE_PEAK) ** 2 - 0.3 * ramp(d, CASE_PEAK, CASE_INTERVENTION)   # slow start, worst at the end of June
    return max(0.0, 0.7 * (1 - (d - CASE_INTERVENTION).days / 21))


def case_asym_load(d: date) -> float:
    """Athlete A's braking asymmetry: builds from mid-May, holds until the intervention, then drops quickly."""
    if d < CASE_INTERVENTION:
        return ramp(d, CASE_ASYM_START, CASE_ASYM_FULL)
    return max(0.0, 1 - (d - CASE_INTERVENTION).days / 10)


def simulate(rng: random.Random):
    # eccentric duration uses its own random stream so adding it left every other simulated value unchanged
    ecc_rng = random.Random(SEED + 1)
    case_rng = random.Random(SEED + CASE_SEED)
    rows, hawkin_rows = [], []
    for a in make_athletes(rng):
        ecc_share = ecc_rng.uniform(0.56, 0.64)                          # eccentric phase as a share of contraction time
        d = a["start"]
        step = 14 if a["rtp"] else 7
        is_case = a["name"] == CASE_NAME
        r = case_rng if is_case else rng                               # the case athlete has his own noise stream
        while d <= SEASON_END:
            if is_case or r.random() < a["attendance"]:
                test_day = d + timedelta(days=0 if is_case else r.choice([0, 0, 1, 2]))
                weeks_in = (test_day - a["start"]).days / 7
                load = case_load(test_day) if is_case else 0.0
                # after the intervention, propulsive (concentric) asymmetry is slower to return
                conc_lag = 0.65 if is_case and test_day >= CASE_INTERVENTION else 0.0
                scale = season_effect(test_day) * (rtp_effect(weeks_in) if a["rtp"] else 1) * (1 - OUT_SIZE * load)

                bw = a["bw"] + r.gauss(0, 0.5) - (0.6 if a["rtp"] and weeks_in < 6 else 0)
                jh_in = a["jh_in"] * scale * (1 + r.gauss(0, 0.025))
                jh_m = jh_in * 0.0254
                v_to = math.sqrt(2 * G * jh_m)                                   # impulse-momentum
                depth_m = a["depth_cm"] / 100 * (1 + r.gauss(0, 0.06))
                ct = a["ct_ms"] * (1 + r.gauss(0, 0.08)) * (1 + (0.12 * math.exp(-weeks_in / 6) if a["rtp"] else 0)) * (1 + CT_SIZE * load)
                depth_m *= 1 - DEPTH_SIZE * load                                       # shallower, stiffer-legged dip
                conc_mean_f = bw * G + bw * v_to ** 2 / (2 * depth_m)             # work-energy over the push-off
                f_zero_v = conc_mean_f * r.uniform(1.10, 1.18)
                stiffness = f_zero_v / depth_m
                ecc_rfd = (f_zero_v - bw * G) / (ct / 1000 * 0.45) * r.uniform(0.9, 1.1) * (1 - 0.12 * load)
                # eccentric duration (start of movement to zero velocity) = part of contraction time, ~4% extra noise
                ecc_dur = ct * ecc_share * (1 + ecc_rng.gauss(0, 0.04))
                unweight = ecc_dur * ecc_rng.uniform(0.42, 0.48)                 # Hawkin splits it into unweighting + braking
                pos_impulse = bw * v_to * r.uniform(1.12, 1.18)
                pp_bm = v_to * r.uniform(20.7, 21.2)
                v_pp = v_to * r.uniform(0.93, 0.96)

                rtp_asym = a["injured_side"] * 18 * math.exp(-weeks_in / 7) if a["rtp"] else 0
                case_asym = -(ASYM_SIZE * case_asym_load(test_day)) if is_case else 0                       # left side doing more (L = negative)
                conc_case = -(8 * max(load, conc_lag * max(0.0, 1 - (test_day - CASE_INTERVENTION).days / 120))) if is_case else 0
                conc_asym = a["asym_bias"] + rtp_asym + conc_case + r.gauss(0, 2.5 if not is_case else 1.6)
                ecc_asym = a["asym_bias"] * 1.2 + rtp_asym * 1.3 + case_asym + r.gauss(0, 3.5 if not is_case else 2.4)

                hour = r.choice([7, 8, 8, 9, 9, 10])
                minute = r.randint(0, 59)
                hawkin_rows.append([
                    a["name"], "Countermovement Jump", test_day.isoformat(), f"{hour:02d}:{minute:02d}:00",
                    f"{bw * G:.1f}", f"{jh_m:.4f}", f"{pp_bm:.2f}", f"{ecc_rfd:.0f}", f"{ct / 1000:.3f}",
                    f"{pos_impulse:.1f}", f"{-depth_m:.4f}", f"{v_to:.3f}", f"{stiffness:.0f}",
                    f"{f_zero_v:.0f}", f"{conc_mean_f:.0f}",
                    # Hawkin L|R index: positive = left higher (the report uses left negative)
                    f"{-ecc_asym:.1f}", f"{-conc_asym:.1f}",
                    f"{unweight / 1000:.3f}", f"{(ecc_dur - unweight) / 1000:.3f}",
                ])
                rows.append([
                    a["name"], a["ext"], "CMJ", f"{test_day.month}/{test_day.day}/{test_day.year}",
                    f"{hour}:{minute:02d} AM", f"{bw:.1f}", 3, "", 0,
                    f"{jh_in * 2.54:.1f}", f"{ct:.0f}", f"{pp_bm:.2f}", f"{bw * 2.20462:.1f}", f"{stiffness:.0f}",
                    f"{v_to:.3f}", f"{ecc_rfd:.0f}", f"{pos_impulse:.1f}", f"{conc_mean_f:.0f}",
                    asym_text(conc_asym), f"{v_pp:.3f}", f"{f_zero_v:.0f}", f"{-depth_m * 100:.1f}",
                    asym_text(ecc_asym), f"{ecc_dur:.0f}",
                ])
            d += timedelta(days=step)
    rows.sort(key=lambda r: (date(*map(int, (r[3].split("/")[2], r[3].split("/")[0], r[3].split("/")[1]))), r[0]))
    hawkin_rows.sort(key=lambda r: (r[2], r[0]))
    return rows, hawkin_rows


if __name__ == "__main__":
    rows, hawkin_rows = simulate(random.Random(SEED))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    for path, header, data in ((OUT, HEADERS, rows), (OUT_HAWKIN, HAWKIN_HEADERS, hawkin_rows)):
        with open(path, "w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(header)
            w.writerows(data)
        print(f"{len(data)} tests for {len({r[0] for r in data})} simulated athletes -> {path}")
