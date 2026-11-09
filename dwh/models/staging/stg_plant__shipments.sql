select
    shipment_id,
    unit_id,
    dealer_id,
    shipped_at,
    {{ to_local('shipped_at') }}::date as shipped_date,
    price_rub
from {{ source('plant', 'shipments') }}
