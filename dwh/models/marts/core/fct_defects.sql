-- Дефекты, обнаруженные на заводе, с прослеживанием до операции-источника
-- (участок, бригада, смена, дата) и стоимостью доработки.
select
    d.defect_id,
    d.unit_id,
    u.model_id,
    m.workshop_id,
    d.defect_type_id,
    dt.defect_code,
    dt.origin_area,
    d.severity,
    d.detection_point,
    d.detected_at,
    d.detected_date,
    date_trunc('month', d.detected_date)::date                     as month_start,
    t.lab_id                                                       as detected_in_lab_id,
    t.test_code                                                    as detected_by_test,
    d.origin_operation_id is not null                              as is_traced,
    o.section_id                                                   as origin_section_id,
    o.brigade_id                                                   as origin_brigade_id,
    o.work_date                                                    as origin_work_date,
    o.shift                                                        as origin_shift,
    d.detected_date - o.work_date                                  as days_to_detection,
    d.rework_minutes,
    round(d.rework_minutes / 60 * {{ param('labor_rate_rub_per_hour') }}, 2) as rework_cost_rub
from {{ ref('stg_plant__defects') }} d
join {{ ref('stg_plant__units') }} u               using (unit_id)
join {{ ref('stg_plant__product_models') }} m      on m.model_id = u.model_id
join {{ ref('stg_plant__defect_types') }} dt       using (defect_type_id)
left join {{ ref('fct_tests') }} t                 on t.test_id = d.test_id
left join {{ ref('stg_plant__operations') }} o     on o.operation_id = d.origin_operation_id
