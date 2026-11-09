-- Накопительный снапшот (accumulating snapshot): одна строка на экземпляр изделия,
-- вехи жизненного цикла, качество «с первого раза», затраты на качество, гарантия.
with first_ops as (
    select
        unit_id,
        max(brigade_id) filter (where section_type = 'WELD')  as weld_brigade_id,
        max(section_id) filter (where section_type = 'WELD')  as weld_section_id,
        max(brigade_id) filter (where section_type = 'PAINT') as paint_brigade_id,
        max(section_id) filter (where section_type = 'PAINT') as paint_section_id,
        bool_or(is_month_end_rush) filter (where step_no = 1) as started_in_rush
    from {{ ref('fct_operations') }}
    where not is_rework
    group by unit_id
),
dyn as (
    select distinct on (unit_id) unit_id, lab_id as dyn_lab_id, used_retired_equipment as dyn_on_retired_stand
    from {{ ref('fct_tests') }}
    where test_code = 'DYN'
    order by unit_id, attempt_no
),
leaks as (
    -- «утечка» после динамического стенда: дефект DYN-типа пойман позже - на обкатке или у дилера
    select unit_id from {{ ref('fct_defects') }}
    where detected_by_test = 'RUN' and defect_code in ('{{ var("dyn_defect_codes") | join("', '") }}')
    union
    select c.unit_id from {{ ref('int_warranty_claims_current') }} c
    where c.status <> 'rejected' and c.unit_id is not null
      and c.defect_code in ('{{ var("dyn_defect_codes") | join("', '") }}')
),
claims as (
    select
        unit_id,
        count(*) filter (where status <> 'rejected')        as warranty_claims_cnt,
        sum(approved_amount_rub)                            as warranty_cost_rub,
        min(claim_date) filter (where status <> 'rejected') as first_claim_date
    from {{ ref('int_warranty_claims_current') }}
    where unit_id is not null
    group by unit_id
),
asof as (
    select max(greatest(started_at, assembled_at, accepted_at)) as data_as_of from {{ ref('stg_plant__units') }}
)
select
    u.unit_id,
    u.serial_no,
    u.model_id,
    m.category_id,
    m.workshop_id,
    u.status,
    u.started_at,
    u.assembled_at,
    u.accepted_at,
    s.shipped_at,
    u.start_date,
    u.assembled_date,
    u.accepted_date,
    s.shipped_date,
    date_trunc('month', u.accepted_date)::date                                   as accepted_month,
    s.dealer_id,
    s.price_rub,
    m.std_cost_rub,
    round(extract(epoch from u.assembled_at - u.started_at)::numeric / 3600, 1)  as line_lead_time_h,
    round(extract(epoch from u.accepted_at - u.assembled_at)::numeric / 3600, 1) as test_lead_time_h,
    round(extract(epoch from u.accepted_at - u.started_at)::numeric / 3600, 1)   as total_lead_time_h,
    q.ops_cnt,
    q.rework_ops_cnt,
    q.line_defects_cnt,
    q.test_defects_cnt,
    q.failed_tests_cnt,
    case when u.accepted_at is not null then q.line_defects_cnt = 0 end                    as is_first_pass_line,
    case when u.accepted_at is not null then coalesce(q.all_tests_passed_first_time, true) end as is_first_pass_test,
    case when u.accepted_at is not null
         then q.line_defects_cnt = 0 and coalesce(q.all_tests_passed_first_time, true) end  as is_first_pass,
    q.line_rework_min + q.test_rework_min                                          as rework_minutes,
    round((q.line_rework_min + q.test_rework_min) / 60 * {{ param('labor_rate_rub_per_hour') }}, 2) as rework_cost_rub,
    fo.weld_section_id,
    fo.weld_brigade_id,
    fo.paint_section_id,
    fo.paint_brigade_id,
    coalesce(fo.started_in_rush, false)                                           as started_in_rush,
    dyn.dyn_lab_id,
    coalesce(dyn.dyn_on_retired_stand, false)                                     as dyn_on_retired_stand,
    lk.unit_id is not null                                                        as leaked_after_dyn,
    coalesce(c.warranty_claims_cnt, 0)                                            as warranty_claims_cnt,
    coalesce(c.warranty_cost_rub, 0)                                              as warranty_cost_rub,
    c.first_claim_date,
    c.first_claim_date - s.shipped_date                                           as days_to_first_claim,
    case when s.shipped_date is not null
         then least((asof.data_as_of AT TIME ZONE 'Europe/Moscow')::date - s.shipped_date,
                    {{ param('warranty_period_days') }}::int) end                 as days_in_service
from {{ ref('stg_plant__units') }} u
join {{ ref('stg_plant__product_models') }} m using (model_id)
join {{ ref('int_unit_quality') }} q          using (unit_id)
left join {{ ref('stg_plant__shipments') }} s using (unit_id)
left join first_ops fo                        using (unit_id)
left join dyn                                 using (unit_id)
left join claims c                            using (unit_id)
left join (select distinct unit_id from leaks) lk using (unit_id)
cross join asof
