-- =====================================================================
-- cohort_analysis.sql
-- Purpose : first-purchase-month cohorts and their retention over time
-- Answers : C1, C3 (over time)  ·  Notes: P2 - Cohort Analysis
-- Source  : analytics.order_base
--   Customer     = customer_unique_id
--   Order        = delivered order
--   Cohort month = month of the customer's first delivered order
--   month_number = months between cohort month and order month (0, 1, 2 ...)
--   Retention(k) = customers with an order in month k / cohort size
-- Cohorts shown: 2017-01 .. 2018-08 (2016 cohorts are tiny, < 350 customers).
-- Last observed month: 2018-08 -> newer cohorts have fewer observed months
-- (triangle). Unobserved cells are NULL, never 0.
-- =====================================================================

-- ---------------------------------------------------------------------
-- CO.1 - CO.5: long table (cohort_month, month_number, active, size, retention)
-- Export: \copy (...) TO 'reports/tables/cohort_retention.csv' CSV HEADER
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS analytics.cohort_retention;
CREATE VIEW analytics.cohort_retention AS
WITH customer_orders AS (                      -- CO.1
    SELECT customer_unique_id, purchase_month
    FROM analytics.order_base
), first_purchase AS (                         -- CO.2
    SELECT customer_unique_id, MIN(purchase_month) AS cohort_month
    FROM customer_orders
    GROUP BY customer_unique_id
), activity AS (                               -- CO.3
    SELECT f.cohort_month,
           co.customer_unique_id,
           (EXTRACT(YEAR  FROM co.purchase_month) - EXTRACT(YEAR  FROM f.cohort_month)) * 12
         + (EXTRACT(MONTH FROM co.purchase_month) - EXTRACT(MONTH FROM f.cohort_month)) AS month_number
    FROM customer_orders co
    JOIN first_purchase f USING (customer_unique_id)
), cohort_size AS (                            -- CO.4
    SELECT cohort_month, COUNT(*) AS cohort_size
    FROM first_purchase
    GROUP BY cohort_month
)
SELECT a.cohort_month,
       a.month_number::int                               AS month_number,
       COUNT(DISTINCT a.customer_unique_id)              AS active_customers,
       s.cohort_size,
       ROUND(100.0 * COUNT(DISTINCT a.customer_unique_id) / s.cohort_size, 3) AS retention_pct
FROM activity a
JOIN cohort_size s USING (cohort_month)
WHERE a.cohort_month BETWEEN DATE '2017-01-01' AND DATE '2018-08-01'
GROUP BY a.cohort_month, a.month_number, s.cohort_size;

-- Test of the month difference on known dates (expected: 0, 1, 12, 13)
SELECT (EXTRACT(YEAR FROM d2) - EXTRACT(YEAR FROM d1)) * 12
     + (EXTRACT(MONTH FROM d2) - EXTRACT(MONTH FROM d1)) AS month_number
FROM (VALUES (DATE '2017-12-01', DATE '2017-12-01'),
             (DATE '2017-12-01', DATE '2018-01-01'),
             (DATE '2017-01-01', DATE '2018-01-01'),
             (DATE '2017-12-01', DATE '2019-01-01')) AS t(d1, d2);

SELECT * FROM analytics.cohort_retention ORDER BY cohort_month, month_number;

-- ---------------------------------------------------------------------
-- CO.6: matrix, month 0 .. 12 (retention %)
-- Cells that cannot be observed yet (cohort_month + k > 2018-08) are NULL.
-- A cell that CAN be observed but had no returning customer is 0.
-- ---------------------------------------------------------------------
WITH sizes AS (
    SELECT DISTINCT cohort_month, cohort_size FROM analytics.cohort_retention
), cells AS (
    SELECT s.cohort_month, s.cohort_size, k.month_number,
           CASE WHEN (s.cohort_month + make_interval(months => k.month_number)) > DATE '2018-08-01' THEN NULL
                ELSE COALESCE(cr.retention_pct, 0) END AS retention_pct
    FROM sizes s
    CROSS JOIN generate_series(0, 12) AS k(month_number)
    LEFT JOIN analytics.cohort_retention cr
           ON cr.cohort_month = s.cohort_month AND cr.month_number = k.month_number
)
SELECT cohort_month, cohort_size,
       MAX(retention_pct) FILTER (WHERE month_number = 0)  AS m0,
       MAX(retention_pct) FILTER (WHERE month_number = 1)  AS m1,
       MAX(retention_pct) FILTER (WHERE month_number = 2)  AS m2,
       MAX(retention_pct) FILTER (WHERE month_number = 3)  AS m3,
       MAX(retention_pct) FILTER (WHERE month_number = 4)  AS m4,
       MAX(retention_pct) FILTER (WHERE month_number = 5)  AS m5,
       MAX(retention_pct) FILTER (WHERE month_number = 6)  AS m6,
       MAX(retention_pct) FILTER (WHERE month_number = 7)  AS m7,
       MAX(retention_pct) FILTER (WHERE month_number = 8)  AS m8,
       MAX(retention_pct) FILTER (WHERE month_number = 9)  AS m9,
       MAX(retention_pct) FILTER (WHERE month_number = 10) AS m10,
       MAX(retention_pct) FILTER (WHERE month_number = 11) AS m11,
       MAX(retention_pct) FILTER (WHERE month_number = 12) AS m12
