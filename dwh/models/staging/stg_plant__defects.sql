select
    defect_id,
    unit_id,
    defect_type_id,
    severity,
    detection_point,
    detected_at,
    {{ to_local('detected_at') }}::date as detected_date,
    operation_id,
    test_id,
    origin_operation_id,
    rework_minutes
from {{ source('plant', 'defects') }}
