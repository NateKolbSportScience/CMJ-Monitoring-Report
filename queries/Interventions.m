// Interventions log: one row per change you made for an athlete. It draws a marker on that
// athlete's trend charts (page 2) and lists the note in the Interventions card.
// Edit it in Power Query (Transform data > Interventions > the gear on "Source"), or replace it
// with a table from Excel. Type the athlete exactly as the report shows the name
// (athlete_01 ... while AnonymizeNames is true).
let
    Source = #table(
        type table [Athlete = text, Date = date, Note = text],
        {
            {"athlete_01", #date(2026, 7, 20), "Example: training modified"}
        })
in
    Source
