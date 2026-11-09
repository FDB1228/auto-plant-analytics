-- Матрица гарантийных когорт: накопленная доля изделий с гарантийным случаем к 3/6/9/12 месяцам
-- (по витрине с учётом цензурирования; пусто = когорта ещё не прожила этот срок)
select
    cohort,
    sum(cohort_units) filter (where month_in_service = 0)                                      as units,
    round(100 * max(cumulative_claim_rate) filter (where month_in_service = 2), 2)              as m3_pct,
    round(100 * max(cumulative_claim_rate) filter (where month_in_service = 5), 2)              as m6_pct,
    round(100 * max(cumulative_claim_rate) filter (where month_in_service = 8), 2)              as m9_pct,
    round(100 * max(cumulative_claim_rate) filter (where month_in_service = 11), 2)             as m12_pct
from marts.mart_warranty_cohorts
where product_group = 'Тяжёлая техника'
group by cohort
order by cohort;
