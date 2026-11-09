select
    dt.defect_type_id,
    dt.defect_code,
    dt.defect_name,
    dt.origin_area,
    st.name as origin_area_name
from {{ ref('stg_plant__defect_types') }} dt
join {{ source('plant', 'section_types') }} st on st.section_type = dt.origin_area
