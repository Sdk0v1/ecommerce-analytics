-- =====================================================================
-- revenue_analysis.sql
-- Мета    : чинники виручки (обсяг vs AOV), категорії, штати,
--           RANK() категорій у межах штатів
-- Відповідає на : R2, R3, R4 (зокрема R4.3 YoY), R5 ·  Нотатки: P2 - Чинники виручки, P2 - Категорії та штати
-- Джерело : analytics.order_base, analytics.item_base
--   Замовлення = доставлене замовлення · Виручка = SUM(price + freight_value)
-- Сукупність: доставлені замовлення, куплені 2017-01 .. 2018-08
-- Мінімальний розмір вибірки для показників штатів / категорій: 300 замовлень
-- =====================================================================

-- ---------------------------------------------------------------------
-- R2/R3.1: помісячна декомпозиція зміни виручки
--   R = N * A  ->  dR = dN*A0 (обсяг) + N0*dA (AOV) + dN*dA (взаємодія)
--   check_sum має дорівнювати 0 (з точністю до округлення)
-- R2/R3.2: головний чинник за місяць = ефект із найбільшим абсолютним значенням
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
       -- чи рухається AOV у тому ж напрямку, що й виручка?
       CASE WHEN SIGN(volume_effect) = SIGN(aov_effect) THEN 'same direction'
            ELSE 'opposite directions' END AS effects_direction
FROM effects
ORDER BY month;

-- Кількість місяців за головним чинником
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

-- Частка абсолютної помісячної зміни виручки, яку пояснює кожен ефект
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
-- R2/R3.3: декомпозиція за весь період
-- Порівнюємо перші 3 місяці (2017-01..03) з останніми 3 місяцями
-- (2018-06..08), беручи середньомісячні значення, щоб згладити шум окремих місяців.
-- ---------------------------------------------------------------------
WITH periods AS (
    SELECT CASE WHEN purchase_month BETWEEN DATE '2017-01-01' AND DATE '2017-03-01' THEN 'start'
                WHEN purchase_month BETWEEN DATE '2018-06-01' AND DATE '2018-08-01' THEN 'end' END AS period,
           order_id, revenue
    FROM analytics.order_base
    WHERE in_kpi_period
), agg AS (
    SELECT period,
           COUNT(DISTINCT order_id) / 3.0 AS n,          -- замовлень на місяць
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
       -- логарифмічна декомпозиція (без члена взаємодії): частки ln(R1/R0)
       ROUND(100 * LN(n1 / n0) / LN((n1 * a1) / (n0 * a0)), 1)       AS log_volume_share_pct,
       ROUND(100 * LN(a1 / a0) / LN((n1 * a1) / (n0 * a0)), 1)       AS log_aov_share_pct
FROM p;

-- RD4: кореляція помісячних змін (%) замовлень і AOV (лише опис - ~19 точок)
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
-- R4.1 + R4.2: категорії - виручка, замовлення, виручка категорії на замовлення,
-- середня ціна товару, частка й кумулятивна частка (Парето)
-- Замовлення категорії = замовлення, що МІСТЯТЬ цю категорію; їхня сума більша
-- за загальну кількість замовлень, бо деякі замовлення містять кілька категорій.
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

-- A2: скільки категорій дають 80% виручки?
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

-- A5: помісячна виручка топ-5 категорій (чи припадає сплеск на одну категорію?)
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
-- R4.3: річне (YoY) зростання виручки топ-5 категорій за загальною
-- виручкою (KPI-період 2017-01..2018-08), порівняння січ.-серп. 2018 із
-- січ.-серп. 2017 (ті самі 8 місяців в обох роках, тож сезонність не змішується).
-- Орієнтир: рядок «ALL CATEGORIES» = уся платформа; share = виручка категорії
-- / виручка платформи за той самий період; share_change_pp і
-- growth_vs_platform_pp > 0 означають, що категорія зростала швидше за платформу.
-- ---------------------------------------------------------------------
WITH by_category AS (
    SELECT category,
           SUM(item_revenue) FILTER (WHERE purchase_month BETWEEN DATE '2017-01-01' AND DATE '2017-08-01') AS revenue_2017,
           SUM(item_revenue) FILTER (WHERE purchase_month BETWEEN DATE '2018-01-01' AND DATE '2018-08-01') AS revenue_2018,
           SUM(item_revenue) AS revenue_total
    FROM analytics.item_base
    WHERE in_kpi_period
    GROUP BY category
), top5 AS (
    SELECT category, revenue_2017, revenue_2018
    FROM by_category
    ORDER BY revenue_total DESC
    LIMIT 5
), platform AS (
    SELECT SUM(revenue_2017) AS revenue_2017,
           SUM(revenue_2018) AS revenue_2018
    FROM by_category
), result AS (
    SELECT 1 AS sort_group, 'ALL CATEGORIES'::text AS category,
           revenue_2017, revenue_2018
    FROM platform
    UNION ALL
    SELECT 2, category, revenue_2017, revenue_2018
    FROM top5
), metrics AS (
    SELECT r.*,
           100 * (r.revenue_2018 - r.revenue_2017) / NULLIF(r.revenue_2017, 0) AS yoy_growth_pct,
           100 * r.revenue_2017 / NULLIF(p.revenue_2017, 0)                    AS share_2017_pct,
           100 * r.revenue_2018 / NULLIF(p.revenue_2018, 0)                    AS share_2018_pct
    FROM result r
    CROSS JOIN platform p
)
SELECT CASE WHEN sort_group = 2
            THEN RANK() OVER (PARTITION BY sort_group ORDER BY revenue_2018 DESC)
       END                                                      AS revenue_rank_2018,
       category,
       ROUND(revenue_2017, 2)                                   AS revenue_jan_aug_2017,
       ROUND(revenue_2018, 2)                                   AS revenue_jan_aug_2018,
       ROUND(revenue_2018 - revenue_2017, 2)                    AS delta_revenue,
       ROUND(yoy_growth_pct, 1)                                 AS yoy_growth_pct,
       ROUND(share_2017_pct, 2)                                 AS share_2017_pct,
       ROUND(share_2018_pct, 2)                                 AS share_2018_pct,
       ROUND(share_2018_pct - share_2017_pct, 2)                AS share_change_pp,
       ROUND(yoy_growth_pct
             - MAX(yoy_growth_pct) FILTER (WHERE sort_group = 1) OVER (), 1) AS growth_vs_platform_pp
FROM metrics
ORDER BY sort_group, revenue_2018 DESC;

-- ---------------------------------------------------------------------
-- R5.1 + R5.2 + B3: штати - виручка, замовлення, клієнти, AOV, ранг,
-- AOV з доставкою і без неї, частка доставки у вартості замовлення
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
-- R4 x R5 (C1): топ-3 категорії за виручкою в кожному штаті - RANK()
-- RANK обрано замість ROW_NUMBER, щоб нічиї не розбивалися довільно
-- (через нічию для штату може бути 4 рядки - це чесно).
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

-- C2: у скількох штатах категорія #1 загалом по країні НЕ є #1?
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
