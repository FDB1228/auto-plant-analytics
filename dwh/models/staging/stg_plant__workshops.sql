select
    workshop_id,
    code           as workshop_code,
    name           as workshop_name,
    shifts_per_day
from {{ source('plant', 'workshops') }}
