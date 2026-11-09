-- Итоговое состояние каждой гарантийной заявки: последнее событие по record_updated_at,
-- дата подачи - из первой записи. VIN сопоставляется с экземпляром изделия.
with ordered as (
    select
        c.*,
        row_number() over (partition by claim_id order by record_updated_at desc, loaded_at desc) as rn_last,
        min(record_updated_at) over (partition by claim_id)                                     as submitted_at,
        max(amount_rub) filter (where status = 'submitted') over (partition by claim_id)        as requested_amount_rub
    from {{ ref('stg_dealer__warranty_claims') }} c
)
select
    o.claim_id,
    o.vin,
    u.unit_id,
    o.dealer_code,
    d.dealer_id,
    o.defect_code,
    dt.defect_type_id,
    o.claim_date,
    o.submitted_at,
    o.status,
    o.status = 'submitted'                                   as is_pending,
    o.requested_amount_rub,
    case when o.status = 'approved' then o.amount_rub else 0 end as approved_amount_rub,
    case when o.status <> 'submitted' then o.record_updated_at::date end as decision_date,
    u.unit_id is null                                        as is_vin_unmatched
from ordered o
left join {{ ref('stg_plant__units') }} u        on u.serial_no = o.vin
left join {{ ref('stg_plant__dealers') }} d      on d.dealer_code = o.dealer_code
left join {{ ref('stg_plant__defect_types') }} dt on dt.defect_code = o.defect_code
where o.rn_last = 1
