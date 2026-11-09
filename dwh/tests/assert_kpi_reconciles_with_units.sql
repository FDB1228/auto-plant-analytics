-- Сверка витрины с фактом: число принятых изделий в дневных KPI = числу в fct_units
select k.kpi_total, u.fact_total
from (select sum(units_accepted) as kpi_total from {{ ref('mart_daily_workshop_kpi') }}) k
cross join (select count(*) as fact_total from {{ ref('fct_units') }} where accepted_date is not null) u
where k.kpi_total <> u.fact_total
