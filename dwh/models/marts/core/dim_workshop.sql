select
    w.workshop_id,
    w.workshop_code,
    w.workshop_name,
    w.shifts_per_day,
    h.full_name as workshop_head
from {{ ref('stg_plant__workshops') }} w
left join {{ ref('stg_plant__management_assignments') }} ma
  on ma.workshop_id = w.workshop_id and ma.role_code = 'workshop_head' and ma.valid_to is null
left join {{ ref('stg_plant__employees') }} h on h.employee_id = ma.employee_id
