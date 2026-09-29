-- =====================================================================
-- revenue_analysis.sql
-- Purpose : revenue drivers (volume vs AOV), categories, states,
--           RANK() of categories within states
-- Answers : R2, R3, R4, R5  ·  Notes: P2 - Revenue Drivers, P2 - Categories and States
-- Source  : analytics.order_base, analytics.item_base
--   Order   = delivered order · Revenue = SUM(price + freight_value)
-- Population: delivered orders purchased 2017-01 .. 2018-08
-- Minimum sample size for state / category rates: 300 orders
-- =====================================================================

-- ---------------------------------------------------------------------
-- R2/R3.1: monthly decomposition of the revenue change
--   R = N * A  ->  dR = dN*A0 (volume) + N0*dA (AOV) + dN*dA (interaction)
--   check_sum must be 0 (up to rounding)
-- R2/R3.2: main driver per month = effect with the largest absolute value
-- ---------------------------------------------------------------------
WITH monthly AS (
    SELECT purchase_month AS month,
           COUNT(DISTINCT order_id)::numeric AS n,
           SUM(revenue) AS r
    FROM analytics.order_base
    WHERE in_kpi_period
    GROUP BY purchase_month
), base AS (
    SELECT month, n, r, r / n AS a,
           LAG(n)     OVER (ORDER BY month) AS n0,
           LAG(r / n) OVER (ORDER BY month) AS a0,
           LAG(r)     OVER (ORDER BY month) AS r0
    FROM monthly
), effects AS (
    SELECT month,
           r - r0                    AS delta_revenue,
           (n - n0) * a0             AS volume_effect,
           n0 * (a - a0)             AS aov_effect,
           (n - n0) * (a - a0)       AS interaction
    FROM base
    WHERE r0 IS NOT NULL
)
SELECT month,
       ROUND(delta_revenue, 2)  AS delta_revenue,
       ROUND(volume_effect, 2)  AS volume_effect,
       ROUND(aov_effect, 2)     AS aov_effect,
       ROUND(interaction, 2)    AS interaction,
       ROUND(volume_effect + aov_effect + interaction - delta_revenue, 6) AS check_sum,
       CASE WHEN ABS(volume_effect) >= ABS(aov_effect) THEN 'volume' ELSE 'aov' END AS main_driver,
       -- does AOV move in the same direction as revenue?
       CASE WHEN SIGN(volume_effect) = SIGN(aov_effect) THEN 'same direction'
            ELSE 'opposite directions' END AS effects_direction
FROM effects
ORDER BY month;

-- Count of months by main driver
WITH monthly AS (
    SELECT purchase_month AS month, COUNT(DISTINCT order_id)::numeric AS n, SUM(revenue) AS r
    FROM analytics.order_base WHERE in_kpi_period GROUP BY purchase_month
), e AS (
    SELECT (n - LAG(n) OVER w) * LAG(r / n) OVER w AS volume_effect,
           LAG(n) OVER w * (r / n - LAG(r / n) OVER w) AS aov_effect
    FROM monthly
    WINDOW w AS (ORDER BY month)
)
SELECT CASE WHEN ABS(volume_effect) >= ABS(aov_effect) THEN 'volume' ELSE 'aov' END AS main_driver,
       COUNT(*) AS months
FROM e
WHERE volume_effect IS NOT NULL
GROUP BY 1;

-- Share of the absolute monthly revenue movement explained by each effect
WITH monthly AS (
    SELECT purchase_month AS month, COUNT(DISTINCT order_id)::numeric AS n, SUM(revenue) AS r
    FROM analytics.order_base WHERE in_kpi_period GROUP BY purchase_month
), e AS (
    SELECT (n - LAG(n) OVER w) * LAG(r / n) OVER w           AS volume_effect,
           LAG(n) OVER w * (r / n - LAG(r / n) OVER w)       AS aov_effect,
           (n - LAG(n) OVER w) * (r / n - LAG(r / n) OVER w) AS interaction
    FROM monthly
    WINDOW w AS (ORDER BY month)
)
SELECT ROUND(100 * SUM(ABS(volume_effect)) / SUM(ABS(volume_effect) + ABS(aov_effect) + ABS(interaction)), 1) AS pct_volume,
       ROUND(100 * SUM(ABS(aov_effect))    / SUM(ABS(volume_effect) + ABS(aov_effect) + ABS(interaction)), 1) AS pct_aov,
       ROUND(100 * SUM(ABS(interaction))   / SUM(ABS(volume_effect) + ABS(aov_effect) + ABS(interaction)), 1) AS pct_interaction
FROM e
WHERE volume_effect IS NOT NULL;

