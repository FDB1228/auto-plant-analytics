-- Состояние бригады на каждый рабочий день: численность, средний стаж, доля новичков, бригадир.
-- Стаж считается от даты приёма на завод. Новичок - стаж меньше порога из cost_parameters.
with days as (
    select date_day
    from {{ ref('dim_date') }}
    where date_day between (select min(work_date) from {{ ref('stg_plant__operations') }})
                       and (select max(work_date) from {{ ref('stg_plant__operations') }})
),
member_days as (
    select
        m.brigade_id,
        d.date_day,
        d.date_day - e.hire_date as tenure_days
    from {{ ref('stg_plant__brigade_memberships') }} m
    join {{ ref('stg_plant__employees') }} e using (employee_id)
    join days d
      on d.date_day >= m.valid_from and d.date_day < m.valid_to_filled
)
select
    md.brigade_id,
    md.date_day,
    count(*)                                                                as members_cnt,
    round(avg(md.tenure_days), 1)                                           as avg_tenure_days,
    round(avg((md.tenure_days < {{ param('newcomer_tenure_days') }})::int), 3) as newcomer_share,
    min(l.employee_id)                                                      as leader_employee_id
from member_days md
left join {{ ref('stg_plant__brigade_leaders') }} l
  on l.brigade_id = md.brigade_id
 and md.date_day >= l.valid_from and md.date_day < l.valid_to_filled
group by md.brigade_id, md.date_day
