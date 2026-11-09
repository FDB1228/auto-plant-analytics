-- Дефектность в зависимости от доли новичков в бригаде, по типам участков (PIVOT через FILTER)
-- Навыки: WIDTH_BUCKET / CASE-бакетирование, PIVOT условной агрегацией
with ops as (
    select section_type,
           case when brigade_newcomer_share = 0 then '0%'
                when brigade_newcomer_share <= 0.25 then '1-25%'
                when brigade_newcomer_share <= 0.5 then '26-50%'
                else '>50%' end as newcomer_bucket,
           caused_defect
    from marts.fct_operations
    where not is_rework
)
select
    newcomer_bucket,
    count(*)                                                                                   as operations,
    round(avg(caused_defect::int) filter (where section_type = 'WELD')  * 100, 2) as weld_pct,
    round(avg(caused_defect::int) filter (where section_type = 'PAINT') * 100, 2) as paint_pct,
    round(avg(caused_defect::int) filter (where section_type = 'ASSY')  * 100, 2) as assy_pct,
    round(avg(caused_defect::int) filter (where section_type = 'FIN')   * 100, 2) as fin_pct,
    round(avg(caused_defect::int) * 100, 2)                                       as all_pct
from ops
group by newcomer_bucket
order by min(case newcomer_bucket when '0%' then 1 when '1-25%' then 2 when '26-50%' then 3 else 4 end);
