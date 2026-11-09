-- Качество работы бригад по месяцам: доля операций, ставших источником дефекта,
-- и кадровый состав (стаж, доля новичков) - для анализа первопричин.
select
    o.month_start,
    o.brigade_id,
    b.brigade_name,
    b.shift,
    b.shift_name,
    b.section_id,
    b.section_name,
    b.section_type,
    b.workshop_code,
    count(*)                                                         as operations,
    count(*) filter (where o.caused_defect)                          as defect_operations,
    round({{ safe_div('count(*) filter (where o.caused_defect)', 'count(*)') }}, 4) as defect_rate,
    count(*) filter (where o.defect_escaped_line)                    as escaped_defect_operations,
    round(avg(o.brigade_members_cnt), 1)                             as avg_members,
    round(avg(o.brigade_avg_tenure_days), 0)                         as avg_tenure_days,
    round(avg(o.brigade_newcomer_share), 3)                          as avg_newcomer_share,
    round(avg(o.std_to_actual_ratio), 3)                             as avg_std_to_actual_ratio,
    min(o.brigade_age_days)                                          as brigade_age_days_at_month_start
from {{ ref('fct_operations') }} o
join {{ ref('dim_brigade') }} b using (brigade_id)
where not o.is_rework
group by 1, 2, 3, 4, 5, 6, 7, 8, 9
