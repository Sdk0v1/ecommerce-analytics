# %% [markdown]
# # Data Cleaning & SQL Validation
# **Answers:** data-quality checks (P1 - Data Quality Report) and validation of the SQL results
# **Input:** the raw Olist CSVs in `data/raw/` - on purpose *not* the PostgreSQL views, so this is an independent second calculation
# **Output:** `reports/tables/orders_clean.csv`, `reports/tables/items_clean.csv` (used by the RFM and statistics scripts) and the validation table
#
# **Definitions** (identical to `SQL/01_analytics_views.sql`):
#
# | Term | Definition |
# | --- | --- |
# | Order | order with `order_status = 'delivered'` |
# | Revenue | `price + freight_value` summed over the order's items |
# | AOV | revenue / orders |
# | Customer | `customer_unique_id` |
# | KPI period | purchase month 2017-01 .. 2018-08 |
# | Delivery days | delivered-to-customer minus purchase timestamp, in fractional days |
# | Late | delivered **date** > estimated delivery **date** |
# | Review score | latest review of the order (by answer timestamp) |

# %%
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent  # repository root, so the script runs from any working directory

pd.set_option("display.max_columns", 50)
pd.set_option("display.width", 160)
pd.set_option("display.float_format", "{:,.3f}".format)

RAW = ROOT / "data" / "raw"
TABLES = ROOT / "reports" / "tables"
FIGS = ROOT / "reports" / "figures"
TABLES.mkdir(parents=True, exist_ok=True)
FIGS.mkdir(parents=True, exist_ok=True)

# %% [markdown]
# ## A1. Load all tables
# **Question:** do the shapes match the row counts loaded into PostgreSQL?

# %%
FILES = {
    "orders":               "olist_orders_dataset.csv",
    "order_items":          "olist_order_items_dataset.csv",
    "customers":            "olist_customers_dataset.csv",
    "products":             "olist_products_dataset.csv",
    "sellers":              "olist_sellers_dataset.csv",
    "payments":             "olist_order_payments_dataset.csv",
    "reviews":              "olist_order_reviews_dataset.csv",
    "category_translation": "product_category_name_translation.csv",
}
# ids are labels, not numbers -> read them as strings (keeps leading zeros in zip prefixes)
ID_COLS = ["order_id", "customer_id", "customer_unique_id", "product_id", "seller_id",
           "review_id", "customer_zip_code_prefix", "seller_zip_code_prefix"]

dfs = {}
for name, file in FILES.items():
    dfs[name] = pd.read_csv(RAW / file, dtype={c: "string" for c in ID_COLS})

EXPECTED = {"orders": 99441, "order_items": 112650, "customers": 99441, "products": 32951,
            "sellers": 3095, "payments": 103886, "reviews": 99224, "category_translation": 71}
shapes = pd.DataFrame({
    "rows": {k: len(v) for k, v in dfs.items()},
    "columns": {k: v.shape[1] for k, v in dfs.items()},
    "expected_rows": EXPECTED,
})
shapes["match"] = shapes["rows"] == shapes["expected_rows"]
print(shapes)

# %% [markdown]
# **Finding:** All 8 tables load with exactly the expected number of rows and columns (orders 99,441 · items 112,650 · customers 99,441 · products 32,951 · sellers 3,095 · payments 103,886 · reviews 99,224 · translations 71).

# %% [markdown]
# ## A2. Datetime conversion
# **Question:** how many values become `NaT` after `pd.to_datetime(errors='coerce')`? `coerce` silently turns bad strings into `NaT`, so the count of new `NaT`s must be compared with the count of empty strings before conversion.

# %%
DATE_COLS = {
    "orders": ["order_purchase_timestamp", "order_approved_at", "order_delivered_carrier_date",
               "order_delivered_customer_date", "order_estimated_delivery_date"],
    "order_items": ["shipping_limit_date"],
    "reviews": ["review_creation_date", "review_answer_timestamp"],
}
rows = []
for table, cols in DATE_COLS.items():
    for col in cols:
        missing_before = dfs[table][col].isna().sum()
        dfs[table][col] = pd.to_datetime(dfs[table][col], errors="coerce")
        missing_after = dfs[table][col].isna().sum()
        rows.append({"table": table, "column": col, "empty_before": missing_before,
                     "NaT_after": missing_after, "unparseable": missing_after - missing_before,
                     "min": dfs[table][col].min(), "max": dfs[table][col].max()})
