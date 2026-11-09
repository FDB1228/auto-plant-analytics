-- План-факт по месяцам и моделям. Факт = изделия, принятые ОТК после испытаний (выпуск).
with fact as (
    select model_id, accepted_month as month_start, count(*) as accepted_qty
    from {{ ref('fct_units') }}
    where accepted_month is not null
    group by 1, 2
),
started as (
    select model_id, date_trunc('month', start_date)::date as month_start, count(*) as started_qty
    from {{ ref('stg_plant__units') }}
    group by 1, 2
)
select
    p.plan_month                                         as month_start,
    p.model_id,
    m.workshop_id,
    m.category_id,
    p.planned_qty,
    p.planned_qty_initial,
    p.plan_versions,
    coalesce(s.started_qty, 0)                           as started_qty,
    coalesce(f.accepted_qty, 0)                          as accepted_qty,
    round({{ safe_div('coalesce(f.accepted_qty, 0)', 'p.planned_qty') }}, 3) as plan_adherence,
    coalesce(f.accepted_qty, 0) * m.list_price_rub       as accepted_value_rub
from {{ ref('int_production_plan_latest') }} p
join {{ ref('stg_plant__product_models') }} m using (model_id)
left join fact f    on f.model_id = p.model_id and f.month_start = p.plan_month
left join started s on s.model_id = p.model_id and s.month_start = p.plan_month
where p.plan_month <= (select max(start_date) from {{ ref('stg_plant__units') }})
