select dealer_id, code as dealer_code, name as dealer_name, segment, region, city
from {{ source('plant', 'dealers') }}
