select
    m.model_id,
    m.code               as model_code,
    m.name               as model_name,
    m.category_id,
    c.code               as category_code,
    c.name               as category_name,
    m.workshop_id,
    m.launch_date,
    m.discontinued_date,
    m.list_price_rub,
    m.std_cost_rub,
    m.list_price_rub - m.std_cost_rub as std_margin_rub
from {{ source('plant', 'product_models') }} m
join {{ source('plant', 'product_categories') }} c using (category_id)
