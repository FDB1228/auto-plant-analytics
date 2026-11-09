select
    d.month_start,
    d.section_id,
    s.section_full_name,
    s.workshop_code,
    d.reason_code,
    d.reason_name,
    d.is_planned,
    count(*)                    as events,
    round(sum(d.duration_h), 1) as downtime_hours,
    round(max(d.duration_h), 1) as longest_event_h
from {{ ref('fct_downtime') }} d
join {{ ref('dim_section') }} s using (section_id)
group by 1, 2, 3, 4, 5, 6, 7
