-- Актуальная версия плана на месяц (последняя утверждённая) + первоначальная версия
with ranked as (
    select
        p.*,
        row_number() over (partition by plan_month, model_code order by plan_version desc, approved_date desc) as rn_last,
        row_number() over (partition by plan_month, model_code order by plan_version, approved_date)           as rn_first
    from {{ ref('stg_erp__production_plan') }} p
)
select
    l.plan_month,
    m.model_id,
    l.model_code,
    l.planned_qty                     as planned_qty,
    f.planned_qty                     as planned_qty_initial,
    l.plan_version                    as plan_versions,
    l.approved_date                   as last_approved_date
from ranked l
join ranked f
  on f.plan_month = l.plan_month and f.model_code = l.model_code and f.rn_first = 1
left join {{ ref('stg_plant__product_models') }} m on m.model_code = l.model_code
where l.rn_last = 1
