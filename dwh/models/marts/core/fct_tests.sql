{{ config(materialized='incremental', unique_key='test_id', on_schema_change='append_new_columns') }}

with tests as (
    select t.*
    from {{ ref('stg_plant__tests') }} t
    {% if is_incremental() %}
    where t.finished_at > (select max(finished_at) - interval '3 days' from {{ this }})
    {% endif %}
),
eq as (
    select
        te.test_id,
        string_agg(e.equipment_name, ', ' order by e.equipment_id)              as equipment_used,
        bool_or(e.decommissioned_date is not null)                             as used_retired_equipment
    from {{ ref('stg_plant__test_equipment') }} te
    join {{ ref('stg_plant__equipment') }} e using (equipment_id, lab_id)
    {% if is_incremental() %}
    where te.test_id in (select test_id from tests)
    {% endif %}
    group by te.test_id
)
select
    t.test_id,
    t.unit_id,
    u.model_id,
    t.workshop_id,
    t.test_type_id,
    tt.test_code,
    tt.test_name,
    t.lab_id,
    t.specialist_id,
    t.attempt_no,
    t.started_at,
    t.finished_at,
    t.test_date,
    date_trunc('month', t.test_date)::date     as month_start,
    t.duration_min,
    t.result,
    t.is_fail,
    eq.equipment_used,
    coalesce(eq.used_retired_equipment, false) as used_retired_equipment
from tests t
join {{ ref('stg_plant__units') }} u        using (unit_id)
join {{ ref('stg_plant__test_types') }} tt  using (test_type_id)
left join eq                                using (test_id)
