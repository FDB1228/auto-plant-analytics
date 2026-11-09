select
    operation_id,
    unit_id,
    model_id,
    step_no,
    attempt_no,
    attempt_no > 1                                               as is_rework,
    section_id,
    brigade_id,
    started_at,
    finished_at,
    {{ work_date('started_at') }}                                 as work_date,
    {{ shift_of('started_at') }}                                  as shift,
    round(extract(epoch from finished_at - started_at)::numeric / 60, 1) as duration_min,
    result,
    result = 'defect'                                            as is_line_defect
from {{ source('plant', 'operations') }}
