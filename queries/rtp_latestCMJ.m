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
    // DataFolder set        -> every CSV in that folder and its subfolders.
    UseDemo = DataFolder = null or Text.Trim(Text.From(DataFolder)) = "",
    DemoCsv = Binary.Decompress(Binary.FromText("DEMO_DATA_BASE64", BinaryEncoding.Base64), Compression.Deflate),
    Empty = #table({"Content", "Name", "Extension"}, {}),
    Probe = if UseDemo then [HasError = true] else try Table.RowCount(Folder.Files(DataFolder)),
    AllFiles =
        if UseDemo then #table({"Content", "Name", "Extension"}, {{DemoCsv, "forcedecks_cmj_demo.csv", ".csv"}})
        else if Probe[HasError] then Empty
        else Folder.Files(DataFolder),
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
            Table.RenameColumns(promoted, List.Zip({old, unique})),
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
        {"Test Type", {"Test Type", "Test"}, "text"},
        {"Date", {"Date", "Test Date"}, "date"},
        {"Time", {"Time", "Test Time"}, "time"},
        {"BW [KG]", {"BW [KG]", "Bodyweight [kg]", "Body Weight [kg]"}, "number"},
        {"Reps", {"Reps", "Repetitions"}, "int"},
        {"Tags", {"Tags"}, "text"},
        {"Additional Load [lb]", {"Additional Load [lb]", "Additional Load [lbs]"}, "int"},
        {"Jump Height (Imp-Mom) (cm)", {"Jump Height (Imp-Mom) [cm]", "Jump Height(cm)"}, "number"},
        {"__JumpHeightIn", {"Jump Height (Imp-Mom) in Inches [in]", "Jump Height (Imp-Mom) [in]", "Jump Height(in)"}, "number"},
        {"__JumpHeightM", {"Jump Height(m)"}, "number"},
        {"Contraction Time (ms)", {"Contraction Time [ms]", "Time To Takeoff(ms)"}, "int"},
        {"__TimeToTakeoffS", {"Time To Takeoff(s)"}, "number"},
        {"Peak Power / BM (W/kg)", {"Peak Power / BM [W/kg]", "Peak Power/BM [W/kg]", "Peak Relative Propulsive Power(W/kg)"}, "number"},
        {"Bodyweight in Pounds [lbs] ", {"Bodyweight in Pounds [lbs]"}, "number"},
        {"CMJ Stiffness [N/m] ", {"CMJ Stiffness [N/m]", "Stiffness(N/m)"}, "int"},
        {"Vertical Velocity at Takeoff (m/s)", {"Vertical Velocity at Takeoff [m/s]", "Takeoff Velocity(m/s)"}, "number"},
        {"Eccentric Braking RFD (N/s)", {"Eccentric Braking RFD [N/s]", "Braking RFD(N/s)"}, "int"},
        {"Positive Impulse [N s] ", {"Positive Impulse [N s]", "Positive Impulse(N.s)", "Positive Impulse(Ns)"}, "number"},
        {"Concentric Mean Force [N] ", {"Concentric Mean Force [N]", "Avg. Propulsive Force(N)"}, "int"},
        {"Concentric Impulse % (Asym) (%)", {"Concentric Impulse % (Asym) (%)", "Concentric Impulse % (Asym)"}, "text"},
        {"Velocity at Peak Power [m/s] ", {"Velocity at Peak Power [m/s]"}, "number"},
        {"Force at Zero Velocity (N)", {"Force at Zero Velocity [N]", "Force at Min Displacement(N)"}, "int"},
        {"Countermovement Depth [cm] ", {"Countermovement Depth [cm]", "Countermovement Depth(cm)"}, "number"},
        {"__DepthM", {"Countermovement Depth(m)"}, "number"},
        {"__DepthIn", {"Countermovement Depth(in)"}, "number"},
        {"Eccentric Braking Impulse % (Asym) (%)", {"Eccentric Braking Impulse % (Asym) (%)", "Eccentric Braking Impulse % (Asym)"}, "text"},
        // Hawkin: system weight in newtons and L|R impulse indices (positive = left higher)
        {"__SystemWeightN", {"System Weight(N)"}, "number"},
        {"__HawkinBrakingIndex", {"L|R Braking Impulse Index(%)"}, "number"},
        {"__HawkinPropulsiveIndex", {"L|R Propulsive Impulse Index(%)"}, "number"}
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
                bwKg = if r[#"BW [KG]"] <> null then r[#"BW [KG]"] else Scale(r[__SystemWeightN], 1 / 9.81)
            in
            Record.TransformFields(r, {
                {"BW [KG]", (x) => bwKg},
                {"Jump Height (Imp-Mom) (cm)", (x) => if x <> null then x else if r[__JumpHeightIn] <> null then r[__JumpHeightIn] * 2.54 else Scale(r[__JumpHeightM], 100)},
                {"Contraction Time (ms)", (x) => if x <> null then x else let ms = Scale(r[__TimeToTakeoffS], 1000) in if ms = null then null else Int64.From(ms)},
                {"Countermovement Depth [cm] ", (x) => if x <> null then x else if r[__DepthM] <> null then r[__DepthM] * 100 else Scale(r[__DepthIn], 2.54)},
                {"Bodyweight in Pounds [lbs] ", (x) => if x <> null then x else Scale(bwKg, 2.20462)}})),
        Table.ColumnNames(Shaped), MissingField.UseNull),
    NoHelper = Table.RemoveColumns(Filled, {"__JumpHeightIn", "__JumpHeightM", "__TimeToTakeoffS", "__DepthM", "__DepthIn", "__SystemWeightN"}),

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
    Display = Table.TransformColumns(WithId, {{"Name", each if AnonymizeNames then "athlete_" & Text.PadStart(Text.From(Record.Field(Index, _)), 2, "0") else _}}),

    Deduped = Table.Distinct(Table.RemoveColumns(Display, {"__HawkinBrakingIndex", "__HawkinPropulsiveIndex"})),
    Typed = Table.TransformColumnTypes(Deduped,
        List.Transform(List.Select(Spec, each not Text.StartsWith(_{0}, "__")), each {_{0}, Record.Field(Types, _{2})}) & {
            {"Eccentric Braking Impulse % (Asym) Direction", type number},
            {"Concentric Impulse % (Asym) Direction", Int64.Type},
            {"athleteid.Index.1", Int64.Type}})
in
    Typed
