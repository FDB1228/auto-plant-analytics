{{ config(severity='warn') }}
-- Аномалия план-факта по цеху за месяц (< 70% или > 130%) - сигнал проверить данные или процесс.
-- Последний месяц исключён: часть изделий ещё на испытаниях.
select month_start, workshop_id, sum(planned_qty) as plan, sum(accepted_qty) as fact
from {{ ref('fct_production_plan') }}
where month_start < (select max(month_start) from {{ ref('fct_production_plan') }})
  and month_start > (select min(month_start) from {{ ref('fct_production_plan') }})
group by month_start, workshop_id
having sum(accepted_qty) < 0.7 * sum(planned_qty) or sum(accepted_qty) > 1.3 * sum(planned_qty)
