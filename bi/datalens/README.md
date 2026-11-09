# Yandex DataLens: дашборд «Производство и качество»

DataLens - облачный сервис, до локального PostgreSQL он не достучится. Поэтому есть два пути:

| Путь | Когда | Как |
|---|---|---|
| **Файлы (CSV)** | для портфолио - быстро и бесплатно | загрузить CSV из `bi/exports` в подключение «Файлы» |
| **PostgreSQL** | база доступна из интернета (Yandex Managed PostgreSQL, свой сервер) | подключение PostgreSQL → схема `marts`; датасеты те же |

Сборка занимает 1-1.5 часа. После публикации дашборда вставьте ссылку в README проекта (раздел «Дашборды») - это сильнее любого скриншота.

## 1. Подключение и датасеты

Подключение → **Файлы** → загрузить все CSV из `bi/exports` (UTF-8, разделитель запятая, первая строка - заголовки). Проверить типы: `*_date`, `month_start`, `date_day` - «Дата»; `is_*` - «Логический»; суммы и доли - «Дробное число».

Датасеты (связи - на вкладке «Источники», LEFT JOIN по ключу):

| Датасет | Источник | Связи |
|---|---|---|
| `ds_kpi_daily` | `mart_daily_workshop_kpi` | - |
| `ds_plan_fact` | `fct_production_plan` | `dim_model` по `model_id`, `dim_workshop` по `workshop_id` |
| `ds_brigades` | `mart_quality_brigade_month` | `dim_brigade` по `brigade_id` |
| `ds_units` | `fct_units` | `dim_model` по `model_id`, `dim_lab` по `dyn_lab_id = lab_id`, `dim_dealer` по `dealer_id` |
| `ds_defects` | `fct_defects` | `dim_defect_type` по `defect_type_id`, `dim_model` по `model_id` |
| `ds_copq` | `mart_copq_monthly` | - |
| `ds_ws2` | `mart_welding_pilot` | - |
| `ds_cohorts` | `mart_warranty_cohorts` | - |
| `ds_downtime` | `mart_downtime_monthly` | - |

## 2. Вычисляемые поля

Добавляются в датасет (кнопка «+ Добавить поле»). Все доли считаются как отношение сумм, а не среднее долей.

```
// ds_kpi_daily
FPY                    = SUM([units_first_pass]) / SUM([units_accepted])
Выпуск, шт             = SUM([units_accepted])
Доработки, ч           = SUM([rework_hours])
Внеплановые простои, ч = SUM([unplanned_downtime_hours])
Средний цикл, ч        = SUM([total_lead_time_h_sum]) / SUM([units_accepted])
Штурмовщина            = IF [is_month_end_rush] THEN "Последние 3 раб. дня" ELSE "Остальные дни" END

// ds_plan_fact
Выполнение плана       = SUM([accepted_qty]) / SUM([planned_qty])
Выполнение плана 3М    = MSUM(SUM([accepted_qty]), 2 WITHIN [workshop_code] ORDER BY [month_start])
                       / MSUM(SUM([planned_qty]),  2 WITHIN [workshop_code] ORDER BY [month_start])
Отклонение, шт         = SUM([accepted_qty]) - SUM([planned_qty])
Статус плана           = IF [Выполнение плана] >= 0.97 THEN "✔ в плане"
                         ELSEIF [Выполнение плана] >= 0.90 THEN "▲ отставание"
                         ELSE "✖ срыв" END

// ds_brigades
Дефектность            = SUM([defect_operations]) / SUM([operations])
Доля новичков          = SUM([avg_newcomer_share] * [operations]) / SUM([operations])
Средний стаж, дн       = SUM([avg_tenure_days] * [operations]) / SUM([operations])

// ds_units
Медиана цикла, ч       = MEDIAN([total_lead_time_h])
P90 цикла, ч           = QUANTILE([total_lead_time_h], 0.9)
Утечка на 1000         = COUNT_IF([unit_id], [leaked_after_dyn]) * 1000
                       / COUNT_IF([unit_id], [dyn_lab_id] IS NOT NULL)
Стенд                  = IF [dyn_on_retired_stand] THEN [lab_code] + " (старый стенд)" ELSE [lab_code] END

// ds_copq
COPQ, млн ₽            = SUM([copq_total_rub]) / 1000000
COPQ на изделие, ₽     = SUM([copq_total_rub]) / SUM([units_accepted])
COPQ, % выручки        = SUM([copq_total_rub]) / SUM([revenue_rub])

// ds_ws2
Дефектность сварки     = SUM([defect_operations]) / SUM([operations])
Группа                 = IF [ws2_group] = "pilot" THEN "Пилот WS-2" ELSE "Контроль" END
Период                 = IF [is_post_period] THEN "После 01.09.2025" ELSE "До старта" END
Время к нормативу      = SUM([avg_duration_to_std] * [operations]) / SUM([operations])
```