-- ---------------------------------------------------------------------
-- R2/R3.3: whole-period decomposition
-- Compare the first 3 months (2017-01..03) with the last 3 months
-- (2018-06..08), using monthly averages to smooth single-month noise.
-- ---------------------------------------------------------------------
WITH periods AS (
    SELECT CASE WHEN purchase_month BETWEEN DATE '2017-01-01' AND DATE '2017-03-01' THEN 'start'
                WHEN purchase_month BETWEEN DATE '2018-06-01' AND DATE '2018-08-01' THEN 'end' END AS period,
           order_id, revenue
    FROM analytics.order_base
    WHERE in_kpi_period
), agg AS (
    SELECT period,
           COUNT(DISTINCT order_id) / 3.0 AS n,          -- orders per month
           SUM(revenue) / COUNT(DISTINCT order_id) AS a   -- AOV
    FROM periods
    WHERE period IS NOT NULL
    GROUP BY period
), p AS (
    SELECT MAX(n) FILTER (WHERE period = 'start') AS n0, MAX(a) FILTER (WHERE period = 'start') AS a0,
           MAX(n) FILTER (WHERE period = 'end')   AS n1, MAX(a) FILTER (WHERE period = 'end')   AS a1
    FROM agg
)
SELECT ROUND(n0, 1) AS orders_per_month_start, ROUND(n1, 1) AS orders_per_month_end,
       ROUND(a0, 2) AS aov_start, ROUND(a1, 2) AS aov_end,
       ROUND(n0 * a0, 2) AS revenue_per_month_start, ROUND(n1 * a1, 2) AS revenue_per_month_end,
       ROUND(n1 * a1 - n0 * a0, 2)       AS delta_revenue,
       ROUND((n1 - n0) * a0, 2)          AS volume_effect,
       ROUND(n0 * (a1 - a0), 2)          AS aov_effect,
       ROUND((n1 - n0) * (a1 - a0), 2)   AS interaction,
       ROUND(100 * (n1 - n0) * a0 / (n1 * a1 - n0 * a0), 1)          AS volume_share_pct,
       ROUND(100 * n0 * (a1 - a0) / (n1 * a1 - n0 * a0), 1)          AS aov_share_pct,
       ROUND(100 * (n1 - n0) * (a1 - a0) / (n1 * a1 - n0 * a0), 1)   AS interaction_share_pct,
       -- log decomposition (no interaction term): shares of ln(R1/R0)
       ROUND(100 * LN(n1 / n0) / LN((n1 * a1) / (n0 * a0)), 1)       AS log_volume_share_pct,
       ROUND(100 * LN(a1 / a0) / LN((n1 * a1) / (n0 * a0)), 1)       AS log_aov_share_pct
FROM p;

-- RD4: correlation of monthly % changes in orders and AOV (describe only - ~19 points)
WITH monthly AS (
    SELECT purchase_month AS month, COUNT(DISTINCT order_id)::numeric AS n, SUM(revenue) / COUNT(DISTINCT order_id) AS a
    FROM analytics.order_base WHERE in_kpi_period GROUP BY purchase_month
), g AS (
    SELECT n / LAG(n) OVER w - 1 AS orders_growth,
           a / LAG(a) OVER w - 1 AS aov_growth
    FROM monthly WINDOW w AS (ORDER BY month)
)
SELECT ROUND(CORR(orders_growth, aov_growth)::numeric, 3) AS corr_orders_vs_aov_growth,
       ROUND(STDDEV_SAMP(orders_growth) * 100, 1)        AS std_orders_growth_pct,
       ROUND(STDDEV_SAMP(aov_growth) * 100, 1)           AS std_aov_growth_pct
FROM g;

-- ---------------------------------------------------------------------
-- R4.1 + R4.2: categories - revenue, orders, category revenue per order,
-- average item price, share and cumulative share (Pareto)
-- Orders per category = orders CONTAINING the category; their sum is larger
-- than total orders because some orders contain several categories.
-- ---------------------------------------------------------------------
WITH cat AS (
    SELECT category,
           SUM(item_revenue)          AS revenue,
           COUNT(DISTINCT order_id)   AS orders_containing,
           COUNT(*)                   AS items,
           AVG(price)                 AS avg_item_price
    FROM analytics.item_base
    WHERE in_kpi_period
    GROUP BY category
)
SELECT RANK() OVER (ORDER BY revenue DESC)                          AS revenue_rank,
       category,
       ROUND(revenue, 2)                                             AS revenue,
       orders_containing,
       RANK() OVER (ORDER BY orders_containing DESC)                AS orders_rank,
       items,
       ROUND(revenue / orders_containing, 2)                        AS category_revenue_per_order,
       ROUND(avg_item_price, 2)                                      AS avg_item_price,
       ROUND(100 * revenue / SUM(revenue) OVER (), 2)                AS revenue_share_pct,
       ROUND(100 * SUM(revenue) OVER (ORDER BY revenue DESC ROWS UNBOUNDED PRECEDING)
                 / SUM(revenue) OVER (), 2)                          AS cumulative_share_pct
