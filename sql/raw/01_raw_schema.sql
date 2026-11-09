-- =====================================================================
--  RAW-слой хранилища: данные внешних систем «как есть» (все поля - text)
--  + технические поля загрузки. Очистка и типизация - в dbt (staging).
-- =====================================================================
CREATE SCHEMA IF NOT EXISTS raw;

-- Журнал загруженных файлов: обеспечивает идемпотентность (файл не грузится дважды)
CREATE TABLE IF NOT EXISTS raw.load_log (
    file_name     text        PRIMARY KEY,
    source        text        NOT NULL,
    file_sha256   char(64)    NOT NULL,
    rows_loaded   integer     NOT NULL,
    loaded_at     timestamptz NOT NULL DEFAULT now()
);

-- План производства из ERP (CSV, cp1251, «;»), каждая версия плана - отдельный файл
CREATE TABLE IF NOT EXISTS raw.erp_production_plan (
    period_raw        text,
    model_code        text,
    model_name        text,
    workshop_code     text,
    planned_qty_raw   text,
    plan_version_raw  text,
    approved_date_raw text,
    _source_file      text        NOT NULL,
    _row_number       integer     NOT NULL,
    _loaded_at        timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (_source_file, _row_number)
);

-- Гарантийные обращения с дилерского портала (еженедельный JSON).
-- Одна заявка приходит несколько раз: при подаче и при решении; бывают дубли.
CREATE TABLE IF NOT EXISTS raw.dealer_warranty_claims (
    export_id           text,
    claim_id            text,
    vin                 text,
    dealer_code         text,
    defect_code         text,
    claim_date_raw      text,
    status              text,
    amount_raw          text,
    record_updated_at   text,
    payload             jsonb       NOT NULL,
    _source_file        text        NOT NULL,
    _row_number         integer     NOT NULL,
    _loaded_at          timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (_source_file, _row_number)
);
