select
    test_id,
    unit_id,
    test_type_id,
    attempt_no,
    lab_id,
    workshop_id,
    specialist_id,
    started_at,
    finished_at,
    {{ to_local('started_at') }}::date                                 as test_date,
    round(extract(epoch from finished_at - started_at)::numeric / 60, 1) as duration_min,
    result,
    result = 'fail'                                                    as is_fail
from {{ source('plant', 'tests') }}
