-- Парето дефектов: какие типы дают 80% затрат на доработку и гарантию
-- Навыки: накопительная сумма (SUM OVER), доля от итога, NTILE-подобная категоризация ABC
with costs as (
    select dt.defect_code, dt.defect_name, dt.origin_area_name,
           count(*) filter (where f.detection_point = 'line') as found_on_line,
           count(*) filter (where f.detection_point = 'test') as found_on_test,
           sum(f.rework_cost_rub)                             as rework_cost
    from marts.fct_defects f join marts.dim_defect_type dt using (defect_type_id)
    group by 1, 2, 3
),
warranty as (
    select dt.defect_code, count(*) filter (where c.status <> 'rejected') as claims, sum(c.approved_amount_rub) as warranty_cost
    from marts.fct_warranty_claims c join marts.dim_defect_type dt using (defect_type_id)
    group by 1
),
total as (
    select c.*, coalesce(w.claims, 0) as claims, coalesce(w.warranty_cost, 0) as warranty_cost,
           c.rework_cost + coalesce(w.warranty_cost, 0) as total_cost
    from costs c left join warranty w using (defect_code)
)
select
    defect_code, defect_name, origin_area_name, found_on_line, found_on_test, claims,
    round(total_cost / 1e3)                                                          as total_cost_k,
    round(100 * total_cost / sum(total_cost) over (), 1)                             as share_pct,
    round(100 * sum(total_cost) over (order by total_cost desc) / sum(total_cost) over (), 1) as cum_share_pct,
    case when sum(total_cost) over (order by total_cost desc) - total_cost < 0.8 * sum(total_cost) over () then 'A'
         when sum(total_cost) over (order by total_cost desc) - total_cost < 0.95 * sum(total_cost) over () then 'B'
         else 'C' end                                                                as abc_class,
    round(found_on_test::numeric / nullif(found_on_line + found_on_test, 0), 3)      as share_escaped_line
from total
order by total_cost desc;
