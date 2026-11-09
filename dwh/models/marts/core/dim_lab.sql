select
    l.lab_id,
    l.lab_code,
    l.lab_name,
    string_agg(w.workshop_code, ', ' order by w.workshop_id) as served_workshops
from {{ ref('stg_plant__labs') }} l
join {{ source('plant', 'lab_workshops') }} lw using (lab_id)
join {{ ref('stg_plant__workshops') }} w using (workshop_id)
group by l.lab_id, l.lab_code, l.lab_name