print(pd.DataFrame(rows))

# %%
# Does the estimated delivery date ever have a time part? (decides DATE vs TIMESTAMP comparison)
est = dfs["orders"]["order_estimated_delivery_date"]
print("estimated dates with a time other than 00:00:00:", (est != est.dt.normalize()).sum())

# %% [markdown]
# **Finding:** No date string failed to parse: every NaT was already an empty field. `order_estimated_delivery_date` always has time 00:00:00, so it is a date in practice - lateness is compared on the DATE level.

# %% [markdown]
# ## A3. Missing values
# **Question:** which columns have missing values, and are they expected?

# %%
missing = []
for name, df in dfs.items():
    na = df.isna().sum()
    for col, n in na[na > 0].items():
        missing.append({"table": name, "column": col, "missing": n, "missing_pct": 100 * n / len(df)})
missing = pd.DataFrame(missing).sort_values(["table", "missing"], ascending=[True, False])
print(missing)

# %%
# Are missing delivery dates explained by the order status?
o = dfs["orders"]
print((o.assign(no_customer_delivery=o["order_delivered_customer_date"].isna())
   .groupby("order_status")["no_customer_delivery"].agg(["size", "sum"])
   .rename(columns={"size": "orders", "sum": "without_delivery_date"})
   .sort_values("orders", ascending=False)))

# %% [markdown]
# **Finding:** Missing delivery dates are explained by the order status: only 8 of 96,478 delivered orders lack a customer delivery date. 610 products (1.9%) have no category -> reported as 'unknown'. Review comments are mostly empty (59% without a message) and are not used.

# %% [markdown]
# ## A4. Duplicates
# **Question:** are there exact duplicate rows or duplicate keys?

# %%
KEYS = {
    "orders": ["order_id"], "order_items": ["order_id", "order_item_id"], "customers": ["customer_id"],
    "products": ["product_id"], "sellers": ["seller_id"], "payments": ["order_id", "payment_sequential"],
    "reviews": ["review_id"], "category_translation": ["product_category_name"],
}
print(pd.DataFrame({
    "exact_duplicate_rows": {k: dfs[k].duplicated().sum() for k in KEYS},
    "duplicate_keys": {k: dfs[k].duplicated(subset=v).sum() for k, v in KEYS.items()},
    "key": {k: ", ".join(v) for k, v in KEYS.items()},
}))

# %%
# review_id is not unique: what do the duplicated review_ids look like?
r = dfs["reviews"]
dup_ids = r[r["review_id"].duplicated(keep=False)]
print("rows with a duplicated review_id:", len(dup_ids))
print("distinct review_ids among them:", dup_ids["review_id"].nunique())
print("same review_id, different order_id:",
      (dup_ids.groupby("review_id")["order_id"].nunique() > 1).sum())

# %% [markdown]
# **Finding:** No exact duplicate rows and no duplicate keys - except `review_id`: 789 review ids appear on two different orders (1,603 rows). `review_id` is therefore not used as a key; reviews are attached to orders by `order_id`.

# %% [markdown]
# ## A5. Timestamp consistency
# **Question:** how many delivered orders violate purchase <= approved <= carrier <= customer delivery?

# %%
d = dfs["orders"].query("order_status == 'delivered'")
checks = {
    "approved before purchase":             (d["order_approved_at"] < d["order_purchase_timestamp"]).sum(),
    "carrier before purchase":              (d["order_delivered_carrier_date"] < d["order_purchase_timestamp"]).sum(),
    "carrier before approval":              (d["order_delivered_carrier_date"] < d["order_approved_at"]).sum(),
    "customer delivery before carrier":     (d["order_delivered_customer_date"] < d["order_delivered_carrier_date"]).sum(),
    "customer delivery before purchase":    (d["order_delivered_customer_date"] < d["order_purchase_timestamp"]).sum(),
    "delivered but no customer date":       d["order_delivered_customer_date"].isna().sum(),
}
print(pd.Series(checks, name="delivered_orders_affected").to_frame())

