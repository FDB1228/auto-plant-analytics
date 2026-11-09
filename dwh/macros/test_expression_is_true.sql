{#- Generic-тест: строки, для которых выражение ложно, считаются ошибками -#}
{% test expression_is_true(model, expression, column_name=none, where=none) %}
select *
from {{ model }}
where not ({{ expression }})
{%- if where %} and {{ where }}{% endif %}
{% endtest %}

{#- Generic-тест: значение в диапазоне -#}
{% test between(model, column_name, min_value, max_value) %}
select *
from {{ model }}
where {{ column_name }} < {{ min_value }} or {{ column_name }} > {{ max_value }}
{% endtest %}

{#- Generic-тест: уникальность комбинации колонок -#}
{% test unique_combination(model, columns) %}
select {{ columns | join(', ') }}, count(*) as n
from {{ model }}
group by {{ columns | join(', ') }}
having count(*) > 1
{% endtest %}
