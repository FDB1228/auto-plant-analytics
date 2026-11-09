-- Ежедневные KPI цеха для операционного дашборда (зерно: цех × календарный день)
with bounds as (
    select min(start_date) as d0, max(start_date) as d1 from {{ ref('stg_plant__units') }}
),
grid as (
    select d.date_day, d.month_start, d.is_working_day, d.is_month_end_rush, w.workshop_id
    from {{ ref('dim_date') }} d
    cross join {{ ref('dim_workshop') }} w
    cross join bounds b
    where d.date_day between b.d0 and b.d1
),
started as (
    select workshop_id, start_date as date_day, count(*) as units_started
    from {{ ref('fct_units') }} group by 1, 2
),
assembled as (
    select workshop_id, assembled_date as date_day, count(*) as units_assembled
    from {{ ref('fct_units') }} where assembled_date is not null group by 1, 2
),
accepted as (
    select
        workshop_id, accepted_date as date_day,
        count(*)                                   as units_accepted,
        count(*) filter (where is_first_pass)      as units_first_pass,
        sum(total_lead_time_h)                     as total_lead_time_h_sum
    from {{ ref('fct_units') }} where accepted_date is not null group by 1, 2
),
shipped as (
    select workshop_id, shipped_date as date_day, count(*) as units_shipped, sum(price_rub) as revenue_rub
    from {{ ref('fct_units') }} where shipped_date is not null group by 1, 2
),
ops as (
    select
        workshop_id, work_date as date_day,
        count(*) filter (where not is_rework)              as operations,
        count(*) filter (where is_rework)                  as rework_operations,
        count(*) filter (where is_line_defect)             as line_defects,
        sum(duration_min) filter (where not is_rework) / 60 as labor_hours
    from {{ ref('fct_operations') }} group by 1, 2
),
dfx as (
    select
        workshop_id, detected_date as date_day,
        count(*) filter (where detection_point = 'test')  as test_defects,
        sum(rework_minutes) / 60                           as rework_hours,
        sum(rework_cost_rub)                               as rework_cost_rub
    from {{ ref('fct_defects') }} group by 1, 2
),
dt as (
    select workshop_id, work_date as date_day, sum(duration_h) as downtime_hours,
           sum(duration_h) filter (where not is_planned) as unplanned_downtime_hours
    from {{ ref('fct_downtime') }} group by 1, 2
)
select
    g.date_day,
    g.month_start,
    g.workshop_id,
    w.workshop_code,
    w.workshop_name,
    g.is_working_day,
    g.is_month_end_rush,
    coalesce(s.units_started, 0)            as units_started,
    coalesce(a.units_assembled, 0)          as units_assembled,
    coalesce(ac.units_accepted, 0)          as units_accepted,
    coalesce(ac.units_first_pass, 0)        as units_first_pass,
    ac.total_lead_time_h_sum,
    coalesce(sh.units_shipped, 0)           as units_shipped,
    coalesce(sh.revenue_rub, 0)             as revenue_rub,
    coalesce(o.operations, 0)               as operations,
    coalesce(o.rework_operations, 0)        as rework_operations,
    coalesce(o.line_defects, 0)             as line_defects,
    coalesce(df.test_defects, 0)            as test_defects,
    round(coalesce(o.labor_hours, 0), 1)    as labor_hours,
    round(coalesce(df.rework_hours, 0), 1)  as rework_hours,
    coalesce(df.rework_cost_rub, 0)         as rework_cost_rub,
    coalesce(dt.downtime_hours, 0)          as downtime_hours,
    coalesce(dt.unplanned_downtime_hours, 0) as unplanned_downtime_hours
from grid g
join {{ ref('dim_workshop') }} w using (workshop_id)
left join started s    using (workshop_id, date_day)
left join assembled a  using (workshop_id, date_day)
left join accepted ac  using (workshop_id, date_day)
left join shipped sh   using (workshop_id, date_day)
left join ops o        using (workshop_id, date_day)
left join dfx df       using (workshop_id, date_day)
left join dt           using (workshop_id, date_day)
