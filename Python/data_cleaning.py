# %% [markdown]
# # Очищення даних і валідація SQL
# **Відповідає на:** перевірки якості даних (P1 - Data Quality Report) і валідацію результатів SQL
# **Вхідні дані:** сирі CSV Olist у `data/raw/` - навмисно *не* представлення PostgreSQL, тож це незалежний другий розрахунок
# **Результат:** `reports/tables/orders_clean.csv`, `reports/tables/items_clean.csv` (використовуються скриптами RFM і статистичного аналізу) та таблиця валідації
#
# **Визначення** (ідентичні до `SQL/01_analytics_views.sql`):
#
# | Термін | Визначення |
# | --- | --- |
# | Замовлення | замовлення з `order_status = 'delivered'` |
# | Виручка | `price + freight_value`, підсумовані за позиціями замовлення |
# | AOV | виручка / замовлення |
# | Клієнт | `customer_unique_id` |
# | KPI-період | місяць покупки 2017-01 .. 2018-08 |
# | Дні доставки | час доставки клієнту мінус час покупки, у дробових днях |
# | Запізнення | **дата** доставки > очікувана **дата** доставки |
# | Оцінка відгуку | останній відгук на замовлення (за часом відповіді) |

# %%
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent  # корінь репозиторію, щоб скрипт запускався з будь-якої робочої директорії

pd.set_option("display.max_columns", 50)
pd.set_option("display.width", 160)
pd.set_option("display.float_format", "{:,.3f}".format)

RAW = ROOT / "data" / "raw"
TABLES = ROOT / "reports" / "tables"
FIGS = ROOT / "reports" / "figures"
TABLES.mkdir(parents=True, exist_ok=True)
FIGS.mkdir(parents=True, exist_ok=True)

# %% [markdown]
# ## A1. Завантаження всіх таблиць
# **Питання:** чи збігаються розміри таблиць із кількістю рядків, завантажених у PostgreSQL?

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
# id - це мітки, а не числа -> читаємо їх як рядки (зберігає початкові нулі в поштових префіксах)
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
# **Висновок:** Усі 8 таблиць завантажуються з точно очікуваною кількістю рядків і стовпців (orders 99,441 · items 112,650 · customers 99,441 · products 32,951 · sellers 3,095 · payments 103,886 · reviews 99,224 · translations 71).

# %% [markdown]
# ## A2. Перетворення дат і часу
# **Питання:** скільки значень стають `NaT` після `pd.to_datetime(errors='coerce')`? `coerce` мовчки перетворює некоректні рядки на `NaT`, тому кількість нових `NaT` треба порівняти з кількістю порожніх значень до перетворення.

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
# Чи буває в очікуваній даті доставки часова частина? (визначає порівняння на рівні DATE чи TIMESTAMP)
est = dfs["orders"]["order_estimated_delivery_date"]
print("estimated dates with a time other than 00:00:00:", (est != est.dt.normalize()).sum())

# %% [markdown]
# **Висновок:** Усі рядки з датами успішно розпарсено: кожен NaT уже був порожнім полем. `order_estimated_delivery_date` завжди має час 00:00:00, тож на практиці це дата - запізнення порівнюється на рівні DATE.

# %% [markdown]
# ## A3. Пропущені значення
# **Питання:** у яких стовпцях є пропущені значення і чи очікувані вони?

# %%
missing = []
for name, df in dfs.items():
    na = df.isna().sum()
    for col, n in na[na > 0].items():
        missing.append({"table": name, "column": col, "missing": n, "missing_pct": 100 * n / len(df)})
missing = pd.DataFrame(missing).sort_values(["table", "missing"], ascending=[True, False])
print(missing)

# %%
# Чи пояснюються пропущені дати доставки статусом замовлення?
o = dfs["orders"]
print((o.assign(no_customer_delivery=o["order_delivered_customer_date"].isna())
   .groupby("order_status")["no_customer_delivery"].agg(["size", "sum"])
   .rename(columns={"size": "orders", "sum": "without_delivery_date"})
   .sort_values("orders", ascending=False)))

