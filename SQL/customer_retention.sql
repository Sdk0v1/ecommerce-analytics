-- =====================================================================
-- customer_retention.sql
-- Purpose : one-time vs repeat customers, time to return, repeat rate
--           over time and by segment
-- Answers : C1, C2, C3, C4  ·  Notes: P2 - Repeat Purchase
-- Source  : analytics.order_base, analytics.item_base
--   Customer        = customer_unique_id  (NOT customer_id - one per order)
--   Order           = delivered order (whole history 2016-09 .. 2018-08)
--   Repeat customer = customer with >= 2 delivered orders
--   Strict repeat   = customer with orders on >= 2 different purchase DATES
--                     (same-day "repeats" are often one basket split in two)
--   Repeat rate     = repeat customers / all customers
-- Last purchase date in the data: 2018-08-29 -> reference for censoring
-- =====================================================================

-- ---------------------------------------------------------------------
-- C1/C2.1: headline numbers
-- ---------------------------------------------------------------------
WITH per_customer AS (
    SELECT customer_unique_id,
           COUNT(DISTINCT order_id)      AS orders,
           COUNT(DISTINCT purchase_date) AS purchase_days,
           SUM(revenue)                  AS revenue
    FROM analytics.order_base
    GROUP BY customer_unique_id
)
SELECT COUNT(*)                                              AS total_customers,
       COUNT(*) FILTER (WHERE orders = 1)                    AS one_time_customers,
       COUNT(*) FILTER (WHERE orders >= 2)                   AS repeat_customers,
       ROUND(100.0 * COUNT(*) FILTER (WHERE orders >= 2) / COUNT(*), 2)        AS repeat_rate_pct,
       COUNT(*) FILTER (WHERE purchase_days >= 2)                              AS strict_repeat_customers,
       ROUND(100.0 * COUNT(*) FILTER (WHERE purchase_days >= 2) / COUNT(*), 2) AS strict_repeat_rate_pct,
       ROUND(100.0 * COUNT(*) FILTER (WHERE orders = 1) / COUNT(*), 2)         AS one_time_pct
FROM per_customer;

-- C1/C2.2: distribution of orders per customer
WITH per_customer AS (
    SELECT customer_unique_id, COUNT(DISTINCT order_id) AS orders
    FROM analytics.order_base
    GROUP BY customer_unique_id
)
SELECT CASE WHEN orders >= 4 THEN '4+' ELSE orders::text END AS orders_per_customer,
       COUNT(*)                                               AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)     AS pct_customers
FROM per_customer
GROUP BY 1
ORDER BY 1;

-- C1/C2.3: share of orders and revenue coming from repeat customers
WITH per_customer AS (
    SELECT customer_unique_id, COUNT(DISTINCT order_id) AS orders
    FROM analytics.order_base
    GROUP BY customer_unique_id
)
SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE pc.orders >= 2) / COUNT(*), 2)                  AS pct_orders_from_repeat,
       ROUND(100.0 * SUM(ob.revenue) FILTER (WHERE pc.orders >= 2) / SUM(ob.revenue), 2)    AS pct_revenue_from_repeat
FROM analytics.order_base ob
JOIN per_customer pc USING (customer_unique_id);

-- ---------------------------------------------------------------------
-- C3.1 + C3.2: time between 1st and 2nd order
-- ROW_NUMBER orders each customer's purchases; LEAD gives the next one.
-- ---------------------------------------------------------------------
WITH ordered AS (
    SELECT customer_unique_id, order_id, purchase_ts,
           ROW_NUMBER() OVER (PARTITION BY customer_unique_id ORDER BY purchase_ts, order_id) AS n,
           LEAD(purchase_ts) OVER (PARTITION BY customer_unique_id ORDER BY purchase_ts, order_id) AS next_ts
    FROM analytics.order_base
), second AS (
    SELECT customer_unique_id,
           EXTRACT(EPOCH FROM (next_ts - purchase_ts)) / 86400.0 AS days_to_second
    FROM ordered
    WHERE n = 1 AND next_ts IS NOT NULL
)
SELECT COUNT(*)                                                                              AS customers_with_2nd_order,
       ROUND(PERCENTILE_CONT(0.5)  WITHIN GROUP (ORDER BY days_to_second)::numeric, 1)       AS median_days,
       ROUND(PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY days_to_second)::numeric, 1)       AS p75_days,
       ROUND(PERCENTILE_CONT(0.9)  WITHIN GROUP (ORDER BY days_to_second)::numeric, 1)       AS p90_days,
       COUNT(*) FILTER (WHERE days_to_second < 1)                                            AS within_1_day,
       ROUND(100.0 * COUNT(*) FILTER (WHERE days_to_second < 1)   / COUNT(*), 1)             AS pct_within_1_day,
       ROUND(100.0 * COUNT(*) FILTER (WHERE days_to_second <= 30)  / COUNT(*), 1)            AS pct_within_30_days,
       ROUND(100.0 * COUNT(*) FILTER (WHERE days_to_second <= 90)  / COUNT(*), 1)            AS pct_within_90_days,
       ROUND(100.0 * COUNT(*) FILTER (WHERE days_to_second <= 180) / COUNT(*), 1)            AS pct_within_180_days
