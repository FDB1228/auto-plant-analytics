-- Гарантийные когорты (таблица дожития): доля изделий с гарантийным случаем
-- к k-му месяцу эксплуатации по квартальным когортам отгрузки.
-- Учитывается цензурирование (изделия, отгруженные недавно, ещё не прожили k месяцев): изделие входит в риск-множество месяца k,
-- только если наблюдается весь месяц k (или случай произошёл в нём).
with units as (
    select
        u.unit_id,
        to_char(date_trunc('quarter', u.shipped_date), 'YYYY-"Q"Q')        as cohort,
        dm.product_group,
        floor(u.days_in_service / 30.4375)::int                           as months_observed,
        floor(u.days_to_first_claim / 30.4375)::int                       as claim_month_k
    from {{ ref('fct_units') }} u
    join {{ ref('dim_model') }} dm using (model_id)
    where u.shipped_date is not null
),
k as (select generate_series(0, 23) as k),
life as (
    select
        u.cohort,
        u.product_group,
        k.k,
        count(*) filter (where (u.claim_month_k is null or u.claim_month_k >= k.k)
                           and (u.months_observed > k.k or u.claim_month_k = k.k))  as at_risk,
        count(*) filter (where u.claim_month_k = k.k)                               as events
    from units u
    cross join k
    group by 1, 2, 3
),
stable as (
    -- месяцы, где в риск-множестве меньше 30 изделий, статистически ненадёжны - отсекаем хвост
    select * from life where at_risk >= 30
),
cohort_size as (
    select cohort, product_group, count(*) as cohort_units from units group by 1, 2
)
select
    l.cohort,
    l.product_group,
    cs.cohort_units,
    l.k                                                         as month_in_service,
    l.at_risk,
    l.events,
    round({{ safe_div('l.events', 'l.at_risk') }}, 5)           as hazard,
    round(1 - exp(sum(ln(1 - least(coalesce(l.events::numeric / nullif(l.at_risk, 0), 0), 0.999999)))
            over (partition by l.cohort, l.product_group order by l.k)), 5) as cumulative_claim_rate
from stable l
join cohort_size cs using (cohort, product_group)
