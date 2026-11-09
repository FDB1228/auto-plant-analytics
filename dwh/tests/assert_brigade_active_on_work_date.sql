-- Операцию может выполнить только бригада, существующая на дату работ
select o.operation_id, o.brigade_id, o.work_date, b.formed_date, b.disbanded_date
from {{ ref('fct_operations') }} o
join {{ ref('dim_brigade') }} b using (brigade_id)
where o.work_date < b.formed_date
   or (b.disbanded_date is not null and o.work_date >= b.disbanded_date)
