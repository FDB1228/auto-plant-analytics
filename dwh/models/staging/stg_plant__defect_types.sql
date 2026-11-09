select
    defect_type_id,
    code          as defect_code,
    name          as defect_name,
    section_type  as origin_area
from {{ source('plant', 'defect_types') }}
