-- Распределение цикла изготовления (запуск -> приёмка ОТК) по моделям: медиана, P90, «хвосты»
-- Навыки: PERCENTILE_CONT, сравнение с нормативом маршрута, LATERAL для топ-N
select
    dm.model_name,
    count(*)                                                                         as units,
    round(dm.route_std_minutes / 60.0, 1)                                            as route_std_hours,
    round(percentile_cont(0.5) within group (order by u.total_lead_time_h)::numeric, 1) as p50_h,
    round(percentile_cont(0.9) within group (order by u.total_lead_time_h)::numeric, 1) as p90_h,
    round((percentile_cont(0.9) within group (order by u.total_lead_time_h)
         / percentile_cont(0.5) within group (order by u.total_lead_time_h))::numeric, 2) as tail_ratio,
    worst.serial_no                                                                  as slowest_unit,
    worst.total_lead_time_h                                                          as slowest_h
from marts.fct_units u
join marts.dim_model dm using (model_id)
cross join lateral (
    select u2.serial_no, u2.total_lead_time_h
    from marts.fct_units u2
    where u2.model_id = dm.model_id and u2.total_lead_time_h is not null
    order by u2.total_lead_time_h desc limit 1
) worst
where u.total_lead_time_h is not null
group by dm.model_name, dm.route_std_minutes, worst.serial_no, worst.total_lead_time_h
order by p50_h desc;
