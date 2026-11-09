{#- Схемы называются ровно так, как задано в +schema (staging, intermediate, marts),
    без префикса целевой схемы - так их проще находить из BI. -#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}{{ target.schema }}{%- else -%}{{ custom_schema_name | trim }}{%- endif -%}
{%- endmacro %}
