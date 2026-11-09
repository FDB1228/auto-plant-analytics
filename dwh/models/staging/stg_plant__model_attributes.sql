-- EAV-атрибуты моделей с определениями и «человекочитаемым» значением
select
    v.model_id,
    a.attribute_id,
    a.code                                                  as attribute_code,
    a.name                                                  as attribute_name,
    a.unit,
    a.data_type,
    v.value_num,
    v.value_text,
    coalesce(trim(trailing '.' from trim(trailing '0' from v.value_num::text)), v.value_text)
        || coalesce(' ' || a.unit, '')                      as value_display
from {{ source('plant', 'model_attribute_values') }} v
join {{ source('plant', 'category_attributes') }} a using (attribute_id, category_id)
