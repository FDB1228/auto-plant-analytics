-- SCD2-измерение сотрудников на основе снапшота: каждая версия атрибутов - отдельная строка
select
    dbt_scd_id                                   as employee_version_key,
    employee_id,
    personnel_no,
    full_name,
    profession_name,
    staff_category,
    hire_date,
    termination_date,
    skill_grade,
    qualification_category,
    dbt_valid_from                               as valid_from,
    dbt_valid_to                                 as valid_to,
    dbt_valid_to is null                         as is_current
from {{ ref('snap_employees') }}