# %% [markdown]
# **Висновок:** Пропущені дати доставки пояснюються статусом замовлення: лише 8 із 96,478 доставлених замовлень не мають дати доставки клієнту. 610 товарів (1.9%) не мають категорії -> позначаються як 'unknown'. Коментарі до відгуків здебільшого порожні (59% без повідомлення) і не використовуються.

# %% [markdown]
# ## A4. Дублікати
# **Питання:** чи є точні дублікати рядків або дублікати ключів?

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
# review_id не унікальний: як виглядають дубльовані review_id?
r = dfs["reviews"]
dup_ids = r[r["review_id"].duplicated(keep=False)]
print("rows with a duplicated review_id:", len(dup_ids))
print("distinct review_ids among them:", dup_ids["review_id"].nunique())
print("same review_id, different order_id:",
      (dup_ids.groupby("review_id")["order_id"].nunique() > 1).sum())

# %% [markdown]
# **Висновок:** Немає ні точних дублікатів рядків, ні дублікатів ключів - крім `review_id`: 789 id відгуків трапляються у двох різних замовленнях (1,603 рядки). Тому `review_id` не використовується як ключ; відгуки прив'язуються до замовлень через `order_id`.

# %% [markdown]
# ## A5. Узгодженість часових міток
# **Питання:** скільки доставлених замовлень порушують порядок покупка <= підтвердження <= передача перевізнику <= доставка клієнту?

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
# **Висновок:** Жодне доставлене замовлення не прибуває раніше, ніж його купили, тож загальний час доставки завжди коректний. Проміжні часові мітки менш надійні (165 замовлень передано перевізнику до покупки, 1,350 - до підтвердження, 23 доставлено ще до того, як їх забрав перевізник) -> аналіз використовує лише інтервал покупка -> доставка клієнту, без розбиття на етапи продавця/перевізника.

# %% [markdown]
# ## A6. Викиди в тривалості доставки
# **Питання:** якими є медіана, p90, p99 та екстремальні значення?

# %%
delivery_days = (d["order_delivered_customer_date"] - d["order_purchase_timestamp"]).dt.total_seconds() / 86400
print(delivery_days.describe(percentiles=[.5, .9, .99]).round(2))
print("orders taking more than 60 days:", (delivery_days > 60).sum())

# %% [markdown]
# **Висновок:** Медіана доставки 10.2 дня, p90 23.1, p99 46.1, максимум 209.6. 306 замовлень доставлялися понад 60 днів. Їх залишено: це правдоподібні доставки з довгого хвоста, а не неможливі значення, і медіана/p90 стійкі до них.

# %% [markdown]
# ## A7. Кілька відгуків на одне замовлення
# **Питання:** скільки замовлень мають більше одного відгуку? **Правило:** залишаємо останній відгук (за `review_answer_timestamp`, потім `review_creation_date`, потім `review_id`) - те саме правило, що й у SQL-представленні.

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
# **Висновок:** 547 замовлень мають більше одного відгуку, і у 202 з них оцінки різні, тож правило має значення. Після залишення останнього відгуку 98,673 замовлення мають рівно один відгук.

# %% [markdown]
# ## A8. Відгуки, написані до прибуття замовлення
# **Питання:** скільки відгуків створено до фактичної дати доставки? Такий відгук не може описувати доставлений товар - але може описувати очікування.

# %%
rv = d[["order_id", "order_delivered_customer_date", "order_estimated_delivery_date"]].merge(last_review, on="order_id")
rv["review_before_delivery"] = rv["review_creation_date"] < rv["order_delivered_customer_date"].dt.normalize()
rv["is_late"] = rv["order_delivered_customer_date"].dt.normalize() > rv["order_estimated_delivery_date"].dt.normalize()
print("reviews created before delivery:", rv["review_before_delivery"].sum())
print(rv.groupby("is_late")["review_before_delivery"].agg(["size", "sum", "mean"]).rename(
    columns={"size": "reviews", "sum": "before_delivery", "mean": "share"}))

