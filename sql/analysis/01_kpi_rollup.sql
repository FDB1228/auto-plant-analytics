-- Выпуск, FPY и выручка по цехам и категориям с подытогами (ROLLUP)
-- Навыки: GROUPING / ROLLUP, FILTER, условная агрегация
select
    case when grouping(w.workshop_code) = 1 then 'ИТОГО завод' else w.workshop_code end       as workshop,
    case when grouping(dm.category_name) = 1 and grouping(w.workshop_code) = 0 then 'итого по цеху'
         else dm.category_name end                                                          as category,
    count(*)                                                                                as units_accepted,
    round(avg(u.is_first_pass::int), 3)                                                     as fpy,
    round(sum(u.price_rub) / 1e6, 1)                                                        as revenue_mln,
    round(sum(u.rework_cost_rub + u.warranty_cost_rub) / nullif(sum(u.price_rub), 0) * 100, 3) as copq_pct_revenue
from marts.fct_units u
join marts.dim_model dm using (model_id)
join marts.dim_workshop w on w.workshop_id = u.workshop_id
where u.accepted_at is not null
group by rollup (w.workshop_code, dm.category_name)
order by grouping(w.workshop_code), w.workshop_code, grouping(dm.category_name), dm.category_name;