FROM second;

-- Same statistics for STRICT repeats (2nd order on a later date)
WITH days AS (
    SELECT DISTINCT customer_unique_id, purchase_date FROM analytics.order_base
), ordered AS (
    SELECT customer_unique_id, purchase_date,
           ROW_NUMBER() OVER (PARTITION BY customer_unique_id ORDER BY purchase_date) AS n,
           LEAD(purchase_date) OVER (PARTITION BY customer_unique_id ORDER BY purchase_date) AS next_date
    FROM days
), second AS (
    SELECT next_date - purchase_date AS days_to_second
    FROM ordered WHERE n = 1 AND next_date IS NOT NULL
)
SELECT COUNT(*)                                                                         AS strict_repeat_customers,
       PERCENTILE_CONT(0.5)  WITHIN GROUP (ORDER BY days_to_second)                     AS median_days,
       PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY days_to_second)                     AS p75_days,
       PERCENTILE_CONT(0.9)  WITHIN GROUP (ORDER BY days_to_second)                     AS p90_days,
       ROUND(100.0 * COUNT(*) FILTER (WHERE days_to_second <= 30)  / COUNT(*), 1)       AS pct_within_30_days,
       ROUND(100.0 * COUNT(*) FILTER (WHERE days_to_second <= 90)  / COUNT(*), 1)       AS pct_within_90_days
FROM second;

-- ---------------------------------------------------------------------
-- C1.4: repeat rate over time with a FIXED 90-day window
-- A customer "returned" if they placed another order on a later date within
-- 90 days of the first order. Only first-purchase months whose customers all
-- had 90 days of observation (first order <= 2018-08-29 - 90 days) are shown
-- -> avoids right-censoring.
-- ---------------------------------------------------------------------
WITH first_order AS (
    SELECT customer_unique_id, MIN(purchase_ts) AS first_ts
    FROM analytics.order_base
    GROUP BY customer_unique_id
), returned AS (
    SELECT f.customer_unique_id,
           DATE_TRUNC('month', f.first_ts)::date AS first_month,
           BOOL_OR(ob.purchase_date > f.first_ts::date
                   AND ob.purchase_ts <= f.first_ts + INTERVAL '90 days') AS returned_90d
    FROM first_order f
    JOIN analytics.order_base ob USING (customer_unique_id)
    GROUP BY f.customer_unique_id, f.first_ts
)
SELECT first_month,
       COUNT(*)                                                   AS new_customers,
       COUNT(*) FILTER (WHERE returned_90d)                       AS returned_within_90d,
       ROUND(100.0 * COUNT(*) FILTER (WHERE returned_90d) / COUNT(*), 2) AS repeat_rate_90d_pct
FROM returned
WHERE first_month BETWEEN DATE '2017-01-01' AND DATE '2018-05-01'   -- 2018-05 is the last month with full 90 days
GROUP BY first_month
ORDER BY first_month;

