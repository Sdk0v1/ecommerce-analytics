-- =====================================================================
-- 01_analytics_views.sql
-- Мета    : єдине місце для всіх бізнес-визначень. Кожен файл аналізу,
--           валідація в Python і Power BI читають ці view, тому
--           цифри всюди узгоджені.
-- Нотатки : P1 - Definitions, P1 - Data Quality Report
-- Запуск  : psql -d olist -f SQL/01_analytics_views.sql   (після 00)
--
-- ВИЗНАЧЕННЯ (ухвалені в P1 - Definitions)
--   Замовлення   = замовлення з order_status = 'delivered'
--                  (96,478 з 99,441 замовлень; скасовані/недоступні/в дорозі виключено)
--   Виручка      = SUM(price + freight_value) з order_items
--                  (що клієнт заплатив за товари + доставку; існує на рівні
--                   товару, тож виручка за категоріями сумується до загальної виручки)
--   AOV          = Виручка / COUNT(DISTINCT order_id)
--   Клієнт       = customer_unique_id (customer_id створюється для кожного замовлення)
--   Місяць       = DATE_TRUNC('month', order_purchase_timestamp)
--   Період KPI   = 2017-01 .. 2018-08 (повні місяці; у 2016 є 3 розріджені
--                  місяці з пропуском, у 2018-09/10 < 20 замовлень)
--   Дні доставки = (delivered_customer_date - purchase_timestamp) у дробових днях
--   Запізнення   = delivered_customer_date::date > estimated_delivery_date::date
--                  (очікувана дата завжди має час 00:00 -> порівнюємо на рівні DATE;
--                   доставлено в обіцяний день = вчасно)
--   Оцінка       = останній відгук до замовлення (за часом відповіді) - 547 замовлень
--                  мають більше ніж один відгук
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS analytics;

DROP VIEW IF EXISTS analytics.item_base CASCADE;
DROP VIEW IF EXISTS analytics.order_base CASCADE;

-- ---------------------------------------------------------------------
-- order_base : один рядок = одне доставлене замовлення
-- ---------------------------------------------------------------------
CREATE VIEW analytics.order_base AS
WITH items AS (                        -- order_items, агреговані до рівня замовлення
    SELECT order_id,
           COUNT(*)                     AS n_items,
           COUNT(DISTINCT seller_id)    AS n_sellers,
           SUM(price)                   AS product_value,
           SUM(freight_value)           AS freight_value,
           SUM(price + freight_value)   AS revenue
    FROM raw.order_items
    GROUP BY order_id
), pays AS (                           -- payments, агреговані до рівня замовлення
    SELECT order_id,
           SUM(payment_value)           AS paid_value,
           -- основний спосіб оплати = рядок із найбільшою сумою
           (ARRAY_AGG(payment_type ORDER BY payment_value DESC, payment_sequential))[1] AS main_payment_type
    FROM raw.payments
    GROUP BY order_id
), last_review AS (                    -- один відгук на замовлення: найостанніший
    SELECT order_id, review_score, review_creation_date
    FROM (
        SELECT r.*,
               ROW_NUMBER() OVER (PARTITION BY order_id
                                  ORDER BY review_answer_timestamp DESC,
                                           review_creation_date DESC,
                                           review_id) AS rn
        FROM raw.reviews r
    ) t
    WHERE rn = 1
)
SELECT
    o.order_id,
    c.customer_unique_id,
    o.customer_id,
    c.customer_state,
    o.order_purchase_timestamp                                   AS purchase_ts,
    o.order_purchase_timestamp::date                             AS purchase_date,
    DATE_TRUNC('month', o.order_purchase_timestamp)::date        AS purchase_month,
    (o.order_purchase_timestamp >= DATE '2017-01-01'
     AND o.order_purchase_timestamp <  DATE '2018-09-01')        AS in_kpi_period,
    i.n_items,
    i.n_sellers,
    i.product_value,
    i.freight_value,
    i.revenue,
    p.paid_value,
    p.main_payment_type,
    o.order_delivered_carrier_date                               AS delivered_carrier_ts,
    o.order_delivered_customer_date                              AS delivered_customer_ts,
    o.order_estimated_delivery_date::date                        AS estimated_delivery_date,
    (o.order_delivered_customer_date IS NOT NULL)                AS has_delivery_date,
    EXTRACT(EPOCH FROM (o.order_delivered_customer_date - o.order_purchase_timestamp)) / 86400.0
                                                                 AS delivery_days,
    EXTRACT(EPOCH FROM (o.order_estimated_delivery_date - o.order_purchase_timestamp)) / 86400.0
                                                                 AS estimated_days,
    (o.order_delivered_customer_date::date - o.order_estimated_delivery_date::date)
                                                                 AS delay_days,      -- цілі дні, >0 = запізнення
    CASE WHEN o.order_delivered_customer_date IS NULL THEN NULL
         WHEN o.order_delivered_customer_date::date > o.order_estimated_delivery_date::date THEN 1
         ELSE 0 END                                              AS is_late,
    r.review_score,
    r.review_creation_date,
    -- відгук написано до фактичного отримання замовлення (див. P3 cleaning A8)
    (r.review_creation_date < o.order_delivered_customer_date::date) AS review_before_delivery
