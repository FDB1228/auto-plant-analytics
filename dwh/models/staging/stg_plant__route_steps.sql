select
    rs.model_id,
    rs.step_no,
    rs.section_id,
    rs.section_type,
    rs.work_type_id,
    wt.code         as work_type_code,
    wt.name         as work_type_name,
    rs.std_minutes
from {{ source('plant', 'route_steps') }} rs
join {{ source('plant', 'work_types') }} wt using (work_type_id)
