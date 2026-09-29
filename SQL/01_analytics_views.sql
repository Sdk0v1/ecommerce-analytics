-- =====================================================================
-- 01_analytics_views.sql
-- Purpose : one place for all business definitions. Every analysis file,
--           the Python validation and Power BI read these views, so the
--           numbers are consistent everywhere.
-- Notes   : P1 - Definitions, P1 - Data Quality Report
-- Run     : psql -d olist -f SQL/01_analytics_views.sql   (after 00)
--
-- DEFINITIONS (decided in P1 - Definitions)
--   Order        = order with order_status = 'delivered'
--                  (96,478 of 99,441 orders; canceled/unavailable/in-transit excluded)
--   Revenue      = SUM(price + freight_value) from order_items
--                  (what the customer paid for goods + shipping; exists at item
--                   level, so revenue by category adds up to total revenue)
--   AOV          = Revenue / COUNT(DISTINCT order_id)
--   Customer     = customer_unique_id (customer_id is created per order)
--   Month        = DATE_TRUNC('month', order_purchase_timestamp)
--   KPI period   = 2017-01 .. 2018-08 (complete months; 2016 has 3 sparse
--                  months with a gap, 2018-09/10 have < 20 orders)
--   Delivery days= (delivered_customer_date - purchase_timestamp) in fractional days
--   Late         = delivered_customer_date::date > estimated_delivery_date::date
--                  (estimated date always has time 00:00 -> compare on DATE level;
--                   delivered on the promised day = on time)
--   Review score = latest review of the order (by answer timestamp) - 547 orders
--                  have more than one review
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS analytics;

DROP VIEW IF EXISTS analytics.item_base CASCADE;
DROP VIEW IF EXISTS analytics.order_base CASCADE;

-- ---------------------------------------------------------------------
-- order_base : one row = one delivered order
-- ---------------------------------------------------------------------
CREATE VIEW analytics.order_base AS
WITH items AS (                        -- order_items aggregated to order level
    SELECT order_id,
           COUNT(*)                     AS n_items,
           COUNT(DISTINCT seller_id)    AS n_sellers,
           SUM(price)                   AS product_value,
           SUM(freight_value)           AS freight_value,
           SUM(price + freight_value)   AS revenue
    FROM raw.order_items
    GROUP BY order_id
), pays AS (                           -- payments aggregated to order level
    SELECT order_id,
           SUM(payment_value)           AS paid_value,
           -- main payment method = the row with the largest value
           (ARRAY_AGG(payment_type ORDER BY payment_value DESC, payment_sequential))[1] AS main_payment_type
    FROM raw.payments
    GROUP BY order_id
), last_review AS (                    -- one review per order: the latest one
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
                                                                 AS delay_days,      -- whole days, >0 = late
    CASE WHEN o.order_delivered_customer_date IS NULL THEN NULL
         WHEN o.order_delivered_customer_date::date > o.order_estimated_delivery_date::date THEN 1
         ELSE 0 END                                              AS is_late,
    r.review_score,
    r.review_creation_date,
    -- review written before the order actually arrived (see P3 cleaning A8)
    (r.review_creation_date < o.order_delivered_customer_date::date) AS review_before_delivery
FROM raw.orders o
JOIN raw.customers c   ON c.customer_id = o.customer_id
JOIN items i           ON i.order_id    = o.order_id
LEFT JOIN pays p       ON p.order_id    = o.order_id
LEFT JOIN last_review r ON r.order_id   = o.order_id
WHERE o.order_status = 'delivered';

-- ---------------------------------------------------------------------
-- item_base : one row = one item of a delivered order, with category
-- ---------------------------------------------------------------------
CREATE VIEW analytics.item_base AS
SELECT
    i.order_id,
    i.order_item_id,
    i.product_id,
    i.seller_id,
    COALESCE(t.product_category_name_english,     -- English name
             p.product_category_name,             -- untranslated (2 categories)
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
-- Sanity checks
-- ---------------------------------------------------------------------
-- 1. order_base has one row per delivered order and no fan-out
SELECT COUNT(*) AS rows, COUNT(DISTINCT order_id) AS orders FROM analytics.order_base;

-- 2. item revenue adds up to order revenue (category analysis is consistent)
SELECT (SELECT SUM(revenue)      FROM analytics.order_base) AS order_revenue,
       (SELECT SUM(item_revenue) FROM analytics.item_base)  AS item_revenue;

-- 3. rows excluded from each analysis (P1 - Data Quality Report)
SELECT
    (SELECT COUNT(*) FROM raw.orders)                                       AS all_orders,
    (SELECT COUNT(*) FROM raw.orders WHERE order_status <> 'delivered')     AS excluded_not_delivered,
    COUNT(*)                                                                AS delivered_orders,
    COUNT(*) FILTER (WHERE NOT in_kpi_period)                               AS delivered_outside_kpi_period,
    COUNT(*) FILTER (WHERE NOT has_delivery_date)                           AS delivered_without_delivery_date,
    COUNT(*) FILTER (WHERE review_score IS NULL)                            AS delivered_without_review,
    COUNT(*) FILTER (WHERE review_before_delivery)                          AS review_before_delivery
FROM analytics.order_base;
