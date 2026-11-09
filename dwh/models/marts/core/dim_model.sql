-- Модели изделий: EAV-атрибуты разворачиваются в колонки (PIVOT через FILTER)
-- и собираются в одну строку характеристик для BI.
with attrs as (
    select
        model_id,
        max(value_num)  filter (where attribute_code = 'seats')            as seats,
        max(value_num)  filter (where attribute_code = 'engine_power')     as engine_power_hp,
        max(value_text) filter (where attribute_code = 'body_type')        as body_type,
        max(value_num)  filter (where attribute_code = 'payload')          as payload_t,
        max(value_text) filter (where attribute_code = 'axle_formula')     as axle_formula,
        max(value_num)  filter (where attribute_code = 'capacity')         as passenger_capacity,
        max(value_num)  filter (where attribute_code = 'length')           as length_m,
        max(value_num)  filter (where attribute_code = 'performance')      as performance,
        max(value_num)  filter (where attribute_code = 'operating_weight') as operating_weight_t,
        max(value_num)  filter (where attribute_code = 'engine_cc')        as engine_cc,
        max(value_num)  filter (where attribute_code = 'max_speed')        as max_speed_kmh,
        max(value_text) filter (where attribute_code = 'purpose')          as purpose,
        max(value_num)  filter (where attribute_code = 'dry_weight')       as dry_weight_kg,
        string_agg(attribute_name || ': ' || value_display, '; ' order by attribute_id) as specs
    from {{ ref('stg_plant__model_attributes') }}
    group by model_id
),
route as (
    select model_id, sum(std_minutes) as route_std_minutes, count(*) as route_steps
    from {{ ref('stg_plant__route_steps') }}
    group by model_id
)
select
    m.model_id,
    m.model_code,
    m.model_name,
    m.category_id,
    m.category_code,
    m.category_name,
    case when m.category_code in ('TRUCK', 'BUS', 'AGRI', 'ROAD') then 'Тяжёлая техника'
         when m.category_code = 'CAR' then 'Легковые'
         else 'Мото и прочее' end                     as product_group,
    m.workshop_id,
    w.workshop_code,
    w.workshop_name,
    m.launch_date,
    m.list_price_rub,
    m.std_cost_rub,
    m.std_margin_rub,
    r.route_std_minutes,
    r.route_steps,
    a.specs,
    a.seats, a.engine_power_hp, a.body_type, a.payload_t, a.axle_formula, a.passenger_capacity,
    a.length_m, a.performance, a.operating_weight_t, a.engine_cc, a.max_speed_kmh, a.purpose, a.dry_weight_kg
from {{ ref('stg_plant__product_models') }} m
join {{ ref('stg_plant__workshops') }} w using (workshop_id)
left join attrs a using (model_id)
left join route r using (model_id)
