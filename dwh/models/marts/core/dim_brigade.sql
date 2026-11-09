select
    b.brigade_id,
    b.brigade_name,
    b.shift,
    case b.shift when 'day' then 'Дневная' else 'Ночная' end     as shift_name,
    b.formed_date,
    b.disbanded_date,
    b.disbanded_date is null                                     as is_active,
    s.section_id,
    s.section_name,
    s.section_type,
    s.workshop_id,
    s.workshop_code,
    s.workshop_code || ' · ' || s.section_name || ' · ' || b.brigade_name as brigade_full_name
from {{ ref('stg_plant__brigades') }} b
join {{ ref('dim_section') }} s using (section_id)
