select test_type_id, code as test_code, name as test_name
from {{ source('plant', 'test_types') }}
