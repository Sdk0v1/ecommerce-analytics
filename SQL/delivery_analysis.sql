-- =====================================================================
-- delivery_analysis.sql
-- Мета    : час доставки, % вчасних доставок, медіана / p90, найгірші штати, тренд
-- Відповідає на : D1, D2, D3, D4 (D5 -> Python/statistical_analysis.py)
-- Нотатки : P2 - Аналіз доставки
-- Джерело : analytics.order_base
--   Сукупність        = доставлені замовлення, куплені 2017-01 .. 2018-08, З
--                       датою доставки клієнту (у 8 доставлених замовлень її немає)
--   Дні доставки      = (delivered_customer_ts - purchase_ts) у дробових днях
--   Обіцяні дні       = (estimated_delivery_date - purchase_ts) у дробових днях
--   Дні затримки      = дата доставки - очікувана дата (цілі дні, > 0 = запізнення)
--   Запізнення        = ДАТА доставки > очікувана ДАТА
--   Штат              = customer_state (де клієнт відчуває затримку)
-- Мінімальний розмір вибірки для порівняння штатів: 300 замовлень
-- =====================================================================

DROP VIEW IF EXISTS analytics.delivery_orders;
CREATE VIEW analytics.delivery_orders AS
SELECT order_id, customer_unique_id, customer_state, purchase_month,
       delivery_days, estimated_days, delay_days, is_late,
       review_score, review_before_delivery,
       EXTRACT(EPOCH FROM (delivered_customer_ts - delivered_carrier_ts)) / 86400.0 AS carrier_days
FROM analytics.order_base
WHERE in_kpi_period
  AND has_delivery_date;

-- ---------------------------------------------------------------------
-- D1 + D3 + D4: загалом
-- ---------------------------------------------------------------------
SELECT COUNT(*)                                                                             AS delivered_orders,
       ROUND(100.0 * AVG(1 - is_late), 2)                                                   AS on_time_pct,
       ROUND(100.0 * AVG(is_late), 2)                                                       AS late_pct,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY delivery_days)::numeric, 2)        AS median_delivery_days,
       ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY delivery_days)::numeric, 2)        AS p90_delivery_days,
       ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY delivery_days)::numeric, 2)       AS p99_delivery_days,
       ROUND(AVG(delivery_days)::numeric, 2)                                                AS mean_delivery_days,
       ROUND(MAX(delivery_days)::numeric, 2)                                                AS max_delivery_days,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY estimated_days)::numeric, 2)       AS median_promised_days,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY estimated_days - delivery_days)::numeric, 2)
                                                                                            AS median_days_early   -- обіцяні мінус фактичні
FROM analytics.delivery_orders;

-- A6: серед замовлень ІЗ ЗАПІЗНЕННЯМ - наскільки запізно?
SELECT COUNT(*)                                                                  AS late_orders,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY delay_days)                   AS median_delay_days,
       PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY delay_days)                   AS p90_delay_days,
       ROUND(100.0 * COUNT(*) FILTER (WHERE delay_days <= 3) / COUNT(*), 1)     AS pct_late_by_1_to_3_days
FROM analytics.delivery_orders
WHERE is_late = 1;

-- Розподіл затримок (для перевірки «доза-відповідь» у статистиці)
SELECT CASE WHEN delay_days <= -10 THEN '1: 10+ days early'
            WHEN delay_days <= -1  THEN '2: 1-9 days early'
            WHEN delay_days =  0   THEN '3: on the promised day'
            WHEN delay_days <= 3   THEN '4: 1-3 days late'
            WHEN delay_days <= 7   THEN '5: 4-7 days late'
            ELSE                        '6: 8+ days late' END   AS delay_bucket,
       COUNT(*)                                                  AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)        AS pct_orders
FROM analytics.delivery_orders
GROUP BY 1
ORDER BY 1;

