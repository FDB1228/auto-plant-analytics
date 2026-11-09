select
    equipment_id,
    lab_id,
    inventory_no,
    name                 as equipment_name,
    test_type_id,
    commissioned_date,
    decommissioned_date
from {{ source('plant', 'equipment') }}
