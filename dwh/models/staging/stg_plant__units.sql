select
    unit_id,
    serial_no,
    model_id,
    status,
    started_at,
    assembled_at,
    accepted_at,
    {{ to_local('started_at') }}::date    as start_date,
    {{ to_local('assembled_at') }}::date  as assembled_date,
    {{ to_local('accepted_at') }}::date   as accepted_date,
    updated_at
from {{ source('plant', 'units') }}
