# CMJ Monitoring Report (Power BI)

<!-- Add screenshots once taken: assets/team-readiness.png and assets/individual-report.png -->

A plug-and-play Power BI report for countermovement jump (CMJ) monitoring on **VALD ForceDecks or Hawkin Dynamics**. Drop in your exports and it works the way monitoring should: start with the whole team, find who is genuinely off their normal, then zoom in on that athlete.

The idea behind it: **good monitoring isn't reacting to every number, it's being able to tell real change from noise.** Every athlete is compared with their own history, every metric is judged against its own day-to-day noise, and a single red cell is not treated as a flag.

> **All data in this repo is simulated** for education and portfolio purposes. It doesn't represent any real athlete or organisation.

---

## The two pages

### 1. Team Readiness: who do I need to look at?

A grid of every athlete across Dr. Matt Jordan's six CMJ metrics, split into what the athlete produced and how they produced it:

| Output | Strategy |
|---|---|
| Jump height | Contraction time |
| Peak power / BM | Eccentric braking RFD |
| Positive impulse | Countermovement depth |

Each cell is coloured by how far the athlete's latest test sits from their own normal: **green** normal, **amber** beyond the smallest worthwhile change (0.5–1 SD worse), **red** more than 1 SD worse. Asymmetry and strategy bar charts sit alongside, and an "as of" date lets you look back at any point in the season.

**Flagging.** With six metrics, most athletes will show one red cell on any given day just from test-to-test noise. So an athlete is only **flagged when at least one output metric and at least one strategy metric are both more than 1 SD worse** on the same test. Output and strategy moving together is a pattern; one cell on its own usually isn't.

### 2. Individual Report: what is actually going on?

Pick an athlete to see all six metrics across the season. Each chart shows:

- the athlete's **normal** (gold line) and **SWC band** (normal ± 0.5 SD, dashed)
- tests **beyond SWC** (amber) and **more than 1 SD worse** (red)
- a **▲ on intervention dates**, so you can see what happened after a change

On the right: the **asymmetry trend** (eccentric braking and concentric impulse, ±10% guides), the athlete's **day-to-day noise** for each metric (CV %), and their **interventions**.

The CV table is there for a reason. Output metrics are usually quiet (a CV of about 2–3%), while timing and RFD metrics are noisy (often 10% or more). A 5% drop in jump height is a real change; a 5% drop in braking RFD may be an ordinary day.

**Interventions.** Log what you changed in the `Interventions` table (Transform data → Interventions): athlete, date and a note. Type the athlete as the report shows the name (`athlete_01` … while `AnonymizeNames` is on).

**The demo case.** `athlete_01` is a simulated case built to show the workflow: a stable baseline through spring; eccentric asymmetry starting to climb in late May; then a sustained slide in output from June with a slower, stiffer countermovement; an intervention on 20 July; output back to normal in August while concentric asymmetry is slower to return. On page 1, set the as-of date to early July to see the team view at the point the flag appears.

---

## Quick start