# %% [markdown]
# **Висновок:** 4,976 відгуків написано до прибуття замовлення - і майже всі вони стосуються запізнілих замовлень: 74.5% відгуків на запізнілі замовлення (4,751 з 6,381) проти 0.3% на вчасні. Для запізнілих замовлень відгук здебільшого є реакцією на очікування. Це перевіряється як аналіз чутливості в `statistical_analysis.py` (C4).

# %% [markdown]
# ## A9. Очищені таблиці на рівні замовлень і позицій із прапорцями
# Усі доставлені замовлення залишено; прапорці роблять кожен фільтр видимим і зворотним.

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

# рівень позицій з англійськими назвами категорій (неперекладені назви залишаються, порожні -> 'unknown')
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

# рядки, виключені з кожного аналізу
print(pd.Series({
    "all orders": len(o),
    "excluded: not delivered": (o["order_status"] != "delivered").sum(),
    "delivered orders": len(orders_clean),
    "delivered, outside KPI period": (~orders_clean["in_kpi_period"]).sum(),
    "delivered, no delivery date": (~orders_clean["has_delivery_date"]).sum(),
    "delivered, no review": orders_clean["review_score"].isna().sum(),
}, name="orders").to_frame())

# %% [markdown]
# ## B. Валідація: SQL проти Python
# **Питання:** чи збігаються ключові показники, розраховані в PostgreSQL (`reports/tables/sql_headline_numbers.csv`, створюється `SQL/99_export_tables.sql`), з показниками, розрахованими тут із сирих CSV?

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
    "median_delivery_days": dlv["delivery_days"].median(),        # лінійна інтерполяція = PERCENTILE_CONT
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
# Щомісячні KPI: порівнюємо кожен місяць, а не лише підсумки
sql_monthly_file = TABLES / "monthly_kpis.csv"
if sql_monthly_file.exists():
    sql_monthly = pd.read_csv(sql_monthly_file, parse_dates=["month"]).set_index("month")
    py_monthly = kpi.groupby("purchase_month").agg(orders=("order_id", "nunique"), revenue=("revenue", "sum"))
    cmp = py_monthly.join(sql_monthly, lsuffix="_python", rsuffix="_sql")
    print("months compared:", len(cmp))
    print("months where orders differ:", (cmp["orders_python"] != cmp["orders_sql"]).sum())
    print("max absolute revenue difference:", (cmp["revenue_python"] - cmp["revenue_sql"]).abs().max().round(4))

# %% [markdown]
# ## Контрольна перевірка валідації
# Ця комірка зупиняє скрипт (і запуск CI) з помилкою, якщо будь-яке число з SQL відрізняється від числа з Python.

# %%
if "match" in validation.columns:
    mismatches = validation[~validation["match"]]
    assert mismatches.empty, f"SQL and Python disagree:\n{mismatches}"
    print(f"validation passed: all {len(validation)} metrics match")
else:
    print("SQL exports not found - validation skipped")

# %% [markdown]
# ## Підсумок
#
# - Сирі дані структурно коректні: кількості збігаються, немає дат, що не розпізнаються, немає дублікатів ключів, крім повторно використаних `review_id`.
# - Виключення: 2,963 недоставлених замовлення (усі аналізи), 267 доставлених замовлень поза 2017-01..2018-08 (щомісячні KPI і доставка), 8 доставлених замовлень без дати доставки (доставка), 646 доставлених замовлень без відгуку (аналіз відгуків).
# - **Валідацію пройдено:** усі 11 ключових показників (замовлення 96,211 · виручка R$ 15,377,809.91 · AOV R$ 159.83 · клієнти 93,358 · повторні клієнти 2,801 · частка повторних клієнтів 3.00% · виручка топ-категорії · вчасно 93.21% · медіана 10.21 дня · p90 23.06 дня · виручка за листопад 2017) та всі 20 щомісячних кількостей замовлень і значень виручки ідентичні в PostgreSQL і в цьому незалежному розрахунку на Pandas.
