// =====================================================================
//  Power Query (M): два способа загрузить витрины
//  Вариант A - напрямую из PostgreSQL (рекомендуется, если база запущена локально или в облаке)
//  Вариант B - из CSV-выгрузки bi/exports (без PostgreSQL)
//  Создайте параметры: Host (text, "localhost:5432"), Database (text, "plant"), CsvFolder (text, путь к bi\exports)
// =====================================================================

// ---------- Вариант A: PostgreSQL ----------
// Получить данные -> PostgreSQL -> Сервер = Host, База = Database -> схема marts.
// Для каждой таблицы запрос выглядит так (пример - fct_units):
let
    Source    = PostgreSQL.Database(Host, Database),
    fct_units = Source{[Schema = "marts", Item = "fct_units"]}[Data]
in
    fct_units

// ---------- Вариант B: CSV ----------
// 1) Пустой запрос fnLoadCsv (функция) - читает файл, поднимает заголовки и типизирует колонки
//    в культуре en-US (десятичная точка, даты ISO), чтобы русская локаль Windows не ломала числа.
(name as text) as table =>
let
    Raw      = Csv.Document(
                   File.Contents(CsvFolder & "\" & name & ".csv"),
                   [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]),
    Promoted = Table.PromoteHeaders(Raw, [PromoteAllScalars = true]),
    Cols     = Table.ColumnNames(Promoted),
    EndsAny  = (c as text, l as list) as logical => List.AnyTrue(List.Transform(l, (x) => Text.EndsWith(c, x))),
    TypeOf   = (c as text) as type =>
                   if List.Contains({"brigade_age_days_at_month_start", "working_days_in_month",
                        "working_day_of_month", "working_days_to_month_end"}, c) then Int64.Type
                   else if EndsAny(c, {"_date", "_start", "_month"}) or c = "date_day" then type date
                   else if Text.EndsWith(c, "_at") then type datetimezone
                   else if Text.StartsWith(c, "is_") or List.Contains({"started_in_rush", "leaked_after_dyn",
                        "dyn_on_retired_stand", "used_retired_equipment"}, c) then type logical
                   else if EndsAny(c, {"_id", "_cnt", "_qty", "_operations", "_claims", "_days", "_versions",
                        "_steps", "_in_month", "_of_month", "_to_month_end"})
                        or Text.StartsWith(c, "units") or List.Contains({"operations", "events", "at_risk",
                        "month_in_service", "year", "quarter", "month", "iso_dow", "cohort_units",
                        "days_to_detection", "days_in_service", "days_to_first_claim", "planned_qty_initial", "shifts_per_day",
                        "line_defects", "test_defects"}, c) then Int64.Type
                   else if EndsAny(c, {"_rub", "_h", "_rate", "_share", "_minutes", "_hours", "_ratio", "_to_std",
                        "_adherence", "_hp", "_kmh", "_kg", "_t", "_m", "_cc"})
                        or Text.StartsWith(c, "avg_") or List.Contains({"hazard", "seats", "performance",
                        "passenger_capacity", "total_lead_time_h_sum"}, c) then type number
                   else type text,
    Typed    = Table.TransformColumnTypes(Promoted, List.Transform(Cols, each {_, TypeOf(_)}), "en-US")
in
    Typed

// 2) Для каждой таблицы - запрос из одной строки, например:
//    fct_units = fnLoadCsv("fct_units")
//    dim_date  = fnLoadCsv("dim_date")
//    ... (полный список файлов - в bi/exports)
