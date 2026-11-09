-- Тренд FPY по месяцам: скользящее среднее, изменение к прошлому месяцу и к тому же месяцу прошлого года
-- Навыки: оконные функции (AVG OVER ROWS, LAG), CTE
with monthly as (
    select accepted_month, workshop_id,
           count(*)                         as units,
           avg(is_first_pass::int)          as fpy
    from marts.fct_units
    where accepted_month is not null
    group by 1, 2
)
select
    w.workshop_code,
    m.accepted_month,
    m.units,
    round(m.fpy, 3)                                                                   as fpy,
    round(avg(m.fpy) over (partition by m.workshop_id order by m.accepted_month
                           rows between 2 preceding and current row), 3)              as fpy_ma3,
    round(m.fpy - lag(m.fpy) over (partition by m.workshop_id order by m.accepted_month), 3)     as d_mom,
    round(m.fpy - lag(m.fpy, 12) over (partition by m.workshop_id order by m.accepted_month), 3) as d_yoy,
    rank() over (partition by m.accepted_month order by m.fpy desc)                   as rank_in_month
from monthly m
join marts.dim_workshop w using (workshop_id)
order by w.workshop_code, m.accepted_month;
