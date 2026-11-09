select test_id, lab_id, equipment_id
from {{ source('plant', 'test_equipment') }}
