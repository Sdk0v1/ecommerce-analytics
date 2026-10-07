# CLAUDE.md — ecommerce-analytics

Portfolio project of a Junior Data Analyst: **"E-commerce: Why Does Revenue Change and Who Comes Back?"** on the Olist Brazilian e-commerce dataset. The goal is a realistic analysis that moves from raw data → evidence → business insight → recommendation. Every number in the documentation must be reproducible from the code in this repo.

## Repository map
- `SQL/` — PostgreSQL. Run order: `00_create_tables` → `01_analytics_views` → `monthly_kpis` → `revenue_analysis` → `customer_retention` → `cohort_analysis` → `delivery_analysis` → `99_export_tables` (see `scripts/run_sql.sh`).
- `Python/` — analysis scripts (PyCharm, `# %%` cells), run order: `data_cleaning` → `rfm_analysis` → `statistical_analysis` → `sql_results_figures`.
- `Documentation/` — data dictionary, business questions, methodology, insights, recommendations.
- `reports/figures/` — charts made by code (never edit by hand). `reports/tables/` — generated CSVs (git-ignored).
- `data/raw/` — Olist CSVs, **git-ignored**; download with `scripts/download_data.sh`.

## Commands
```bash
bash scripts/download_data.sh          # data into data/raw/
createdb olist                         # once
bash scripts/run_sql.sh                # all SQL in order (uses PG* env vars)
python Python/data_cleaning.py         # etc., in the run order above (works from any folder)
```
CI (`.github/workflows/ci.yml`) runs exactly these steps on every push and pull request.

## Business definitions — single source of truth: `SQL/01_analytics_views.sql`
| Term | Definition |
| --- | --- |
| Order | order with `order_status = 'delivered'` |
| Revenue | `SUM(price + freight_value)` from `order_items` |
| AOV | revenue / `COUNT(DISTINCT order_id)` |
| Customer | `customer_unique_id` (never `customer_id` — it is created per order) |
| Month | `DATE_TRUNC('month', order_purchase_timestamp)` |
| KPI period | 2017-01 .. 2018-08 (complete months only) |
| Late | delivered **date** > estimated delivery **date** |
| Review score | latest review of the order (by `review_answer_timestamp`) |

Do not change a definition silently. If a change is needed: change it in `01_analytics_views.sql` **and** in `Python/data_cleaning.py` (A9), update `Documentation/methodology.md`, and say so in the PR description.

## Rules
1. **SQL style:** every query starts with a comment `-- <question ID>: <question>`; use CTEs, not deep nesting; aggregate "many" tables (items, payments, reviews) to order level **before** joining; `COUNT(DISTINCT ...)` for orders and customers; `NULLIF` in divisions; round only in the final `SELECT`.
2. **SQL = Python:** `data_cleaning.py` recomputes the headline numbers from raw CSVs and fails if they differ from `reports/tables/sql_headline_numbers.csv`. If you add a headline metric, add it to both `99_export_tables.sql` and the validation cell.
3. **Python scripts** must run top to bottom without errors; every section = question → code → one-sentence finding with a number.
4. **Charts:** title states a verified finding; axis labels with units; no dual-axis charts; "late" is always orange `#eb6834`, the main series blue `#2a78d6`.
5. **Statistics:** report effect size and confidence intervals, not only p-values. **No causal language** ("causes", "leads to", "drives") for associations.
6. **Never commit** `data/raw/*.csv`, generated `reports/tables/*.csv`, credentials, tokens or `.env` files.
7. Do not copy insights from Kaggle notebooks or other analyses — every finding must come from this code.

## Git workflow
- Work on a branch (`feature/<short-name>` or `fix/<short-name>`), never commit directly to `main`.
- Small commits with clear messages; open a pull request; CI must be green before merging.
- In the PR description: which question IDs are affected and whether any headline number changed (old → new).

## Question IDs
Revenue R1–R5 · Retention C1–C5 · Delivery D1–D5 · Satisfaction S1–S4 (full list: `Documentation/business_questions.md`).
