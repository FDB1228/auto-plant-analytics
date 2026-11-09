{#-
  SCD2-история сотрудников: смена профессии, разряда, увольнение.
  Каждый прогон пайплайна фиксирует изменения с момента предыдущего прогона.
-#}
{% snapshot snap_employees %}
{{
    config(
        unique_key='employee_id',
        strategy='check',
        check_cols=['full_name', 'profession_id', 'skill_grade', 'qualification_category', 'termination_date'],
        invalidate_hard_deletes=True
    )
}}
select
    employee_id, personnel_no, full_name, profession_id, profession_name, staff_category,
    hire_date, termination_date, skill_grade, qualification_category
from {{ ref('stg_plant__employees') }}
{% endsnapshot %}
