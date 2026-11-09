-- У каждой операции должен быть известен состав бригады на дату работ
select operation_id, brigade_id, work_date
from {{ ref('fct_operations') }}
where brigade_members_cnt is null or brigade_members_cnt = 0
