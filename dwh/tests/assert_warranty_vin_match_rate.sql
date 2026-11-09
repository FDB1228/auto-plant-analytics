{{ config(severity='warn') }}
-- Контроль качества внешнего источника: доля заявок с VIN, не найденным в MES, не выше 1%
select count(*) filter (where is_vin_unmatched) as unmatched, count(*) as total
from {{ ref('fct_warranty_claims') }}
having count(*) filter (where is_vin_unmatched) > 0.01 * count(*)
