-- Стоимость низкого качества (COPQ) по месяцам и цехам:
--   внутренние потери - доработки на линии и после испытаний (нормо-часы × ставка),
--   внешние потери    - одобренные гарантийные выплаты (по месяцу обращения).
with months as (
    select distinct month_start from {{ ref('mart_daily_workshop_kpi') }}
),
grid as (
    select m.month_start, w.workshop_id, w.workshop_code, w.workshop_name
    from months m cross join {{ ref('dim_workshop') }} w
),
internal as (
    select
        workshop_id, month_start,
        sum(rework_cost_rub) filter (where detection_point = 'line') as line_rework_cost_rub,
        sum(rework_cost_rub) filter (where detection_point = 'test') as test_rework_cost_rub
    from {{ ref('fct_defects') }} group by 1, 2
),
external as (
    select workshop_id, claim_month as month_start,
           count(*) filter (where status <> 'rejected') as warranty_claims,
           sum(approved_amount_rub)                    as warranty_cost_rub
    from {{ ref('fct_warranty_claims') }} where workshop_id is not null group by 1, 2
),
output as (
    select workshop_id, month_start, sum(units_accepted) as units_accepted, sum(revenue_rub) as revenue_rub
    from {{ ref('mart_daily_workshop_kpi') }} group by 1, 2
)
select
    g.month_start,
    g.workshop_id,
    g.workshop_code,
    g.workshop_name,
    coalesce(o.units_accepted, 0)                                    as units_accepted,
    coalesce(o.revenue_rub, 0)                                       as revenue_rub,
    coalesce(i.line_rework_cost_rub, 0)                              as line_rework_cost_rub,
    coalesce(i.test_rework_cost_rub, 0)                              as test_rework_cost_rub,
    coalesce(e.warranty_claims, 0)                                   as warranty_claims,
    coalesce(e.warranty_cost_rub, 0)                                 as warranty_cost_rub,
    coalesce(i.line_rework_cost_rub, 0) + coalesce(i.test_rework_cost_rub, 0)
        + coalesce(e.warranty_cost_rub, 0)                           as copq_total_rub,
    round({{ safe_div('coalesce(i.line_rework_cost_rub, 0) + coalesce(i.test_rework_cost_rub, 0) + coalesce(e.warranty_cost_rub, 0)', 'o.units_accepted') }}, 0) as copq_per_unit_rub
from grid g
left join internal i using (workshop_id, month_start)
left join external e using (workshop_id, month_start)
left join output o   using (workshop_id, month_start)
