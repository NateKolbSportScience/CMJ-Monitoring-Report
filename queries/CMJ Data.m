// Reads every ForceDecks or Hawkin Dynamics CMJ export in DataFolder (subfolders included) - or the
// built-in demo export when DataFolder is blank - and returns the exact
// columns the CMJ Monitoring Report expects. Column order, extra/missing columns, header spacing,
// [unit] vs (unit), inch or cm jump height and duplicate tests across files are all handled.
// Hawkin exports ("Jump Height(m)", "Time To Takeoff(s)", L|R index ...) are mapped onto the same
// columns with their units converted (m -> cm, s -> ms, N -> kg) and the L|R sign flipped to L - / R +.
let
    // ---------- helpers --------------------------------------------------------------------
    // header -> comparison key: lower case, [unit] -> (unit), no spaces or dots
    // so "Jump Height (m)", "Jump Height(m)" and "jump height [m]" all match
    Key = (h as any) as text =>
        let
            t = Text.Replace(Text.Replace(Text.Replace(if h = null then "" else Text.From(h), Character.FromNumber(65279), ""), "[", "("), "]", ")"),
            words = List.Select(Text.SplitAny(Text.Lower(Text.Trim(t)), " .#(tab)#(00A0)"), each _ <> "")
        in
            Text.Combine(words, ""),
    CleanName = (n as any) as nullable text =>
        let parts = if n = null then {} else List.Select(Text.SplitAny(Text.Trim(Text.From(n)), " #(tab)#(00A0)"), each _ <> "")
        in if List.IsEmpty(parts) then null else Text.Combine(parts, " "),
    ToNumber = (v as any) as nullable number =>
        if v = null then null
        else if v is number then v
        else
            let t = Text.Remove(Text.Trim(Text.From(v)), {"%", " ", "#(00A0)"})
            in if t = "" then null else try Number.FromText(t, "en-US") otherwise null,
    // "2026/09/08" or "2026-09-08" (year first) reads the same whatever ExportCulture is set to
    YearFirst = (t as text) as nullable date =>
        let p = Text.SplitAny(Text.BeforeDelimiter(t & " ", " "), "/-.")
        in if List.Count(p) = 3 and Text.Length(p{0}) = 4
           then try #date(Number.FromText(p{0}), Number.FromText(p{1}), Number.FromText(p{2})) otherwise null
           else null,
    ToDate = (v as any) as nullable date =>
        if v = null then null
        else if v is date then v
        else if v is datetime then DateTime.Date(v)
        else
            let t = Text.Trim(Text.From(v))
            in if t = "" then null
               else if YearFirst(t) <> null then YearFirst(t)
               else try Date.FromText(t, ExportCulture)
               otherwise try DateTime.Date(DateTime.FromText(t, ExportCulture))
               otherwise try Date.FromText(Text.BeforeDelimiter(t, " "), ExportCulture)
               otherwise null,
    ToTime = (v as any) as nullable time =>
        if v = null then null
        else if v is time then v
        else
            let t = Text.Trim(Text.From(v))
            in if t = "" then null
               else try Time.FromText(t, ExportCulture)
               otherwise try DateTime.Time(DateTime.FromText(t, ExportCulture))
               otherwise null,
    // "12.3 L" -> -12.3, "8.1 R" -> 8.1 (left negative, right positive)
    Asym = (v as any) as nullable number =>
        if v = null then null
        else if v is number then v
        else
            let
                tokens = List.Select(Text.SplitAny(Text.Upper(Text.Remove(Text.Trim(Text.From(v)), {"%"})), " ()#(00A0)"), each _ <> ""),
                nums = List.RemoveNulls(List.Transform(tokens, each try Number.FromText(_, "en-US") otherwise null)),
                n = List.First(nums, null),
                isLeft = List.Contains(tokens, "L") or List.Contains(tokens, "LEFT")
            in
                if n = null then null else if isLeft then -Number.Abs(n) else Number.Abs(n),
    Converters = [
        text = (v) => if v = null then null else let t = Text.Trim(Text.From(v)) in if t = "" then null else t,
        number = ToNumber,
        int = (v) => let n = ToNumber(v) in if n = null then null else Int64.From(n),
        date = ToDate,
        time = ToTime
    ],
    Types = [text = type text, number = type number, int = Int64.Type, date = type date, time = type time],

    // ---------- choose the data ------------------------------------------------------------
    // DataFolder left blank -> the simulated demo export built into this file (works on any computer).
    // DataFolder = a folder -> every CSV in that folder and its subfolders.
    // DataFolder = a file   -> just that CSV export.
    // Quotes from Windows' "Copy as path" are stripped. A path with no CSVs stops the refresh with a message
    // saying so, instead of loading an empty report.
    Path = if DataFolder = null then "" else Text.Trim(Text.Trim(Text.From(DataFolder)), """"),
    UseDemo = Path = "",
    IsFile = Text.EndsWith(Text.Lower(Path), ".csv"),
    DemoCsv = Binary.Decompress(Binary.FromText("DEMO_DATA_BASE64", BinaryEncoding.Base64), Compression.Deflate),
    Found =
        if UseDemo then #table({"Content", "Name", "Extension"}, {{DemoCsv, "forcedecks_cmj_demo.csv", ".csv"}})
        else if IsFile then
            let f = try File.Contents(Path) in
            if f[HasError] then #table({"Content", "Name", "Extension"}, {})
            else #table({"Content", "Name", "Extension"}, {{f[Value], List.Last(Text.Split(Path, "\")), ".csv"}})
        else
            let files = try Folder.Files(Path) in
            if files[HasError] then #table({"Content", "Name", "Extension"}, {}) else files[Value],
    AllFiles =
        if Table.IsEmpty(Table.SelectRows(Found, each Text.Lower([Extension]) = ".csv"))
        then error Error.Record("No CMJ exports found",
            "Nothing to load at " & Path & ". Paste the path of a VALD or Hawkin CSV export, or of the folder that holds them (Transform data > Edit parameters > DataFolder). Clear it to see the demo.")
        else Found,
    CsvFiles = Table.SelectRows(AllFiles, each Text.Lower([Extension]) = ".csv" and not Text.StartsWith([Name], "~$")),
    ReadCsv = (content as binary) as table =>
        let
            first = try Lines.FromBinary(content, null, null, 65001){0} otherwise "",
            delimiter = if List.Count(Text.Split(first, ";")) > List.Count(Text.Split(first, ",")) then ";" else ",",
            promoted = Table.PromoteHeaders(Csv.Document(content, [Delimiter = delimiter, Encoding = 65001, QuoteStyle = QuoteStyle.Csv]), [PromoteAllScalars = true]),
            old = Table.ColumnNames(promoted),
            keys = List.Transform(old, Key),
            unique = List.Accumulate(List.Positions(keys), {}, (acc, i) => acc & {if List.Contains(acc, keys{i}) then keys{i} & " #" & Text.From(i) else keys{i}})
        in
            Units(Table.RenameColumns(promoted, List.Zip({old, unique}))),
    // Hawkin exports can drop the units from the headers ("Jump Height", "System Weight") and use metric or
    // imperial depending on account settings. Work the unit out from each file's typical value and rename the
    // column to its unit form ("jumpheight(in)"), which the Spec below already converts.
    Units = (tbl as table) as table =>
        let
            cols = Table.ColumnNames(tbl),
            med = (c as text) as nullable number =>
                let vals = List.RemoveNulls(List.Transform(Table.Column(tbl, c), ToNumber))
                in if List.IsEmpty(vals) then null else Number.Abs(List.Median(vals)),
            pick = (c as text, rule as function) as list =>
                if not List.Contains(cols, c) then {} else
                let m = med(c), u = if m = null then null else rule(m)
                in if u = null or List.Contains(cols, c & "(" & u & ")") then {} else {{c, c & "(" & u & ")"}},
            renames =
                pick("jumpheight", (m) => if m < 1.5 then "m" else if m < 28 then "in" else "cm")
                & pick("countermovementdepth", (m) => if m < 1.5 then "m" else if m < 20 then "in" else "cm")
                & pick("timetotakeoff", (m) => if m < 5 then "s" else "ms")
                & pick("unweightingphase", (m) => if m < 5 then "s" else null)
                & pick("brakingphase", (m) => if m < 5 then "s" else null)
                & pick("systemweight", (m) => if m > 400 then "n" else if m > 140 then "lb" else "kg")
        in
            Table.RenameColumns(tbl, renames),
    Tables = List.RemoveNulls(List.Transform(CsvFiles[Content], each try Table.Buffer(ReadCsv(_)) otherwise null)),
    Combined = if List.IsEmpty(Tables) then #table({}, {}) else Table.Combine(Tables),

    // Keep CMJ rows only when a file holds several ForceDecks tests (single-leg CMJ excluded)
    TypeCol = List.First(List.Select({"testtype", "type"}, each Table.HasColumns(Combined, _)), null),
    CmjOnly = if TypeCol = null then Combined
        else Table.SelectRows(Combined, each
            let v = Record.Field(_, TypeCol), t = if v = null then "" else Text.Lower(Text.From(v))
            in (Text.Contains(t, "cmj") or Text.Contains(t, "countermovement"))
               and not Text.Contains(t, "sl") and not Text.Contains(t, "single") and not Text.Contains(t, "rebound")),

    // ---------- map whatever is there onto the report's columns ---------------------------
    // {output column, accepted export headers, type}
    // Columns starting "__" are Hawkin (or inch) helpers converted into the report columns below
    Spec = {
        {"Name", {"Name", "Athlete", "Athlete Name"}, "text"},
        {"ExternalId", {"ExternalId", "External Id"}, "text"},
        {"Test Type", {"Test Type", "Test", "Type"}, "text"},
        {"Date", {"Date", "Test Date"}, "date"},
        {"Time", {"Time", "Test Time"}, "time"},
        {"BW [KG]", {"BW [KG]", "Bodyweight [kg]", "Body Weight [kg]", "System Weight(kg)"}, "number"},
        {"Reps", {"Reps", "Repetitions"}, "int"},
        {"Tags", {"Tags"}, "text"},
        {"Additional Load [lb]", {"Additional Load [lb]", "Additional Load [lbs]"}, "int"},
        {"Jump Height (Imp-Mom) (cm)", {"Jump Height (Imp-Mom) [cm]", "Jump Height(cm)"}, "number"},
        {"__JumpHeightIn", {"Jump Height (Imp-Mom) in Inches [in]", "Jump Height (Imp-Mom) [in]", "Jump Height(in)"}, "number"},
        {"__JumpHeightM", {"Jump Height(m)"}, "number"},
        {"Contraction Time (ms)", {"Contraction Time [ms]", "Time To Takeoff(ms)"}, "int"},
        {"__TimeToTakeoffS", {"Time To Takeoff(s)"}, "number"},
        {"Peak Power / BM (W/kg)", {"Peak Power / BM [W/kg]", "Peak Power/BM [W/kg]", "Peak Relative Propulsive Power(W/kg)", "Peak Relative Propulsive Power"}, "number"},
        {"Bodyweight in Pounds [lbs] ", {"Bodyweight in Pounds [lbs]"}, "number"},
        {"CMJ Stiffness [N/m] ", {"CMJ Stiffness [N/m]", "Stiffness(N/m)", "Stiffness"}, "int"},
        {"Vertical Velocity at Takeoff (m/s)", {"Vertical Velocity at Takeoff [m/s]", "Takeoff Velocity(m/s)", "Takeoff Velocity"}, "number"},
        {"Eccentric Braking RFD (N/s)", {"Eccentric Braking RFD [N/s]", "Braking RFD(N/s)", "Braking RFD"}, "int"},
        {"Eccentric Duration (ms)", {"Eccentric Duration [ms]", "Eccentric Duration(ms)"}, "int"},
        {"__UnweightingS", {"Unweighting Phase(s)"}, "number"},
        {"__BrakingPhaseS", {"Braking Phase(s)"}, "number"},
        {"Positive Impulse [N s] ", {"Positive Impulse [N s]", "Positive Impulse(N.s)", "Positive Impulse(Ns)", "Positive Impulse"}, "number"},
        {"Concentric Mean Force [N] ", {"Concentric Mean Force [N]", "Avg. Propulsive Force(N)", "Avg. Propulsive Force"}, "int"},
        {"Concentric Impulse % (Asym) (%)", {"Concentric Impulse % (Asym) (%)", "Concentric Impulse % (Asym)"}, "text"},
        {"Velocity at Peak Power [m/s] ", {"Velocity at Peak Power [m/s]"}, "number"},
        {"Force at Zero Velocity (N)", {"Force at Zero Velocity [N]", "Force at Min Displacement(N)", "Force at Min Displacement"}, "int"},
        {"Countermovement Depth [cm] ", {"Countermovement Depth [cm]", "Countermovement Depth(cm)"}, "number"},
        {"__DepthM", {"Countermovement Depth(m)"}, "number"},
        {"__DepthIn", {"Countermovement Depth(in)"}, "number"},
        {"Eccentric Braking Impulse % (Asym) (%)", {"Eccentric Braking Impulse % (Asym) (%)", "Eccentric Braking Impulse % (Asym)"}, "text"},
        // Hawkin: system weight in newtons and L|R impulse indices (positive = left higher)
        {"__SystemWeightN", {"System Weight(N)"}, "number"},
        {"__SystemWeightLb", {"System Weight(lb)", "System Weight(lbs)"}, "number"},
        {"__HawkinBrakingIndex", {"L|R Braking Impulse Index(%)", "L|R Braking Impulse Index"}, "number"},
        {"__HawkinPropulsiveIndex", {"L|R Propulsive Impulse Index(%)", "L|R Propulsive Impulse Index"}, "number"}
    },
    Cols = Table.ColumnNames(CmjOnly),
    Resolve = (aliases as list) as nullable text => List.First(List.Select(List.Transform(aliases, Key), each List.Contains(Cols, _)), null),
    Shaped = Table.FromRecords(
        Table.TransformRows(CmjOnly, (r) =>
            Record.FromList(
                List.Transform(Spec, (s) => let k = Resolve(s{1}) in if k = null then null else Record.Field(Converters, s{2})(Record.Field(r, k))),
                List.Transform(Spec, each _{0}))),
        List.Transform(Spec, each _{0}), MissingField.UseNull),

    // Unit conversions: the report is metric with lengths in cm and times in ms.
    // Inch exports and Hawkin exports (m, s, N) are converted here.
    Scale = (x as nullable number, f as number) as nullable number => if x = null then null else x * f,
    Filled = Table.FromRecords(
        Table.TransformRows(Shaped, (r) =>
            let
                bwKg = if r[#"BW [KG]"] <> null then r[#"BW [KG]"] else if r[__SystemWeightN] <> null then r[__SystemWeightN] / 9.81 else Scale(r[__SystemWeightLb], 1 / 2.20462)
            in
            Record.TransformFields(r, {
                {"BW [KG]", (x) => bwKg},
                {"Jump Height (Imp-Mom) (cm)", (x) => if x <> null then x else if r[__JumpHeightIn] <> null then r[__JumpHeightIn] * 2.54 else Scale(r[__JumpHeightM], 100)},
                {"Contraction Time (ms)", (x) => if x <> null then x else let ms = Scale(r[__TimeToTakeoffS], 1000) in if ms = null then null else Int64.From(ms)},
                // Hawkin has no "eccentric duration": VALD's eccentric phase runs from the start of movement to zero
                // velocity, which is Hawkin's unweighting phase + braking phase
                {"Eccentric Duration (ms)", (x) => if x <> null then x else if r[__UnweightingS] = null or r[__BrakingPhaseS] = null then null else Int64.From((r[__UnweightingS] + r[__BrakingPhaseS]) * 1000)},
                {"Countermovement Depth [cm] ", (x) => if x <> null then x else if r[__DepthM] <> null then r[__DepthM] * 100 else Scale(r[__DepthIn], 2.54)},
                {"Bodyweight in Pounds [lbs] ", (x) => if x <> null then x else Scale(bwKg, 2.20462)}})),
        Table.ColumnNames(Shaped), MissingField.UseNull),
    NoHelper = Table.RemoveColumns(Filled, {"__JumpHeightIn", "__JumpHeightM", "__TimeToTakeoffS", "__DepthM", "__DepthIn", "__SystemWeightN", "__SystemWeightLb", "__UnweightingS", "__BrakingPhaseS"}),

    // Asymmetry direction, left negative / right positive. ForceDecks text ("6.4 L") or Hawkin index (sign flipped)
    EccDirection = Table.AddColumn(NoHelper, "Eccentric Braking Impulse % (Asym) Direction", each
        let v = Asym([#"Eccentric Braking Impulse % (Asym) (%)"])
        in if v <> null then v else Scale([__HawkinBrakingIndex], -1)),
    ConcDirection = Table.AddColumn(EccDirection, "Concentric Impulse % (Asym) Direction", each
        let v = Asym([#"Concentric Impulse % (Asym) (%)"]), n = if v <> null then v else Scale([__HawkinPropulsiveIndex], -1)
        in if n = null then null else Int64.From(n)),

    // ---------- athletes: tidy names, number them, optionally anonymise --------------------
    // No Name column, or a blank name? Fall back to the ExternalId so de-identified exports still load
    Tidy = Table.FromRecords(
        Table.TransformRows(ConcDirection, (r) =>
            Record.TransformFields(r, {"Name", (n) =>
                let c = CleanName(n), id = CleanName(r[ExternalId])
                in if c <> null then c else if id <> null then "ID " & id else null})),
        Table.ColumnNames(ConcDirection), MissingField.UseNull),
    Valid = Table.SelectRows(Tidy, each [Name] <> null and [Date] <> null),
    Names = List.Sort(List.Distinct(Valid[Name])),
    Index = Record.FromList(List.Numbers(1, List.Count(Names)), Names),
    WithId = Table.AddColumn(Valid, "athleteid.Index.1", each Record.Field(Index, [Name])),
    // pad IDs to the same width (athlete_001 with 100+ athletes) so they sort in number order
    IdWidth = List.Max({2, Text.Length(Text.From(List.Count(Names)))}),
    Display = Table.TransformColumns(WithId, {{"Name", each if AnonymizeNames then "athlete_" & Text.PadStart(Text.From(Record.Field(Index, _)), IdWidth, "0") else _}}),

    Deduped = Table.Distinct(Table.RemoveColumns(Display, {"__HawkinBrakingIndex", "__HawkinPropulsiveIndex"})),

    // ---------- one row per test --------------------------------------------------------------
    // Hawkin exports every rep as its own row (VALD usually exports one row per test). For each session
    // (athlete + date), drop reps whose jump height is more than RepDropPercent below that session's best
    // (warm-ups, botched jumps), then average every metric across the reps that are left.
    RepDropPercent = 10,
    JH = "Jump Height (Imp-Mom) (cm)",
    KeepReps = (t as table) as table =>
        let best = List.Max(List.RemoveNulls(Table.Column(t, JH)), null)
        in if best = null then t
           else Table.SelectRows(t, (r) => Record.Field(r, JH) = null or Record.Field(r, JH) >= best * (1 - RepDropPercent / 100)),
    KeyCols = {"Name", "athleteid.Index.1", "Date"},
    TextCols = List.Transform(List.Select(Spec, each List.Contains({"text", "time", "date"}, _{2})), each _{0}),
    ValueCols = List.Difference(Table.ColumnNames(Deduped), KeyCols),
    Grouped = Table.Group(Deduped, KeyCols, {{"__Reps", each KeepReps(_), type table}}),
    Sessions = Table.FromRecords(
        Table.TransformRows(Grouped, (g) =>
            Record.SelectFields(g, KeyCols) & Record.FromList(
                List.Transform(ValueCols, (c) =>
                    let vals = List.RemoveNulls(Table.Column(g[__Reps], c))
                    in if List.Contains(TextCols, c) then List.First(vals, null)
                       else if List.IsEmpty(vals) then null else List.Average(vals)),
                ValueCols)),
        KeyCols & ValueCols, MissingField.UseNull),
    Typed = Table.TransformColumnTypes(Sessions,
        List.Transform(List.Select(Spec, each not Text.StartsWith(_{0}, "__")), each {_{0}, Record.Field(Types, _{2})}) & {
            {"Eccentric Braking Impulse % (Asym) Direction", type number},
            {"Concentric Impulse % (Asym) Direction", Int64.Type},
            {"athleteid.Index.1", Int64.Type}})
in
    Typed