# %% [markdown]
# **Finding:** No delivered order arrives before it was bought, so total delivery time is always valid. Intermediate timestamps are less reliable (165 orders handed to the carrier before purchase, 1,350 before approval, 23 delivered before carrier pickup) -> the analysis uses only purchase -> customer delivery, not the seller/carrier split.

# %% [markdown]
# ## A6. Delivery duration outliers
# **Question:** what do the median, p90, p99 and extreme values look like?

# %%
delivery_days = (d["order_delivered_customer_date"] - d["order_purchase_timestamp"]).dt.total_seconds() / 86400
print(delivery_days.describe(percentiles=[.5, .9, .99]).round(2))
print("orders taking more than 60 days:", (delivery_days > 60).sum())

# %% [markdown]
# **Finding:** Median delivery 10.2 days, p90 23.1, p99 46.1, max 209.6. 306 orders took more than 60 days. They are kept: they are plausible long-tail deliveries, not impossible values, and the median/p90 are robust to them.

# %% [markdown]
# ## A7. Multiple reviews per order
# **Question:** how many orders have more than one review? **Rule:** keep the latest review (by `review_answer_timestamp`, then `review_creation_date`, then `review_id`) - the same rule as the SQL view.

# %%
reviews_per_order = dfs["reviews"].groupby("order_id").size()
print("orders with > 1 review:", (reviews_per_order > 1).sum())

multi = dfs["reviews"][dfs["reviews"]["order_id"].isin(reviews_per_order[reviews_per_order > 1].index)]
print("of those, orders whose reviews have different scores:",
      (multi.groupby("order_id")["review_score"].nunique() > 1).sum())

last_review = (dfs["reviews"]
               .sort_values(["order_id", "review_answer_timestamp", "review_creation_date", "review_id"],
                            ascending=[True, False, False, True])
               .drop_duplicates("order_id", keep="first")
               [["order_id", "review_score", "review_creation_date"]])
print("orders with a review after applying the rule:", len(last_review))

# %% [markdown]
# **Finding:** 547 orders have more than one review and 202 of them have different scores, so the rule matters. After keeping the latest review, 98,673 orders have exactly one review.

# %% [markdown]
# ## A8. Reviews written before the order arrived
# **Question:** how many reviews were created before the actual delivery date? Such a review cannot describe the delivered product - but it can describe the waiting.

# %%
rv = d[["order_id", "order_delivered_customer_date", "order_estimated_delivery_date"]].merge(last_review, on="order_id")
rv["review_before_delivery"] = rv["review_creation_date"] < rv["order_delivered_customer_date"].dt.normalize()
rv["is_late"] = rv["order_delivered_customer_date"].dt.normalize() > rv["order_estimated_delivery_date"].dt.normalize()
print("reviews created before delivery:", rv["review_before_delivery"].sum())
print(rv.groupby("is_late")["review_before_delivery"].agg(["size", "sum", "mean"]).rename(
    columns={"size": "reviews", "sum": "before_delivery", "mean": "share"}))

# %% [markdown]
# **Finding:** 4,976 reviews were written before the order arrived - and almost all of them belong to late orders: 74.5% of late orders' reviews (4,751 of 6,381) vs 0.3% of on-time ones. For late orders the review is mostly a reaction to the waiting. This is tested as a sensitivity check in `statistical_analysis.py` (C4).

# %% [markdown]
# ## A9. Clean order-level and item-level tables with flags
# All delivered orders are kept; flags make every filter visible and reversible.

# %%
o, c, it, p = dfs["orders"], dfs["customers"], dfs["order_items"], dfs["payments"]

items_per_order = (it.assign(item_revenue=it["price"] + it["freight_value"])
                     .groupby("order_id")
                     .agg(n_items=("order_item_id", "size"), product_value=("price", "sum"),
                          freight_value=("freight_value", "sum"), revenue=("item_revenue", "sum")))
