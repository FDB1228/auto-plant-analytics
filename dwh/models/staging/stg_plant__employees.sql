select
    e.employee_id,
    e.personnel_no,
    e.full_name,
    e.profession_id,
    p.name                         as profession_name,
    e.staff_category,
    e.hire_date,
    e.termination_date,
    e.termination_date is null     as is_active,
    wd.skill_grade,
    itr.qualification_category,
    greatest(e.updated_at, coalesce(wd.updated_at, e.updated_at)) as updated_at
from {{ source('plant', 'employees') }} e
join {{ source('plant', 'professions') }} p using (profession_id)
left join {{ source('plant', 'worker_details') }} wd using (employee_id)
left join {{ source('plant', 'itr_details') }} itr using (employee_id)
