// One row per athlete for the bar-chart axes, taken from the CMJ table.
let
    Source = Table.SelectColumns(#"CMJ Data", {"Name", "athleteid.Index.1"}),
    Distinct = Table.Distinct(Source),
    Renamed = Table.RenameColumns(Distinct, {{"athleteid.Index.1", "Index.1"}}),
    Typed = Table.TransformColumnTypes(Renamed, {{"Name", type text}, {"Index.1", Int64.Type}})
in
    Typed
