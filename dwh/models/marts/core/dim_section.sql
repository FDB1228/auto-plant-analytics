-- Участки с цехом, текущим начальником (NULL = вакансия) и группой пилота стандарта сварки WS-2
select
    s.section_id,
    s.section_code,
    s.section_name,
    s.section_type,
    s.section_type_name,
    w.workshop_id,
    w.workshop_code,
    w.workshop_name,
    w.workshop_code || ' · ' || s.section_name                   as section_full_name,
    h.full_name                                                  as section_head,
    p.ws2_group,
    p.pilot_start                                                as ws2_pilot_start
from {{ ref('stg_plant__sections') }} s
join {{ ref('stg_plant__workshops') }} w using (workshop_id)
left join {{ ref('ws2_pilot') }} p on p.section_code = s.section_code
left join {{ ref('stg_plant__management_assignments') }} ma
  on ma.section_id = s.section_id and ma.role_code = 'section_head' and ma.valid_to is null
left join {{ ref('stg_plant__employees') }} h on h.employee_id = ma.employee_id
