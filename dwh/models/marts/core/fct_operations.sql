{#-
  Факт операций (зерно: одна операция, включая доработки). Инкрементальная модель.
  Окно пересчёта - 3 дня от последней загруженной операции, плюс «поздние» факты:
  операции, по которым дефект обнаружен позже (на испытаниях) - их флаг caused_defect
  меняется задним числом.
-#}
{{ config(materialized='incremental', unique_key='operation_id', on_schema_change='append_new_columns',
          indexes=[{'columns': ['work_date']}, {'columns': ['brigade_id', 'work_date']}, {'columns': ['unit_id']}]) }}

with watermark as (
    {% if is_incremental() %}
    select max(finished_at) - interval '3 days' as since from {{ this }}
    {% else %}
    select timestamptz '1900-01-01' as since
    {% endif %}
),
ops as (
    select o.*
    from {{ ref('stg_plant__operations') }} o
    {% if is_incremental() %}
    where o.finished_at > (select since from watermark)
       or o.operation_id in (
            select origin_operation_id
            from {{ ref('stg_plant__defects') }}
            where detected_at > (select since from watermark) and origin_operation_id is not null)
    {% endif %}
),
origin_defects as (
    select
        origin_operation_id                                      as operation_id,
        count(*)                                                 as defects_originated,
        count(*) filter (where detection_point = 'test')         as defects_escaped_line
    from {{ ref('stg_plant__defects') }}
    where origin_operation_id is not null
    group by origin_operation_id
)
select
    o.operation_id,
    o.unit_id,
    o.model_id,
    o.step_no,
    rs.work_type_id,
    rs.work_type_name,
    o.section_id,
    sec.section_type,
    sec.workshop_id,
    o.brigade_id,
    o.attempt_no,
    o.is_rework,
    o.started_at,
    o.finished_at,
    o.work_date,
    dd.month_start,
    o.shift,
    dd.is_month_end_rush,
    o.duration_min,
    rs.std_minutes,
    case when not o.is_rework then round(rs.std_minutes / o.duration_min, 3) end as std_to_actual_ratio,
    o.result,
    o.is_line_defect,
    coalesce(od.defects_originated, 0) > 0                     as caused_defect,
    coalesce(od.defects_escaped_line, 0) > 0                   as defect_escaped_line,
    bd.members_cnt                                             as brigade_members_cnt,
    bd.avg_tenure_days                                         as brigade_avg_tenure_days,
    bd.newcomer_share                                          as brigade_newcomer_share,
    o.work_date - b.formed_date                                as brigade_age_days,
    sec.ws2_group,
    sec.ws2_group is not null and o.work_date >= sec.ws2_pilot_start as is_ws2_post_period
from ops o
join {{ ref('stg_plant__route_steps') }} rs on rs.model_id = o.model_id and rs.step_no = o.step_no
join {{ ref('dim_section') }} sec           on sec.section_id = o.section_id
join {{ ref('stg_plant__brigades') }} b     on b.brigade_id = o.brigade_id
join {{ ref('dim_date') }} dd               on dd.date_day = o.work_date
left join {{ ref('int_brigade_daily') }} bd on bd.brigade_id = o.brigade_id and bd.date_day = o.work_date
left join origin_defects od                 on od.operation_id = o.operation_id
