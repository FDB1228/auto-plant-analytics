-- Данные для оценки пилота стандарта сварки WS-2 (разность разностей):
-- участок × месяц, группа (pilot / control), период (до / после старта).
select
    o.month_start,
    o.section_id,
    s.section_name,
    s.workshop_code,
    s.ws2_group,
    s.ws2_pilot_start,
    o.month_start >= s.ws2_pilot_start                                   as is_post_period,
    count(*)                                                             as operations,
    count(*) filter (where o.caused_defect)                              as defect_operations,
    round({{ safe_div('count(*) filter (where o.caused_defect)', 'count(*)') }}, 4) as defect_rate,
    round(avg(o.duration_min / o.std_minutes), 4)                        as avg_duration_to_std,
    round(sum(o.duration_min) / 60, 1)                                   as labor_hours
from {{ ref('fct_operations') }} o
join {{ ref('dim_section') }} s using (section_id)
where s.ws2_group is not null and not o.is_rework
group by 1, 2, 3, 4, 5, 6, 7
