-- =====================================================================
-- monthly_kpis.sql
-- Мета    : замовлення, виручка, AOV за місяць + зміна місяць до місяця (LAG)
-- Відповідає: R1   ·  Нотатки: P2 - Monthly KPIs and MoM
-- Джерело : analytics.order_base (визначення в 01_analytics_views.sql)
--   Замовлення = доставлене замовлення
--   Виручка    = SUM(price + freight_value)
--   AOV        = Виручка / Замовлення
-- Вибірка: доставлені замовлення, куплені 2017-01 .. 2018-08 (in_kpi_period)
-- =====================================================================

-- ---------------------------------------------------------------------
-- R1.1 + R1.2: які щомісячні замовлення, виручка, AOV?
-- R1.3: чи не пропущено жодного календарного місяця? (LAG бере попередній РЯДОК,
--       тож пропущений місяць непомітно порівнювався б із позаминулим).
--       generate_series будує повний список місяців; LEFT JOIN виявляє пропуски.
-- ---------------------------------------------------------------------
WITH months AS (
    SELECT generate_series(DATE '2017-01-01', DATE '2018-08-01', INTERVAL '1 month')::date AS month
), monthly AS (
    SELECT purchase_month           AS month,
           COUNT(DISTINCT order_id) AS orders,
           SUM(revenue)             AS revenue
    FROM analytics.order_base
    WHERE in_kpi_period
    GROUP BY purchase_month
)
SELECT m.month,
       COALESCE(k.orders, 0)                      AS orders,
       COALESCE(k.revenue, 0)                     AS revenue,
       ROUND(k.revenue / NULLIF(k.orders, 0), 2)  AS aov,
       (k.month IS NULL)                          AS is_missing_month
FROM months m
LEFT JOIN monthly k ON k.month = m.month
ORDER BY m.month;

-- ---------------------------------------------------------------------
-- R1.4: яка MoM-динаміка виручки, замовлень і AOV?
-- Перший місяць не має попереднього значення -> LAG повертає NULL -> приріст NULL.
-- ---------------------------------------------------------------------
WITH monthly AS (
    SELECT purchase_month               AS month,
           COUNT(DISTINCT order_id)     AS orders,
           SUM(revenue)                 AS revenue,
           SUM(revenue) / COUNT(DISTINCT order_id) AS aov
    FROM analytics.order_base
    WHERE in_kpi_period
    GROUP BY purchase_month
), with_prev AS (
    SELECT month, orders, revenue, aov,
           LAG(revenue) OVER (ORDER BY month) AS prev_revenue,
           LAG(orders)  OVER (ORDER BY month) AS prev_orders,
           LAG(aov)     OVER (ORDER BY month) AS prev_aov
    FROM monthly
)
SELECT month,
       orders,
       ROUND(revenue, 2)                                                      AS revenue,
       ROUND(aov, 2)                                                          AS aov,
       ROUND(prev_revenue, 2)                                                 AS prev_revenue,
       ROUND(revenue - prev_revenue, 2)                                       AS mom_revenue_change,
       ROUND(100.0 * (revenue - prev_revenue) / NULLIF(prev_revenue, 0), 1)   AS mom_revenue_growth_pct,
       prev_orders,
       orders - prev_orders                                                   AS mom_orders_change,
       ROUND(100.0 * (orders - prev_orders) / NULLIF(prev_orders, 0), 1)     AS mom_orders_growth_pct,
       ROUND(prev_aov, 2)                                                     AS prev_aov,
       ROUND(aov - prev_aov, 2)                                               AS mom_aov_change,
       ROUND(100.0 * (aov - prev_aov) / NULLIF(prev_aov, 0), 1)              AS mom_aov_growth_pct
FROM with_prev
ORDER BY month;

-- ---------------------------------------------------------------------
-- R1.5: яке 3-місячне ковзне середнє виручки та приріст рік до року?
-- YoY через LAG(x, 12) коректний, бо R1.3 показав відсутність пропущених місяців.
-- ---------------------------------------------------------------------
WITH monthly AS (
    SELECT purchase_month AS month,
           COUNT(DISTINCT order_id) AS orders,
           SUM(revenue) AS revenue
    FROM analytics.order_base
    WHERE in_kpi_period
    GROUP BY purchase_month
)
SELECT month,
       ROUND(revenue, 2) AS revenue,
       ROUND(AVG(revenue) OVER (ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 2) AS revenue_rolling_3m,
       ROUND(LAG(revenue, 12) OVER (ORDER BY month), 2)                                       AS revenue_same_month_last_year,
       ROUND(100.0 * (revenue - LAG(revenue, 12) OVER (ORDER BY month))
             / NULLIF(LAG(revenue, 12) OVER (ORDER BY month), 0), 1)                          AS yoy_revenue_growth_pct,
       ROUND(100.0 * (orders - LAG(orders, 12) OVER (ORDER BY month))
             / NULLIF(LAG(orders, 12) OVER (ORDER BY month), 0), 1)                           AS yoy_orders_growth_pct
FROM monthly
ORDER BY month;

-- ---------------------------------------------------------------------
-- R1 підсумок: наскільки волатильний MoM-приріст виручки? (M2 у нотатці)
-- ---------------------------------------------------------------------
WITH monthly AS (
    SELECT purchase_month AS month, SUM(revenue) AS revenue
    FROM analytics.order_base
    WHERE in_kpi_period
    GROUP BY purchase_month
), g AS (
    SELECT month,
           100.0 * (revenue - LAG(revenue) OVER (ORDER BY month))
                 / NULLIF(LAG(revenue) OVER (ORDER BY month), 0) AS mom_pct
    FROM monthly
)
SELECT ROUND(MIN(mom_pct), 1)                       AS min_mom_pct,
       ROUND(MAX(mom_pct), 1)                       AS max_mom_pct,
       ROUND(AVG(mom_pct), 1)                       AS avg_mom_pct,
       ROUND(STDDEV_SAMP(mom_pct), 1)               AS std_mom_pct,
       COUNT(*) FILTER (WHERE mom_pct < 0)          AS negative_months,
       COUNT(mom_pct)                               AS months_with_mom
FROM g;