FROM raw.orders o
JOIN raw.customers c   ON c.customer_id = o.customer_id
JOIN items i           ON i.order_id    = o.order_id
LEFT JOIN pays p       ON p.order_id    = o.order_id
LEFT JOIN last_review r ON r.order_id   = o.order_id
WHERE o.order_status = 'delivered';

-- ---------------------------------------------------------------------
-- item_base : один рядок = один товар доставленого замовлення, з категорією
-- ---------------------------------------------------------------------
CREATE VIEW analytics.item_base AS
SELECT
    i.order_id,
    i.order_item_id,
    i.product_id,
    i.seller_id,
    COALESCE(t.product_category_name_english,     -- англійська назва
             p.product_category_name,             -- без перекладу (2 категорії)
             'unknown')                                  AS category,
    i.price,
    i.freight_value,
    i.price + i.freight_value                            AS item_revenue,
    ob.customer_unique_id,
    ob.customer_state,
    ob.purchase_month,
    ob.in_kpi_period
FROM raw.order_items i
JOIN analytics.order_base ob          ON ob.order_id = i.order_id
LEFT JOIN raw.products p              ON p.product_id = i.product_id
LEFT JOIN raw.category_translation t  ON t.product_category_name = p.product_category_name;

-- ---------------------------------------------------------------------
-- Перевірки на адекватність
-- ---------------------------------------------------------------------
-- 1. чи має order_base один рядок на доставлене замовлення і жодного fan-out?
SELECT COUNT(*) AS rows, COUNT(DISTINCT order_id) AS orders FROM analytics.order_base;

-- 2. чи сумується виручка товарів до виручки замовлень (аналіз категорій узгоджений)?
SELECT (SELECT SUM(revenue)      FROM analytics.order_base) AS order_revenue,
       (SELECT SUM(item_revenue) FROM analytics.item_base)  AS item_revenue;

-- 3. скільки рядків виключено з кожного аналізу? (P1 - Data Quality Report)
SELECT
    (SELECT COUNT(*) FROM raw.orders)                                       AS all_orders,
    (SELECT COUNT(*) FROM raw.orders WHERE order_status <> 'delivered')     AS excluded_not_delivered,
    COUNT(*)                                                                AS delivered_orders,
    COUNT(*) FILTER (WHERE NOT in_kpi_period)                               AS delivered_outside_kpi_period,
    COUNT(*) FILTER (WHERE NOT has_delivery_date)                           AS delivered_without_delivery_date,
    COUNT(*) FILTER (WHERE review_score IS NULL)                            AS delivered_without_review,
    COUNT(*) FILTER (WHERE review_before_delivery)                          AS review_before_delivery
FROM analytics.order_base;