main_payment = (p.sort_values(["order_id", "payment_value", "payment_sequential"], ascending=[True, False, True])
                 .drop_duplicates("order_id")[["order_id", "payment_type"]]
                 .rename(columns={"payment_type": "main_payment_type"}))

orders_clean = (o.query("order_status == 'delivered'")
                 .merge(c[["customer_id", "customer_unique_id", "customer_state"]], on="customer_id", how="left")
                 .merge(items_per_order, on="order_id", how="inner")
                 .merge(main_payment, on="order_id", how="left")
                 .merge(last_review, on="order_id", how="left"))

orders_clean["purchase_date"] = orders_clean["order_purchase_timestamp"].dt.normalize()
orders_clean["purchase_month"] = orders_clean["order_purchase_timestamp"].dt.to_period("M").dt.to_timestamp()
orders_clean["in_kpi_period"] = orders_clean["purchase_month"].between("2017-01-01", "2018-08-01")
orders_clean["has_delivery_date"] = orders_clean["order_delivered_customer_date"].notna()
orders_clean["delivery_days"] = (orders_clean["order_delivered_customer_date"]
                                 - orders_clean["order_purchase_timestamp"]).dt.total_seconds() / 86400
orders_clean["estimated_days"] = (orders_clean["order_estimated_delivery_date"]
                                  - orders_clean["order_purchase_timestamp"]).dt.total_seconds() / 86400
orders_clean["delay_days"] = (orders_clean["order_delivered_customer_date"].dt.normalize()
                              - orders_clean["order_estimated_delivery_date"].dt.normalize()).dt.days
orders_clean["is_late"] = np.where(orders_clean["has_delivery_date"],
                                   (orders_clean["delay_days"] > 0).astype(float), np.nan)
orders_clean["review_before_delivery"] = (orders_clean["review_creation_date"]
                                          < orders_clean["order_delivered_customer_date"].dt.normalize())

KEEP = ["order_id", "customer_unique_id", "customer_state", "order_purchase_timestamp", "purchase_date",
        "purchase_month", "in_kpi_period", "n_items", "product_value", "freight_value", "revenue",
        "main_payment_type", "has_delivery_date", "delivery_days", "estimated_days", "delay_days",
        "is_late", "review_score", "review_before_delivery"]
orders_clean = orders_clean[KEEP]
print(orders_clean.shape, "| duplicated order_id:", orders_clean["order_id"].duplicated().sum())

# item level with English category names (untranslated names kept, empty -> 'unknown')
pr, tr = dfs["products"], dfs["category_translation"]
items_clean = (it.merge(pr[["product_id", "product_category_name"]], on="product_id", how="left")
                 .merge(tr, on="product_category_name", how="left"))
items_clean["category"] = (items_clean["product_category_name_english"]
                           .fillna(items_clean["product_category_name"]).fillna("unknown"))
items_clean["item_revenue"] = items_clean["price"] + items_clean["freight_value"]
items_clean = items_clean.merge(orders_clean[["order_id", "customer_unique_id", "customer_state",
                                              "purchase_month", "in_kpi_period"]], on="order_id", how="inner")
items_clean = items_clean[["order_id", "order_item_id", "product_id", "seller_id", "category", "price",
                           "freight_value", "item_revenue", "customer_unique_id", "customer_state",
                           "purchase_month", "in_kpi_period"]]
print(items_clean.shape)

orders_clean.to_csv(TABLES / "orders_clean.csv", index=False)
items_clean.to_csv(TABLES / "items_clean.csv", index=False)

# rows excluded from each analysis
print(pd.Series({
    "all orders": len(o),
    "excluded: not delivered": (o["order_status"] != "delivered").sum(),
    "delivered orders": len(orders_clean),
    "delivered, outside KPI period": (~orders_clean["in_kpi_period"]).sum(),
    "delivered, no delivery date": (~orders_clean["has_delivery_date"]).sum(),
    "delivered, no review": orders_clean["review_score"].isna().sum(),
}, name="orders").to_frame())

