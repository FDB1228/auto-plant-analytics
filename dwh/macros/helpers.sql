{#- Локальное время завода -#}
{% macro to_local(col) -%}
    ({{ col }} AT TIME ZONE 'Europe/Moscow')
{%- endmacro %}

{#- Рабочие сутки: ночная смена после полуночи (до 08:00) относится к предыдущему дню -#}
{% macro work_date(col) -%}
    (({{ col }} AT TIME ZONE 'Europe/Moscow') - interval '8 hours')::date
{%- endmacro %}

{#- Смена по локальному времени начала -#}
{% macro shift_of(col) -%}
    case when extract(hour from {{ col }} AT TIME ZONE 'Europe/Moscow') between 8 and 19
         then 'day' else 'night' end
{%- endmacro %}

{#- Значение бизнес-параметра из seed cost_parameters -#}
{% macro param(name) -%}
    (select value from {{ ref('cost_parameters') }} where parameter = '{{ name }}')
{%- endmacro %}

{#- Безопасное деление -#}
{% macro safe_div(num, den) -%}
    ({{ num }})::numeric / nullif({{ den }}, 0)
{%- endmacro %}