-- ---------------------------------------------------------------------
-- D2: за штатом клієнта, з рангами (найгірший = 1) і порівнянням із країною загалом
-- ---------------------------------------------------------------------
WITH st AS (
    SELECT customer_state,
           COUNT(*)                                                           AS orders,
           AVG(is_late)                                                       AS late_rate,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY delivery_days)         AS median_days,
           PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY delivery_days)         AS p90_days,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY estimated_days)        AS median_promised_days
    FROM analytics.delivery_orders
    GROUP BY customer_state
), nat AS (
    SELECT AVG(is_late) AS late_rate,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY delivery_days) AS median_days
    FROM analytics.delivery_orders
)
SELECT st.customer_state,
       st.orders,
       (st.orders >= 300)                                                        AS meets_min_n,
       ROUND(100.0 * st.late_rate, 2)                                            AS late_pct,
       ROUND(100.0 * (st.late_rate - nat.late_rate), 2)                          AS late_pct_vs_national_pp,
       ROUND(st.median_days::numeric, 1)                                         AS median_delivery_days,
       ROUND(st.p90_days::numeric, 1)                                            AS p90_delivery_days,
       ROUND(st.median_promised_days::numeric, 1)                                AS median_promised_days,
       RANK() OVER (ORDER BY st.late_rate DESC)                                  AS rank_late_pct,
       RANK() OVER (ORDER BY st.median_days DESC)                                AS rank_median_days
FROM st CROSS JOIN nat
ORDER BY st.late_rate DESC;

-- 5 найгірших штатів за % запізнень серед штатів із >= 300 замовленнями
WITH st AS (
    SELECT customer_state, COUNT(*) AS orders, AVG(is_late) AS late_rate,
           PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY delivery_days) AS p90_days
    FROM analytics.delivery_orders
    GROUP BY customer_state
    HAVING COUNT(*) >= 300
)
SELECT RANK() OVER (ORDER BY late_rate DESC) AS rank_late,
       customer_state, orders,
       ROUND(100.0 * late_rate, 2) AS late_pct,
       ROUND(p90_days::numeric, 1)  AS p90_delivery_days
FROM st
ORDER BY late_rate DESC
LIMIT 5;

-- ---------------------------------------------------------------------
-- У динаміці: % вчасних доставок і медіана днів доставки за місяцем покупки
-- УВАГА: дані закінчуються 2018-10. Замовлення останніх місяців, які ще були
-- в дорозі, ще не мають статусу delivered, тож їх тут немає - найповільніші
-- замовлення останніх місяців недопредставлені, і нещодавній час доставки
-- виглядає кращим, ніж буде насправді. Порівнюйте останні місяці обережно.
-- ---------------------------------------------------------------------
SELECT purchase_month,
       COUNT(*)                                                                         AS delivered_orders,
       ROUND(100.0 * AVG(1 - is_late), 2)                                               AS on_time_pct,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY delivery_days)::numeric, 1)    AS median_delivery_days,
       ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY delivery_days)::numeric, 1)    AS p90_delivery_days,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY estimated_days)::numeric, 1)   AS median_promised_days
FROM analytics.delivery_orders
GROUP BY purchase_month
ORDER BY purchase_month;

-- ---------------------------------------------------------------------
-- Попередній огляд D5 (повна статистика в Python): оцінка відгуку за статусом доставки
-- ---------------------------------------------------------------------
SELECT CASE is_late WHEN 1 THEN 'late' ELSE 'on time' END           AS delivery_status,
       COUNT(review_score)                                           AS reviews,
       ROUND(AVG(review_score), 3)                                   AS mean_score,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY review_score)     AS median_score,
       ROUND(100.0 * AVG((review_score <= 2)::int), 2)               AS pct_1_2_stars,
       ROUND(100.0 * AVG((review_score = 5)::int), 2)                AS pct_5_stars
FROM analytics.delivery_orders
WHERE review_score IS NOT NULL
GROUP BY 1;

-- ---------------------------------------------------------------------
-- Експорт для Python (запускати в psql з кореня репозиторію):
-- \copy (SELECT * FROM analytics.delivery_orders) TO 'reports/tables/delivery_orders.csv' WITH (FORMAT csv, HEADER true)
-- ---------------------------------------------------------------------
