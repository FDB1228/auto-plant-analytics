select lab_id, code as lab_code, name as lab_name
from {{ source('plant', 'labs') }}
