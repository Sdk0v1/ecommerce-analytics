-- =====================================================================
-- 99_export_tables.sql
-- Purpose : export the analytics views to CSV for Python and Power BI
-- Run     : from the repository root, after 00, 01 and the analysis files
--           (cohort_analysis.sql and delivery_analysis.sql create views):
--             psql -d olist -f SQL/99_export_tables.sql
-- =====================================================================
\copy (SELECT * FROM analytics.order_base ORDER BY purchase_ts)                 TO 'reports/tables/order_base.csv'       WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM analytics.item_base ORDER BY order_id, order_item_id)      TO 'reports/tables/item_base.csv'        WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM analytics.delivery_orders ORDER BY order_id)               TO 'reports/tables/delivery_orders.csv'  WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM analytics.cohort_retention ORDER BY cohort_month, month_number) TO 'reports/tables/cohort_retention.csv' WITH (FORMAT csv, HEADER true)

-- Monthly KPI table (same logic as monthly_kpis.sql R1.4) - used by the Python validation
\copy (SELECT purchase_month AS month, COUNT(DISTINCT order_id) AS orders, SUM(revenue) AS revenue, SUM(revenue) / COUNT(DISTINCT order_id) AS aov FROM analytics.order_base WHERE in_kpi_period GROUP BY purchase_month ORDER BY purchase_month) TO 'reports/tables/monthly_kpis.csv' WITH (FORMAT csv, HEADER true)

-- Headline numbers calculated in SQL - compared with Python in data_cleaning.py
\copy (SELECT 'total_orders' AS metric, COUNT(*)::numeric AS sql_value FROM analytics.order_base WHERE in_kpi_period UNION ALL SELECT 'total_revenue', SUM(revenue) FROM analytics.order_base WHERE in_kpi_period UNION ALL SELECT 'aov', SUM(revenue) / COUNT(*) FROM analytics.order_base WHERE in_kpi_period UNION ALL SELECT 'total_customers', COUNT(DISTINCT customer_unique_id) FROM analytics.order_base UNION ALL SELECT 'repeat_customers', COUNT(*) FROM (SELECT customer_unique_id FROM analytics.order_base GROUP BY 1 HAVING COUNT(*) >= 2) t UNION ALL SELECT 'repeat_rate_pct', 100.0 * (SELECT COUNT(*) FROM (SELECT customer_unique_id FROM analytics.order_base GROUP BY 1 HAVING COUNT(*) >= 2) t) / (SELECT COUNT(DISTINCT customer_unique_id) FROM analytics.order_base) UNION ALL SELECT 'top_category_revenue', MAX(r) FROM (SELECT SUM(item_revenue) AS r FROM analytics.item_base WHERE in_kpi_period GROUP BY category) t UNION ALL SELECT 'on_time_pct', 100.0 * AVG(1 - is_late) FROM analytics.delivery_orders UNION ALL SELECT 'median_delivery_days', PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY delivery_days)::numeric FROM analytics.delivery_orders UNION ALL SELECT 'p90_delivery_days', PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY delivery_days)::numeric FROM analytics.delivery_orders UNION ALL SELECT 'revenue_2017_11', SUM(revenue) FROM analytics.order_base WHERE purchase_month = DATE '2017-11-01') TO 'reports/tables/sql_headline_numbers.csv' WITH (FORMAT csv, HEADER true)