FROM cat
ORDER BY revenue DESC;

-- A2: how many categories make 80% of revenue?
WITH cat AS (
    SELECT category, SUM(item_revenue) AS revenue
    FROM analytics.item_base WHERE in_kpi_period GROUP BY category
), cum AS (
    SELECT category,
           SUM(revenue) OVER (ORDER BY revenue DESC ROWS UNBOUNDED PRECEDING) / SUM(revenue) OVER () AS cum_share
    FROM cat
)
SELECT COUNT(*) FILTER (WHERE cum_share < 0.8) + 1 AS categories_for_80pct_revenue,
       COUNT(*)                                     AS total_categories
FROM cum;

-- A5: monthly revenue of the top 5 categories (did one category drive a spike?)
WITH top5 AS (
    SELECT category FROM analytics.item_base WHERE in_kpi_period
    GROUP BY category ORDER BY SUM(item_revenue) DESC LIMIT 5
)
SELECT ib.purchase_month, ib.category, ROUND(SUM(ib.item_revenue), 2) AS revenue
FROM analytics.item_base ib
JOIN top5 USING (category)
WHERE ib.in_kpi_period
GROUP BY ib.purchase_month, ib.category
ORDER BY ib.purchase_month, revenue DESC;

-- ---------------------------------------------------------------------
-- R5.1 + R5.2 + B3: states - revenue, orders, customers, AOV, rank,
-- AOV with and without freight, freight share of order value
-- ---------------------------------------------------------------------
WITH st AS (
    SELECT customer_state,
           COUNT(DISTINCT order_id)            AS orders,
           COUNT(DISTINCT customer_unique_id)  AS customers,
           SUM(revenue)                        AS revenue,
           SUM(product_value)                  AS product_value,
           SUM(freight_value)                  AS freight_value
    FROM analytics.order_base
    WHERE in_kpi_period
    GROUP BY customer_state
)
SELECT RANK() OVER (ORDER BY revenue DESC)                                    AS revenue_rank,
       customer_state,
       orders,
       customers,
       ROUND(revenue, 2)                                                       AS revenue,
       ROUND(100 * revenue / SUM(revenue) OVER (), 2)                          AS revenue_share_pct,
       ROUND(100 * SUM(revenue) OVER (ORDER BY revenue DESC ROWS UNBOUNDED PRECEDING)
                 / SUM(revenue) OVER (), 2)                                    AS cumulative_share_pct,
       ROUND(revenue / orders, 2)                                              AS aov,
       ROUND(product_value / orders, 2)                                        AS aov_without_freight,
       ROUND(freight_value / orders, 2)                                        AS freight_per_order,
       ROUND(100 * freight_value / revenue, 1)                                 AS freight_share_pct,
       (orders >= 300)                                                         AS meets_min_n
FROM st
ORDER BY revenue DESC;

-- ---------------------------------------------------------------------
-- R4 x R5 (C1): top 3 categories by revenue within each state - RANK()
-- RANK chosen over ROW_NUMBER so that ties are not broken arbitrarily
-- (a tie can show 4 rows for a state - that is honest).
-- ---------------------------------------------------------------------
WITH cs AS (
    SELECT customer_state, category, SUM(item_revenue) AS revenue
    FROM analytics.item_base
    WHERE in_kpi_period
    GROUP BY customer_state, category
), ranked AS (
    SELECT customer_state, category, revenue,
           RANK() OVER (PARTITION BY customer_state ORDER BY revenue DESC) AS rank_in_state,
           100 * revenue / SUM(revenue) OVER (PARTITION BY customer_state) AS share_in_state
    FROM cs
)
SELECT customer_state, rank_in_state, category,
       ROUND(revenue, 2) AS revenue, ROUND(share_in_state, 1) AS share_in_state_pct
FROM ranked
WHERE rank_in_state <= 3
ORDER BY customer_state, rank_in_state;

-- C2: in how many states is the national #1 category NOT #1?
WITH national AS (
    SELECT category FROM analytics.item_base WHERE in_kpi_period
    GROUP BY category ORDER BY SUM(item_revenue) DESC LIMIT 1
), cs AS (
    SELECT customer_state, category,
           RANK() OVER (PARTITION BY customer_state ORDER BY SUM(item_revenue) DESC) AS rnk
    FROM analytics.item_base
    WHERE in_kpi_period
    GROUP BY customer_state, category
)
SELECT (SELECT category FROM national)                                        AS national_top_category,
       COUNT(DISTINCT customer_state)                                         AS states,
       COUNT(DISTINCT customer_state) FILTER (WHERE rnk = 1
             AND category = (SELECT category FROM national))                  AS states_where_it_is_top1
FROM cs;
