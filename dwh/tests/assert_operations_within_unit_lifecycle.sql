-- Все операции экземпляра выполнены между запуском и окончанием сборки
select o.operation_id, o.unit_id, o.started_at, u.started_at as unit_started_at, u.assembled_at
from {{ ref('fct_operations') }} o
join {{ ref('fct_units') }} u using (unit_id)
where o.started_at < u.started_at
   or (u.assembled_at is not null and o.finished_at > u.assembled_at)
