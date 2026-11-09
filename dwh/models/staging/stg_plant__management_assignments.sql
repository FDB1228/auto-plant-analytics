select
    ma.assignment_id,
    ma.employee_id,
    ma.role_code,
    r.name                                   as role_name,
    ma.workshop_id,
    ma.section_id,
    ma.valid_from,
    ma.valid_to,
    coalesce(ma.valid_to, date '9999-12-31') as valid_to_filled
from {{ source('plant', 'management_assignments') }} ma
join {{ source('plant', 'management_roles') }} r using (role_code)
