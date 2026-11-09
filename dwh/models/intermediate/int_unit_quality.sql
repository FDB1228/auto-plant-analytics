-- Качество по экземпляру: доработки на линии, результаты испытаний, затраты на доработку
with ops as (
    select
        unit_id,
        count(*) filter (where not is_rework)       as ops_cnt,
        count(*) filter (where is_rework)           as rework_ops_cnt,
        count(*) filter (where is_line_defect)      as line_defects_cnt
    from {{ ref('stg_plant__operations') }}
    group by unit_id
),
tst as (
    select
        unit_id,
        count(distinct test_type_id)                as test_types_cnt,
        count(*)                                    as tests_cnt,
        count(*) filter (where is_fail)             as failed_tests_cnt,
        bool_and(not is_fail) filter (where attempt_no = 1) as all_tests_passed_first_time,
        sum(duration_min)                           as test_minutes
    from {{ ref('stg_plant__tests') }}
    group by unit_id
),
dfx as (
    select
        unit_id,
        count(*) filter (where detection_point = 'test')                   as test_defects_cnt,
        coalesce(sum(rework_minutes) filter (where detection_point = 'line'), 0) as line_rework_min,
        coalesce(sum(rework_minutes) filter (where detection_point = 'test'), 0) as test_rework_min
    from {{ ref('stg_plant__defects') }}
    group by unit_id
)
select
    u.unit_id,
    coalesce(o.ops_cnt, 0)                  as ops_cnt,
    coalesce(o.rework_ops_cnt, 0)           as rework_ops_cnt,
    coalesce(o.line_defects_cnt, 0)         as line_defects_cnt,
    coalesce(d.test_defects_cnt, 0)         as test_defects_cnt,
    coalesce(t.tests_cnt, 0)                as tests_cnt,
    coalesce(t.failed_tests_cnt, 0)         as failed_tests_cnt,
    t.all_tests_passed_first_time,
    coalesce(d.line_rework_min, 0)          as line_rework_min,
    coalesce(d.test_rework_min, 0)          as test_rework_min
from {{ ref('stg_plant__units') }} u
left join ops o using (unit_id)
left join tst t using (unit_id)
left join dfx d using (unit_id)
