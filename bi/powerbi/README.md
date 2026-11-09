# Power BI: дашборд «Производство и качество»

Сборка отчёта занимает 1.5-2 часа. Все меры и запросы уже написаны - остаётся собрать модель и визуалы по макету ниже.

| Файл | Что внутри |
|---|---|
| `power_query.pq` | загрузка витрин: из PostgreSQL (вариант A) или из CSV `bi/exports` (вариант B) |
| `measures.dax` | ~35 мер: выпуск, план-факт, FPY, COPQ, DiD пилота, утечка после стенда, простои |
| `theme.json` | тема: палитра, шрифты, фон (Вид → Темы → Обзор тем) |

## 1. Загрузка данных

**Вариант A (рекомендуется):** база поднята (`make db-up && make pipeline`) → Получить данные → PostgreSQL → `localhost:5432`, база `plant`, схема `marts`. Режим - Import.

**Вариант B:** без PostgreSQL. Создайте параметр `CsvFolder` = полный путь к папке `bi\exports`, функцию `fnLoadCsv` из `power_query.pq` и по запросу на каждую таблицу: `= fnLoadCsv("fct_units")`. Функция типизирует колонки в культуре en-US, иначе русская локаль Windows прочитает `1.5` как текст.

Загружаемые таблицы:
- измерения: `dim_date`, `dim_workshop`, `dim_model`, `dim_section`, `dim_brigade`, `dim_lab`, `dim_dealer`, `dim_defect_type`;
- факты: `fct_units`, `fct_defects`, `fct_warranty_claims`, `fct_production_plan`;
- витрины: `mart_daily_workshop_kpi`, `mart_quality_brigade_month`, `mart_welding_pilot`, `mart_warranty_cohorts`, `mart_downtime_monthly`, `mart_copq_monthly`.

## 2. Модель данных (звезда)

Все связи «один ко многим», фильтрация в одну сторону. `dim_date` пометить как таблицу дат (поле `date_day`).

| Из (1) | В (*) | Активна |
|---|---|---|
| `dim_date[date_day]` | `fct_units[accepted_date]` | да |
| `dim_date[date_day]` | `fct_units[start_date]`, `fct_units[shipped_date]` | нет (через `USERELATIONSHIP` в мерах) |
| `dim_date[date_day]` | `fct_defects[detected_date]`, `fct_warranty_claims[claim_date]`, `mart_daily_workshop_kpi[date_day]` | да |
| `dim_date[date_day]` | `[month_start]` в `fct_production_plan`, `mart_quality_brigade_month`, `mart_welding_pilot`, `mart_downtime_monthly`, `mart_copq_monthly` | да |
| `dim_workshop[workshop_id]` | `workshop_id` во всех фактах и витринах | да |
| `dim_model[model_id]` | `fct_units`, `fct_defects`, `fct_warranty_claims`, `fct_production_plan` | да |
| `dim_section[section_id]` | `mart_welding_pilot`, `mart_downtime_monthly` | да |
| `dim_brigade[brigade_id]` | `mart_quality_brigade_month` | да |
| `dim_defect_type[defect_type_id]` | `fct_defects`, `fct_warranty_claims` | да |
| `dim_dealer[dealer_id]` | `fct_units`, `fct_warranty_claims` | да |
| `dim_lab[lab_id]` | `fct_units[dyn_lab_id]` | да |

Скрыть в представлении отчёта все ключи `*_id` фактов; сортировать `dim_date[month_name]` по `month`.

## 3. Страницы отчёта

Слева на каждой странице - срезы: **период** (`dim_date[date_day]`, диапазон), **цех** (`dim_workshop[workshop_code]`), **группа продукции** (`dim_model[product_group]`). Синхронизировать срезы между страницами (Вид → Синхронизация срезов).

**1. Обзор (для директора по производству)**
- Карточки: `Принято шт`, `Выручка ₽`, `FPY %`, `Выполнение плана %` (+ `Статус плана` подписью), `COPQ % выручки`.
- Линия: ось - `dim_date[month_start]`, значения - `Выполнение плана 3М %`, легенда - `workshop_code`. Константная линия 100%.
- Линия: `FPY 3М скользящий %` по месяцам и цехам.
- Таблица по цехам: принято, FPY, медиана и P90 цикла, COPQ на изделие; условное форматирование `FPY %` иконками.

**2. Качество и бригады (для начальников цехов и ОТК)**
- Матрица «бригада × месяц»: строки `dim_brigade[brigade_full_name]`, столбцы `month_start`, значения `Дефектность операций %` с фоновой цветовой шкалой (один оттенок, светлый → тёмный). Отсортировать по последнему месяцу.
- Точечная диаграмма: X - `Доля новичков в бригаде %`, Y - `Дефектность операций %`, детализация - бригада × месяц, размер - `Операций (бригады)`. Линия тренда.
- Столбцы Парето: `defect_name` по `COPQ ₽`, сортировка по убыванию + таблица с накопленной долей (без второй оси).
- Карточка `Доля дефектов, пропущенных линией %`.

**3. Стоимость качества**
- Столбцы с накоплением по месяцам: `Доработки ₽` (линия и испытания из `mart_copq_monthly`) и `Гарантия ₽`.
- Таблица по цехам: `COPQ ₽`, `COPQ на изделие ₽`, `COPQ % выручки`.

**4. Пилот WS-2 (для главного технолога)**
- Линия: `Дефектность сварки %` по месяцам, легенда `ws2_group`; вертикальная линия на 01.09.2025 (константа оси X).
- Карточки: `DiD относительный %` с подписью «оценка эффекта стандарта», `Время сварки к нормативу` для пилота после старта.
- Текстовый блок с выводом из ноутбука 03 (эффект реальный, экономически не окупается в текущем виде).

**5. Гарантия и испытания**
- Матрица когорт: строки `mart_warranty_cohorts[cohort]`, столбцы `month_in_service`, значения `Накопленная доля гарантийных случаев %`, фильтр `product_group`; цветовая шкала.
- Столбцы: `Утечка после стенда на 1000` по `dim_lab[lab_code]` и `fct_units[dyn_on_retired_stand]`, фильтр «тяжёлая техника».
- Таблица заявок по `dim_defect_type[defect_name]` и `dim_dealer[region]`.

**6. Простои**
- Столбцы: `Внеплановые простои ч` по месяцам и участкам (топ-5 участков по фильтру Top N).
- Таблица: причины (`reason_name`), события, часы, максимальная длительность.

## 4. Оформление

- Тема `theme.json`; одна ось на графике (никаких двух шкал - вторую меру выносим в отдельный визуал).
- Цвет закреплён за сущностью: цех всегда одного цвета на всех страницах (Формат → Цвета данных).
- Статус плана показывается иконкой и подписью, а не только цветом.
- Подсказки (tooltips): на линиях план-факта - план, факт, отклонение в штуках.

После сборки сохраните `.pbix` в эту папку и добавьте скриншоты страниц в `reports/figures/powerbi_*.png` - они пойдут в README проекта.
