-- Очистка выгрузки дилерского портала:
--   VIN: верхний регистр, без пробелов; даты: ISO или ДД.ММ.ГГГГ;
--   суммы: число или строка «45 300,00»; полные дубли записей удаляются.
with typed as (
    select
        claim_id,
        upper(regexp_replace(vin, '\s', '', 'g'))                         as vin,
        dealer_code,
        nullif(trim(defect_code), '')                                    as defect_code,
        case
            when claim_date_raw ~ '^\d{4}-\d{2}-\d{2}$' then claim_date_raw::date
            when claim_date_raw ~ '^\d{2}\.\d{2}\.\d{4}$' then to_date(claim_date_raw, 'DD.MM.YYYY')
        end                                                              as claim_date,
        lower(status)                                                    as status,
        nullif(replace(regexp_replace(amount_raw, '[\s ]', '', 'g'), ',', '.'), '')::numeric(14,2) as amount_rub,
        (record_updated_at::timestamp AT TIME ZONE 'Europe/Moscow')        as record_updated_at,  -- портал отдаёт местное время без пояса
        export_id,
        _source_file                                                     as source_file,
        _loaded_at                                                       as loaded_at
    from {{ source('raw', 'dealer_warranty_claims') }}
)
select distinct on (claim_id, status, record_updated_at) *
from typed
order by claim_id, status, record_updated_at, loaded_at
