select
    d.downtime_id,
    d.section_id,
    d.reason_code,
    r.name                                                              as reason_name,
    r.is_planned,
    d.started_at,
    d.ended_at,
    {{ work_date('d.started_at') }}                                     as work_date,
    round(extract(epoch from d.ended_at - d.started_at)::numeric / 3600, 2) as duration_h
from {{ source('plant', 'section_downtimes') }} d
join {{ source('plant', 'downtime_reasons') }} r using (reason_code)
