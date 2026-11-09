select
    leader_period_id,
    brigade_id,
    employee_id,
    valid_from,
    valid_to,
    coalesce(valid_to, date '9999-12-31') as valid_to_filled
from {{ source('plant', 'brigade_leaders') }}