FROM cells
GROUP BY cohort_month, cohort_size
ORDER BY cohort_month;

-- ---------------------------------------------------------------------
-- CO1 / CO2: typical retention at month 1, 3, 6 across cohorts
-- Only cohorts that have that month observed; median across cohorts.
-- ---------------------------------------------------------------------
WITH sizes AS (
    SELECT DISTINCT cohort_month FROM analytics.cohort_retention
), cells AS (
    SELECT s.cohort_month, k.month_number, COALESCE(cr.retention_pct, 0) AS retention_pct
    FROM sizes s
    CROSS JOIN (VALUES (1), (3), (6), (12)) AS k(month_number)
    LEFT JOIN analytics.cohort_retention cr
           ON cr.cohort_month = s.cohort_month AND cr.month_number = k.month_number
    WHERE (s.cohort_month + make_interval(months => k.month_number)) <= DATE '2018-08-01'
)
SELECT month_number,
       COUNT(*)                                                                   AS cohorts_observed,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY retention_pct)::numeric, 3) AS median_retention_pct,
       MIN(retention_pct)                                                         AS min_retention_pct,
       MAX(retention_pct)                                                         AS max_retention_pct
FROM cells
GROUP BY month_number
ORDER BY month_number;

-- ---------------------------------------------------------------------
-- CO4: cumulative retention - % of a cohort that returned AT LEAST ONCE
-- in months 1..k (a later month; same-month repeats are not counted)
-- ---------------------------------------------------------------------
WITH first_purchase AS (
    SELECT customer_unique_id, MIN(purchase_month) AS cohort_month
    FROM analytics.order_base
    GROUP BY customer_unique_id
), first_return AS (
    SELECT f.customer_unique_id, f.cohort_month,
           MIN((EXTRACT(YEAR FROM ob.purchase_month) - EXTRACT(YEAR FROM f.cohort_month)) * 12
             + (EXTRACT(MONTH FROM ob.purchase_month) - EXTRACT(MONTH FROM f.cohort_month)))
               FILTER (WHERE ob.purchase_month > f.cohort_month) AS first_return_month
    FROM first_purchase f
    JOIN analytics.order_base ob USING (customer_unique_id)
    GROUP BY f.customer_unique_id, f.cohort_month
)
SELECT cohort_month,
       COUNT(*) AS cohort_size,
       CASE WHEN cohort_month + INTERVAL '3 months' <= DATE '2018-08-01'
            THEN ROUND(100.0 * COUNT(*) FILTER (WHERE first_return_month <= 3) / COUNT(*), 2) END AS cum_returned_by_m3_pct,
       CASE WHEN cohort_month + INTERVAL '6 months' <= DATE '2018-08-01'
            THEN ROUND(100.0 * COUNT(*) FILTER (WHERE first_return_month <= 6) / COUNT(*), 2) END AS cum_returned_by_m6_pct,
       CASE WHEN cohort_month + INTERVAL '12 months' <= DATE '2018-08-01'
            THEN ROUND(100.0 * COUNT(*) FILTER (WHERE first_return_month <= 12) / COUNT(*), 2) END AS cum_returned_by_m12_pct
FROM first_return
WHERE cohort_month BETWEEN DATE '2017-01-01' AND DATE '2018-08-01'
GROUP BY cohort_month
ORDER BY cohort_month;
