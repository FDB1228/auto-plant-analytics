select
    brigade_id,
    section_id,
    name            as brigade_name,
    shift,
    formed_date,
    disbanded_date
from {{ source('plant', 'brigades') }}
