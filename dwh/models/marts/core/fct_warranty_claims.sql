select
    c.claim_id,
    c.unit_id,
    u.model_id,
    u.workshop_id,
    c.dealer_id,
    c.defect_type_id,
    coalesce(dt.origin_area, 'UNKNOWN')               as origin_area,
    c.claim_date,
    date_trunc('month', c.claim_date)::date           as claim_month,
    c.status,
    c.is_pending,
    c.requested_amount_rub,
    c.approved_amount_rub,
    c.decision_date,
    u.shipped_date,
    date_trunc('month', u.shipped_date)::date         as ship_month,
    c.claim_date - u.shipped_date                     as days_in_service,
    u.paint_brigade_id,
    u.dyn_lab_id,
    u.dyn_on_retired_stand,
    c.is_vin_unmatched
from {{ ref('int_warranty_claims_current') }} c
left join {{ ref('fct_units') }} u          using (unit_id)
left join {{ ref('stg_plant__defect_types') }} dt using (defect_type_id)
