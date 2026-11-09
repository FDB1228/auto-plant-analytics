-- «Серии» отказов оборудования: подряд идущие рабочие дни с внеплановыми простоями на участке
-- Навыки: gaps-and-islands (разность ROW_NUMBER), агрегация островов
with days as (
    select distinct d.section_id, d.work_date
    from marts.fct_downtime d
    where not d.is_planned
),
numbered as (
    select ds.section_id, ds.work_date, dd.working_day_index,
           dd.working_day_index - row_number() over (partition by ds.section_id order by ds.work_date) as island
    from days ds
    join (select date_day, row_number() over (order by date_day) as working_day_index
          from marts.dim_date where is_working_day) dd on dd.date_day = ds.work_date
),
islands as (
    select section_id, island, min(work_date) as series_start, max(work_date) as series_end, count(*) as days_in_row
    from numbered group by section_id, island
)
select s.section_full_name, i.series_start, i.series_end, i.days_in_row,
       round(sum(f.duration_h), 1) as downtime_hours, count(f.downtime_id) as events
from islands i
join marts.dim_section s using (section_id)
join marts.fct_downtime f on f.section_id = i.section_id and f.work_date between i.series_start and i.series_end
                         and not f.is_planned
where i.days_in_row >= 3
group by 1, 2, 3, 4
order by downtime_hours desc;