## 3. Чарты

| № | Чарт | Тип | Поля |
|---|---|---|---|
| 1 | KPI месяца | Индикатор ×4 | `Выпуск, шт`, `FPY`, `Выполнение плана`, `COPQ, % выручки` |
| 2 | План-факт по цехам | Линейная | X: `month_start` (месяц), Y: `Выполнение плана 3М`, цвета: `workshop_code` |
| 3 | Выпуск по месяцам | Столбчатая | X: `month_start`, Y: `Выпуск, шт`, цвета: `workshop_code` |
| 4 | Дефектность бригад | Сводная таблица | строки: `brigade_full_name`, столбцы: `month_start`, мера `Дефектность` с цветовой заливкой (градиент одного оттенка) |
| 5 | Новички и брак | Точечная | X: `Доля новичков`, Y: `Дефектность`, точки: `brigade_name` × `month_start`, размер: `operations` |
| 6 | Штурмовщина | Столбчатая | X: `Штурмовщина`, Y: `Выпуск, шт` / `FPY` (два отдельных чарта, не две оси) |
| 7 | COPQ по месяцам | Столбчатая с накоплением | X: `month_start`, Y: `line_rework_cost_rub`, `test_rework_cost_rub`, `warranty_cost_rub` |
| 8 | Пилот WS-2 | Линейная | X: `month_start`, Y: `Дефектность сварки`, цвета: `Группа` |
| 9 | Пилот WS-2: до/после | Таблица | строки: `Группа`, столбцы: `Период`, мера: `Дефектность сварки`, `Время к нормативу` |
| 10 | Гарантийные когорты | Сводная таблица | строки: `cohort`, столбцы: `month_in_service`, мера: `MAX([cumulative_claim_rate])`, фильтр `product_group` |
| 11 | Утечка после стенда | Столбчатая горизонтальная | Y: `Стенд`, X: `Утечка на 1000`, фильтр: `product_group = "Тяжёлая техника"` |
| 12 | Простои | Столбчатая | X: `month_start`, Y: `SUM([downtime_hours])`, цвета: `reason_name`, фильтр `is_planned = false` |

## 4. Дашборд

Вкладки: **Обзор** (1-3, 6) · **Качество** (4, 5, 7) · **Пилот WS-2** (8, 9 + текст с выводом) · **Гарантия** (10, 11) · **Простои** (12).

Селекторы в одну строку над чартами: период (`month_start`, диапазон), цех (`workshop_code`), группа продукции (`product_group`). Связи селекторов с датасетами - через одноимённые поля (в DataLens: «Связи» → алиасы полей между датасетами).

Правила оформления: одна ось на чарт; цвет цеха одинаковый на всех вкладках (палитра → ручное назначение цветов: ЦЛА `#2a78d6`, ЦГА `#eb6834`, ЦСТ `#1baf7a`, ЦМТ `#eda100`); статус плана - символом и текстом, не только цветом.
