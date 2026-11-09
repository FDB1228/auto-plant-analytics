-- SCD2: у сотрудника ровно одна актуальная версия и версии не пересекаются во времени
select employee_id, count(*) filter (where is_current) as current_versions
from {{ ref('dim_employee') }}
group by employee_id
having count(*) filter (where is_current) <> 1
union all
select a.employee_id, null
from {{ ref('dim_employee') }} a
join {{ ref('dim_employee') }} b
  on a.employee_id = b.employee_id and a.employee_version_key <> b.employee_version_key
 and a.valid_from < coalesce(b.valid_to, 'infinity') and b.valid_from < coalesce(a.valid_to, 'infinity')