1. Install [Power BI Desktop](https://powerbi.microsoft.com/desktop/) (Windows).
2. Download this repo (**Code → Download ZIP**) and **extract it**. Power BI can't open a project from inside a zip.
3. Open **`CMJMonitoringReport.pbip`** and click **Refresh**.

The simulated demo data is built into the report, so there's nothing to set up.

## Using your own data

1. Export CMJ tests as CSV into a folder, from VALD Hub (ForceDecks) or the Hawkin Dynamics cloud. You can keep adding exports over time.
2. In Power BI: **Transform data → Edit parameters** (inside Power Query: **Manage Parameters**).
3. Paste the folder path into **DataFolder**, for example `C:\Users\you\Documents\CMJ exports`.
4. **Refresh.** Clear DataFolder at any time to go back to the demo.

| Parameter | What it does |
|---|---|
| `DataFolder` | Blank = built-in demo. A folder path = every CSV in that folder and its subfolders. |
| `AnonymizeNames` | `true` shows `athlete_01, athlete_02 …` instead of names. Keep this on for screenshots and anything you share. |
| `ExportCulture` | `en-US` for MM/DD/YYYY dates, `en-GB` / `en-AU` for DD/MM/YYYY. |

### VALD and Hawkin

Both systems load into the same columns:

| Report metric | VALD ForceDecks | Hawkin Dynamics |
|---|---|---|
| Jump height (cm) | Jump Height (Imp-Mom) | Jump Height (m → cm) |
| Peak power / BM | Peak Power / BM | Peak Relative Propulsive Power |
| Positive impulse | Positive Impulse | Positive Impulse |
| Contraction time (ms) | Contraction Time | Time To Takeoff (s → ms) |
| Eccentric braking RFD | Eccentric Braking RFD | Braking RFD |
| Countermovement depth (cm) | Countermovement Depth | Countermovement Depth (m → cm) |
| Asymmetry (L – / R +) | Braking / concentric impulse % (Asym) | L\|R Braking / Propulsive Impulse Index (sign flipped) |

The two systems detect jump phases slightly differently, so compare athletes within one system rather than across them. Because every athlete is compared with their own history, that doesn't affect the flags.

### Built for real-world exports

- Column order doesn't matter, and extra columns are ignored.
- A missing column comes through blank instead of breaking the refresh.
- Header quirks are handled: trailing spaces, `[unit]` vs `(unit)`, spacing and capitalisation.
- Units are converted: inch exports, and Hawkin's metres, seconds and newtons.
- Files holding several tests keep only bilateral CMJ rows, so SL CMJ, rebound jumps, IMTP and other tests are skipped.
- Overlapping exports are de-duplicated.
- Comma or semicolon delimiters and UTF-8 BOMs are detected automatically.
- De-identified exports with no Name column load using the ExternalId instead.
- Year-first dates (2026/09/08) are read correctly whatever `ExportCulture` is set to.

To check an export before opening Power BI:

```
python tools/check_export.py "C:\path\to\your\exports"
```

---

## How the scoring works

For each athlete and metric:

```
z = (test − athlete's own mean) / athlete's own SD
```

- **SWC** (smallest worthwhile change) is 0.5 × the athlete's own SD.
- Each metric is scored in the direction that matters: higher is better for jump height, power, impulse and RFD; lower is better for contraction time; a big change in countermovement depth in either direction counts as worse.
- Athletes need at least 3 tests before they are scored on page 1.
- On page 1 the normal is every test up to the as-of date; on page 2 it is every test for that athlete.

## Repo contents

```
CMJMonitoringReport.pbip            open this in Power BI Desktop
CMJMonitoringReport.Report/         report pages and visuals (Power BI project format)
CMJMonitoringReport.SemanticModel/  tables, relationships and DAX measures (TMDL)
queries/                            readable copies of the Power Query (M) code
sample_data/                        the simulated season as a ForceDecks CSV (built into the report)
                                    and the same season as a Hawkin Dynamics CSV
tools/make_demo_data.py             how the simulated data is generated
tools/build_model.py                copies queries/*.m and the demo CSV into the model after edits
tools/check_export.py               checks a VALD or Hawkin export against the import rules
```

## How the demo data is built

`tools/make_demo_data.py` simulates a season of weekly CMJ testing for 20 athletes from scratch, not from any real dataset:

- Each athlete gets traits for bodyweight, jump ability, countermovement strategy and side bias.
- Metrics are physically linked: takeoff velocity from jump height (impulse–momentum), concentric force from bodyweight, velocity and depth (work–energy), stiffness from force over depth.
- The season has a pre-season build and a mild mid-summer dip.
- Four return-to-play athletes start mid-season about 20% down, with asymmetries that close over time.
- Test-to-test noise is in line with typical CMJ reliability: about 2–3% for output metrics and 6–15% for timing and RFD metrics.
- `athlete_01` follows the simulated case described above.

## Credits and further reading

- Metric selection follows Dr. Matt Jordan's six CMJ monitoring metrics. See also Bishop C, Turner A, Jordan M, et al. *A framework to guide practitioners for selecting metrics during the countermovement and drop jump tests.* Journal of Strength and Conditioning Research (2021).
- Smallest worthwhile change and interpreting individual change: Hopkins WG. *How to interpret changes in an athletic performance test.* Sportscience 8 (2004).
- The page 1 column layout is inspired by the CMJ team report in Sport Horizon's tutorial [Power BI for Strength & Conditioning (S&C) Coaches: Tutorial & Course Discount!](https://www.youtube.com/watch?v=ZMnDJSYdFX4). For more of their Power BI education for coaches and sport scientists, see [sporthorizon.co.uk](https://www.sporthorizon.co.uk/).
- This report grew out of my earlier [CMJ Trend Report](https://github.com/NateKolbSportScience/CMJ-Trend-Report).

## Privacy

Keep real exports outside the repo, or in `data/`, `exports/` or `private/`, which `.gitignore` excludes along with Power BI's local data cache. Leave `AnonymizeNames = true` for screenshots and anything you share.

---

Built by **Nate Kolb**, MSc, RSCC, CPSS · strength and conditioning coach and sport scientist