# %% [markdown]
# ## B. Validation: SQL vs Python
# **Question:** do the headline numbers calculated in PostgreSQL (`reports/tables/sql_headline_numbers.csv`, written by `SQL/99_export_tables.sql`) match the numbers calculated here from the raw CSVs?

# %%
kpi = orders_clean[orders_clean["in_kpi_period"]]
dlv = kpi[kpi["has_delivery_date"]]
per_customer = orders_clean.groupby("customer_unique_id")["order_id"].nunique()

python_values = {
    "total_orders":         kpi["order_id"].nunique(),
    "total_revenue":        kpi["revenue"].sum(),
    "aov":                  kpi["revenue"].sum() / kpi["order_id"].nunique(),
    "total_customers":      orders_clean["customer_unique_id"].nunique(),
    "repeat_customers":     (per_customer >= 2).sum(),
    "repeat_rate_pct":      100 * (per_customer >= 2).mean(),
    "top_category_revenue": items_clean[items_clean["in_kpi_period"]].groupby("category")["item_revenue"].sum().max(),
    "on_time_pct":          100 * (1 - dlv["is_late"]).mean(),
    "median_delivery_days": dlv["delivery_days"].median(),        # linear interpolation = PERCENTILE_CONT
    "p90_delivery_days":    dlv["delivery_days"].quantile(0.9),
    "revenue_2017_11":      orders_clean.loc[orders_clean["purchase_month"] == "2017-11-01", "revenue"].sum(),
}

validation = pd.DataFrame({"python_value": python_values})
sql_file = TABLES / "sql_headline_numbers.csv"
if sql_file.exists():
    sql_values = pd.read_csv(sql_file).set_index("metric")["sql_value"]
    validation["sql_value"] = sql_values
    validation["difference"] = validation["python_value"] - validation["sql_value"]
    validation["match"] = np.isclose(validation["python_value"], validation["sql_value"], rtol=0, atol=0.01)
else:
    print("Run SQL/99_export_tables.sql first to create", sql_file)
print(validation)

# %%
# Monthly KPIs: compare every month, not only the totals
sql_monthly_file = TABLES / "monthly_kpis.csv"
if sql_monthly_file.exists():
    sql_monthly = pd.read_csv(sql_monthly_file, parse_dates=["month"]).set_index("month")
    py_monthly = kpi.groupby("purchase_month").agg(orders=("order_id", "nunique"), revenue=("revenue", "sum"))
    cmp = py_monthly.join(sql_monthly, lsuffix="_python", rsuffix="_sql")
    print("months compared:", len(cmp))
    print("months where orders differ:", (cmp["orders_python"] != cmp["orders_sql"]).sum())
    print("max absolute revenue difference:", (cmp["revenue_python"] - cmp["revenue_sql"]).abs().max().round(4))

# %% [markdown]
# ## Validation gate
# This cell stops the script (and the CI run) with an error if any SQL number differs from the Python number.

# %%
if "match" in validation.columns:
    mismatches = validation[~validation["match"]]
    assert mismatches.empty, f"SQL and Python disagree:\n{mismatches}"
    print(f"validation passed: all {len(validation)} metrics match")
else:
    print("SQL exports not found - validation skipped")

# %% [markdown]
# ## Summary
#
# - The raw data is structurally sound: counts match, no unparseable dates, no duplicate keys except the reused `review_id`s.
# - Exclusions: 2,963 non-delivered orders (all analyses), 267 delivered orders outside 2017-01..2018-08 (monthly KPIs and delivery), 8 delivered orders without a delivery date (delivery), 646 delivered orders without a review (review analysis).
# - **Validation passed:** all 11 headline numbers (orders 96,211 · revenue R$ 15,377,809.91 · AOV R$ 159.83 · customers 93,358 · repeat customers 2,801 · repeat rate 3.00% · top-category revenue · on-time 93.21% · median 10.21 days · p90 23.06 days · Nov-2017 revenue) and all 20 monthly order counts and revenues are identical in PostgreSQL and in this independent Pandas calculation.
