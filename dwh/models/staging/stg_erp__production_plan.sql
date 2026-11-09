-- Типизация плана из ERP. Все версии плана сохраняются; актуальная выбирается в intermediate.
select
    to_date(period_raw, 'DD.MM.YYYY')               as plan_month,
    upper(trim(model_code))                         as model_code,
    trim(workshop_code)                             as workshop_code,
    planned_qty_raw::integer                        as planned_qty,
    plan_version_raw::smallint                      as plan_version,
    to_date(approved_date_raw, 'DD.MM.YYYY')        as approved_date,
    _source_file                                    as source_file,
    _loaded_at                                      as loaded_at
from {{ source('raw', 'erp_production_plan') }}
