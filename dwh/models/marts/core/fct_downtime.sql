select
    d.downtime_id,
    d.section_id,
    s.workshop_id,
    d.reason_code,
    d.reason_name,
    d.is_planned,
    d.started_at,
    d.ended_at,
    d.work_date,
    date_trunc('month', d.work_date)::date as month_start,
    d.duration_h
from {{ ref('stg_plant__section_downtimes') }} d
join {{ ref('dim_section') }} s using (section_id)
