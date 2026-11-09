select
    s.section_id,
    s.workshop_id,
    s.section_type,
    st.name        as section_type_name,
    s.code         as section_code,
    s.name         as section_name
from {{ source('plant', 'sections') }} s
join {{ source('plant', 'section_types') }} st using (section_type)
