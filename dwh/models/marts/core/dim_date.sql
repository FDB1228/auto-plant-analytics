-- Календарь с производственными признаками: рабочий день, номер рабочего дня в месяце,
-- последние N рабочих дней месяца («штурмовщина»).
with days as (
    select d::date as date_day
    from generate_series(date '2024-01-01', date '2027-12-31', interval '1 day') d
),
flags as (
    select
        d.date_day,
        h.holiday_name,
        extract(isodow from d.date_day) >= 6 or h.holiday_date is not null as is_non_working
    from days d
    left join {{ ref('ru_holidays') }} h on h.holiday_date = d.date_day
),
wd as (
    select
        f.*,
        case when not is_non_working then
            row_number() over (partition by date_trunc('month', date_day), is_non_working order by date_day)
        end as working_day_of_month,
        case when not is_non_working then
            row_number() over (partition by date_trunc('month', date_day), is_non_working order by date_day desc)
        end as working_days_to_month_end
    from flags f
)
select
    date_day,
    extract(year from date_day)::int                                         as year,
    extract(quarter from date_day)::int                                      as quarter,
    extract(month from date_day)::int                                        as month,
    date_trunc('month', date_day)::date                                      as month_start,
    to_char(date_day, 'YYYY-MM')                                             as year_month,
    (array['Январь','Февраль','Март','Апрель','Май','Июнь','Июль','Август',
           'Сентябрь','Октябрь','Ноябрь','Декабрь'])[extract(month from date_day)::int] as month_name,
    extract(year from date_day)::int || '-Q' || extract(quarter from date_day)::int as year_quarter,
    date_trunc('week', date_day)::date                                       as week_start,
    extract(isodow from date_day)::int                                       as iso_dow,
    (array['Пн','Вт','Ср','Чт','Пт','Сб','Вс'])[extract(isodow from date_day)::int] as dow_name,
    holiday_name,
    not is_non_working                                                       as is_working_day,
    working_day_of_month,
    working_days_to_month_end,
    coalesce(working_days_to_month_end <= {{ param('rush_working_days') }}, false) as is_month_end_rush,
    count(*) filter (where not is_non_working)
        over (partition by date_trunc('month', date_day))                    as working_days_in_month
from wd
