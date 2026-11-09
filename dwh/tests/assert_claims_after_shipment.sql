-- Гарантийное обращение не может предшествовать отгрузке
select claim_id, unit_id, claim_date, shipped_date
from {{ ref('fct_warranty_claims') }}
where shipped_date is not null and claim_date < shipped_date
