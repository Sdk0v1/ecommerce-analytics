# Power BI

Place `ecommerce_dashboard.pbix` here (not committed yet).

Pages:
1. Executive Overview — KPI cards (Revenue, Orders, AOV, Repeat Rate, On-Time %, Avg Review) + 5 visuals
2. State Detail (drill-through on customer_state)
3. Category Detail (drill-through on category)

Data source: CSV exports in `reports/tables/` written by `SQL/99_export_tables.sql` and the notebooks — `order_base.csv`, `item_base.csv`, `cohort_retention.csv`, `delivery_orders.csv`, `rfm_segments.csv`. They come from the PostgreSQL views `analytics.order_base` / `analytics.item_base`, so the definitions are the same as in the analysis. PostgreSQL booleans are exported as `t` / `f`.

Measures (definitions match `Documentation/methodology.md`; expected values for the KPI period 2017-01 .. 2018-08):

| Measure | DAX (sketch) | Definition | Expected value |
| --- | --- | --- | --- |
| Revenue | `SUM(order_base[revenue])` | price + freight of delivered orders | R$ 15,377,809.91 |
| Orders | `DISTINCTCOUNT(order_base[order_id])` | delivered orders | 96,211 |
| AOV | `DIVIDE([Revenue], [Orders])` | revenue / orders | R$ 159.83 |
| Customers | `DISTINCTCOUNT(order_base[customer_unique_id])` | unique customers (whole history) | 93,358 |
| Repeat Rate | customers with ≥ 2 orders / Customers | whole history | 3.00% |
| On-Time % | `1 - AVERAGE(delivery_orders[is_late])` | delivered date ≤ estimated date | 93.21% |
| Median Delivery Days | `MEDIAN(delivery_orders[delivery_days])` | purchase → customer delivery | 10.21 |
| p90 Delivery Days | `PERCENTILE.INC(delivery_orders[delivery_days], 0.9)` | | 23.06 |
| Avg Review | `AVERAGE(delivery_orders[review_score])` | latest review per order | 4.16 |
| Revenue MoM % | `DIVIDE([Revenue] - [Revenue PM], [Revenue PM])` | vs previous month (date table) | — |

Filter all measures except Customers / Repeat Rate on `in_kpi_period = TRUE`.