-- ---------------------------------------------------------------------
-- C4.1: repeat rate by segment known AT THE FIRST ORDER
-- Outcome: customer placed any later order (strict repeat, whole history).
-- Customers who first bought after 2018-05-31 are excluded (< 90 days to return).
-- Groups with fewer than 300 customers are flagged.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS tmp_first_order;
CREATE TEMP TABLE tmp_first_order AS
WITH ranked AS (
    SELECT ob.*,
           ROW_NUMBER() OVER (PARTITION BY customer_unique_id ORDER BY purchase_ts, order_id) AS n
    FROM analytics.order_base ob
), first_cat AS (          -- category with the largest revenue in the first order
    SELECT order_id, category
    FROM (
        SELECT order_id, category,
               ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY SUM(item_revenue) DESC, category) AS rn
        FROM analytics.item_base
        GROUP BY order_id, category
    ) t
    WHERE rn = 1
), later AS (
    SELECT customer_unique_id, COUNT(DISTINCT purchase_date) > 1 AS is_repeat
    FROM analytics.order_base
    GROUP BY customer_unique_id
)
SELECT r.customer_unique_id,
       r.customer_state,
       fc.category                                   AS first_category,
       r.revenue                                     AS first_order_value,
       NTILE(4) OVER (ORDER BY r.revenue)            AS first_value_quartile,
       r.main_payment_type                           AS first_payment_type,
       r.is_late                                     AS first_is_late,
       r.review_score                                AS first_review_score,
       l.is_repeat
FROM ranked r
JOIN later l USING (customer_unique_id)
LEFT JOIN first_cat fc ON fc.order_id = r.order_id
WHERE r.n = 1
  AND r.purchase_ts < DATE '2018-06-01';

-- helper: one query per segment variable, same shape
SELECT 'state' AS segment_type, customer_state AS segment,
       COUNT(*) AS customers, COUNT(*) FILTER (WHERE is_repeat) AS repeat_customers,
       ROUND(100.0 * COUNT(*) FILTER (WHERE is_repeat) / COUNT(*), 2) AS repeat_rate_pct,
       (COUNT(*) >= 300) AS meets_min_n
FROM tmp_first_order GROUP BY customer_state
UNION ALL
SELECT 'first_value_quartile', first_value_quartile::text,
       COUNT(*), COUNT(*) FILTER (WHERE is_repeat),
       ROUND(100.0 * COUNT(*) FILTER (WHERE is_repeat) / COUNT(*), 2), (COUNT(*) >= 300)
FROM tmp_first_order GROUP BY first_value_quartile
UNION ALL
SELECT 'first_payment_type', COALESCE(first_payment_type, 'none'),
       COUNT(*), COUNT(*) FILTER (WHERE is_repeat),
       ROUND(100.0 * COUNT(*) FILTER (WHERE is_repeat) / COUNT(*), 2), (COUNT(*) >= 300)
FROM tmp_first_order GROUP BY first_payment_type
UNION ALL
SELECT 'first_delivery', CASE first_is_late WHEN 1 THEN 'late' WHEN 0 THEN 'on time' ELSE 'unknown' END,
       COUNT(*), COUNT(*) FILTER (WHERE is_repeat),
       ROUND(100.0 * COUNT(*) FILTER (WHERE is_repeat) / COUNT(*), 2), (COUNT(*) >= 300)
FROM tmp_first_order GROUP BY first_is_late
UNION ALL
SELECT 'first_review_score', COALESCE(first_review_score::text, 'no review'),
       COUNT(*), COUNT(*) FILTER (WHERE is_repeat),
       ROUND(100.0 * COUNT(*) FILTER (WHERE is_repeat) / COUNT(*), 2), (COUNT(*) >= 300)
FROM tmp_first_order GROUP BY first_review_score
ORDER BY segment_type, repeat_rate_pct DESC;

-- first category: top 15 categories by number of first orders
SELECT first_category,
       COUNT(*) AS customers,
       COUNT(*) FILTER (WHERE is_repeat) AS repeat_customers,
       ROUND(100.0 * COUNT(*) FILTER (WHERE is_repeat) / COUNT(*), 2) AS repeat_rate_pct
FROM tmp_first_order
GROUP BY first_category
HAVING COUNT(*) >= 300
ORDER BY repeat_rate_pct DESC;

-- Confounder check for "first delivery late vs on time":
-- compare the repeat rate WITHIN the 5 largest states
WITH big AS (
    SELECT customer_state FROM tmp_first_order
    GROUP BY customer_state ORDER BY COUNT(*) DESC LIMIT 5
)
SELECT t.customer_state,
       CASE t.first_is_late WHEN 1 THEN 'late' ELSE 'on time' END AS first_delivery,
       COUNT(*) AS customers,
       ROUND(100.0 * COUNT(*) FILTER (WHERE is_repeat) / COUNT(*), 2) AS repeat_rate_pct
FROM tmp_first_order t
JOIN big USING (customer_state)
WHERE t.first_is_late IS NOT NULL
GROUP BY t.customer_state, 2
ORDER BY t.customer_state, 2;
