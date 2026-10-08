# %% [markdown]
# # RFM-сегментація
# **Відповідає на:** C5 (і підтримує C1-C4) · Нотатки: P3 - RFM-сегментація
# **Вхідні дані:** `reports/tables/orders_clean.csv` (з `data_cleaning.py`)
#
# | Метрика | Визначення |
# | --- | --- |
# | Recency | кількість днів від останнього доставленого замовлення клієнта до опорної дати |
# | Frequency | кількість доставлених замовлень |
# | Monetary | загальний дохід (ціна + доставка) з доставлених замовлень клієнта |
# | Опорна дата | наступний день після останньої покупки в даних (дані історичні - "сьогодні" зробило б кожного клієнта схожим на втраченого) |

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

# %%
# Стиль графіків: ненав'язлива сітка/осі, тонкі позначки, текст нейтральним кольором (ніколи кольором серії)
BLUE, ORANGE = "#2a78d6", "#eb6834"      # вчасно / основна серія = синій, із запізненням = помаранчевий (перевірена пара)
INK, INK2, GRID = "#0b0b0b", "#52514e", "#e5e4e0"
plt.rcParams.update({
    "figure.dpi": 110, "savefig.dpi": 200, "figure.facecolor": "white",
    "axes.edgecolor": GRID, "axes.labelcolor": INK2, "axes.titlecolor": INK,
    "axes.titlesize": 12, "axes.titleweight": "bold", "axes.titlelocation": "left",
    "axes.grid": True, "grid.color": GRID, "grid.linewidth": 0.8,
    "axes.spines.top": False, "axes.spines.right": False,
    "xtick.color": INK2, "ytick.color": INK2, "legend.frameon": False,
    "font.size": 10,
})

def save(fig, name):
    fig.savefig(FIGS / name, bbox_inches="tight")
    print("saved", FIGS / name)
    plt.close(fig)

# %% [markdown]
# ## 1. Побудова таблиці RFM
# Один рядок на `customer_unique_id`, уся історія замовлень (2016-09 .. 2018-08).

# %%
orders = pd.read_csv(TABLES / "orders_clean.csv", parse_dates=["purchase_date", "purchase_month"])

REFERENCE_DATE = orders["purchase_date"].max() + pd.Timedelta(days=1)
print("reference date:", REFERENCE_DATE.date())

rfm = (orders.groupby("customer_unique_id")
             .agg(last_purchase=("purchase_date", "max"),
                  frequency=("order_id", "nunique"),
                  monetary=("revenue", "sum")))
rfm["recency"] = (REFERENCE_DATE - rfm["last_purchase"]).dt.days
rfm = rfm[["recency", "frequency", "monetary"]]
print(rfm.shape)
print(rfm.head())

# %% [markdown]
# ## 2. Розподіли
# **Питання:** який вигляд мають R, F і M? Яка частка клієнтів має F = 1, 2, 3+?

# %%
print(rfm.describe(percentiles=[.2, .4, .5, .6, .8, .9]).T)

# %%
f_dist = rfm["frequency"].clip(upper=3).map({1: "1", 2: "2", 3: "3+"}).value_counts().sort_index()
print(pd.DataFrame({"customers": f_dist, "pct": 100 * f_dist / f_dist.sum()}))

# %%
# Чому квінтилі не працюють для Frequency: межі квінтилів збігаються в одне значення
print("F quintile edges:", rfm["frequency"].quantile([0, .2, .4, .6, .8, 1]).tolist())
try:
    pd.qcut(rfm["frequency"], 5)
except ValueError as e:
    print("pd.qcut on frequency fails:", e)

# %%
fig, axes = plt.subplots(1, 2, figsize=(11, 3.6))
axes[0].hist(rfm["recency"], bins=40, color=BLUE, edgecolor="white", linewidth=0.6)
axes[0].set_title("Recency is spread evenly across the 2 years")
axes[0].set_xlabel("days since last order"); axes[0].set_ylabel("customers")
axes[1].hist(np.log10(rfm["monetary"]), bins=40, color=BLUE, edgecolor="white", linewidth=0.6)
axes[1].set_title("Customer value is right-skewed")
axes[1].set_xlabel("total revenue per customer, R$ (log10 scale)"); axes[1].set_ylabel("customers")
ticks = [1, 2, 3, 4]
axes[1].set_xticks(ticks, [f"{10**t:,}" for t in ticks])
fig.tight_layout()
save(fig, "rfm_distributions.png")

# %% [markdown]
# **Висновок:** 97.0% клієнтів замовили один раз, 2.8% - двічі і 0.2% - три чи більше разів, тому Frequency не можна поділити на квінтилі (4 з 5 меж квінтилів дорівнюють 1). Monetary має правосторонню асиметрію (медіана R$ 107.79, максимум R$ 13,664); recency розподілена досить рівномірно протягом двох років.

# %% [markdown]
# ## 3. Метод оцінювання (рішення)
#
# | Метрика | Метод | Інтервали | Чому |
# | --- | --- | --- | --- |
# | R | квінтилі (`pd.qcut`, 5 = найнедавніші) | 20% клієнтів на кожну оцінку | recency має багато різних значень і немає природних бізнесових порогів |
# | F | **на основі правил** | 1 замовлення -> 1 · 2 замовлення -> 2 · 3+ замовлень -> 3 | квінтилі неможливі: переважна більшість клієнтів має рівно 1 замовлення (див. крок 2) |
# | M | квінтилі (`pd.qcut`, 5 = найвища цінність) | 20% клієнтів на кожну оцінку | асиметричний, але неперервний - квантилі стійкі до асиметрії |

# %%
R_LABELS = [5, 4, 3, 2, 1]          # низька recency (нещодавно) = найкраще
M_LABELS = [1, 2, 3, 4, 5]
F_BINS, F_LABELS = [0, 1, 2, np.inf], [1, 2, 3]

rfm["R"] = pd.qcut(rfm["recency"], 5, labels=R_LABELS).astype(int)
rfm["F"] = pd.cut(rfm["frequency"], bins=F_BINS, labels=F_LABELS).astype(int)
rfm["M"] = pd.qcut(rfm["monetary"], 5, labels=M_LABELS).astype(int)

# фактично використані пороги - видимі для документа з методології
print("R quintile edges (days):", rfm["recency"].quantile([.2, .4, .6, .8]).round(0).tolist())
print("M quintile edges (R$):  ", rfm["monetary"].quantile([.2, .4, .6, .8]).round(2).tolist())
print(rfm[["R", "F", "M"]].apply(pd.Series.value_counts).fillna(0).astype(int))

# %% [markdown]
# ## 4. Правила сегментації
# Оскільки більшість клієнтів купують один раз, єдиний сегмент "One-time Customers" охопив би майже всіх і не дав би маркетингу нічого для дій. Тому базу одноразових покупців поділено за **recency** та **цінністю** - двома чинниками, які визначають, чи варто запускати кампанію другої покупки.
#
# | Сегмент | Правило | Бізнесове значення | Можлива дія |
# | --- | --- | --- | --- |
# | Champions | F >= 2 і R >= 4 | купували більше одного разу, нещодавно | VIP-обслуговування, реферали, ранній доступ |
# | Loyal Customers | F >= 2 і R <= 3 | купували більше одного разу, але давно | повернення з персональною пропозицією |
# | Potential Loyalists | F = 1 і R >= 4 і M >= 4 | одне нещодавнє цінне перше замовлення | **головна ціль кампанії другої покупки** |
# | Recent One-time | F = 1 і R >= 4 і M <= 3 | одне нещодавнє менше перше замовлення | недороге нагадування (cross-sell email) |
# | At Risk | F = 1 і R у {2, 3} і M >= 4 | цінне перше замовлення, клієнт віддаляється | пропозиція реактивації, поки їх не втрачено |
# | One-time Lapsed | усі інші клієнти з F = 1 | давнє одиничне замовлення меншої цінності | без витрат; лише в дешевих масових каналах |
#
# Правила застосовуються згори донизу, тож кожен клієнт отримує рівно один сегмент.

# %%
def assign_segment(row):
    if row.F >= 2 and row.R >= 4:
        return "Champions"
    if row.F >= 2:
        return "Loyal Customers"
    if row.R >= 4 and row.M >= 4:
        return "Potential Loyalists"
    if row.R >= 4:
        return "Recent One-time"
    if row.R in (2, 3) and row.M >= 4:
        return "At Risk"
    return "One-time Lapsed"

SEGMENT_ORDER = ["Champions", "Loyal Customers", "Potential Loyalists",
                 "Recent One-time", "At Risk", "One-time Lapsed"]
rfm["segment"] = pd.Categorical(rfm.apply(assign_segment, axis=1), categories=SEGMENT_ORDER, ordered=True)

# перевірка повноти: кожен клієнт - рівно в одному сегменті
assert rfm["segment"].notna().all()
assert len(rfm) == orders["customer_unique_id"].nunique()
print("all", len(rfm), "customers have exactly one segment")

# %% [markdown]
# ## 5. Профіль сегментів
# **Питання:** який розмір кожного сегмента, скільки доходу він приносить і як він поводиться?

# %%
profile = (rfm.groupby("segment", observed=True)
              .agg(customers=("R", "size"), revenue=("monetary", "sum"),
                   avg_orders=("frequency", "mean"), avg_recency_days=("recency", "mean"),
                   avg_monetary=("monetary", "mean"),
                   repeat_rate=("frequency", lambda f: (f >= 2).mean())))
profile["pct_customers"] = 100 * profile["customers"] / profile["customers"].sum()
profile["pct_revenue"] = 100 * profile["revenue"] / profile["revenue"].sum()
profile["repeat_rate"] = 100 * profile["repeat_rate"]
profile = profile[["customers", "pct_customers", "revenue", "pct_revenue", "avg_orders",
                   "avg_recency_days", "avg_monetary", "repeat_rate"]]
print(profile.round(2))

# %%
# Концентрація доходу: яка частка доходу припадає на топ 10% / 20% клієнтів?
m_sorted = rfm["monetary"].sort_values(ascending=False)
for top in (0.1, 0.2):
    n = int(len(m_sorted) * top)
    print(f"top {int(top*100)}% of customers -> {100 * m_sorted.iloc[:n].sum() / m_sorted.sum():.1f}% of revenue")

# %%
# Чи відрізняються сегменти за місцем проживання клієнтів? (частка 3 найбільших штатів)
seg_state = orders.merge(rfm[["segment"]], left_on="customer_unique_id", right_index=True)
seg_state = seg_state.drop_duplicates("customer_unique_id")    # штат першого зазначеного замовлення клієнта
print((pd.crosstab(seg_state["segment"], seg_state["customer_state"], normalize="index")[["SP", "RJ", "MG"]] * 100).round(1))

# %% [markdown]
# ## 6. Графік: частка клієнтів проти частки доходу

# %%
fig, ax = plt.subplots(figsize=(9, 4))
y = np.arange(len(profile))
h = 0.38
ax.barh(y - h/2 - 0.01, profile["pct_customers"], height=h, color=BLUE, label="% of customers")
ax.barh(y + h/2 + 0.01, profile["pct_revenue"], height=h, color=ORANGE, label="% of revenue")
for yi, (c_, r_) in enumerate(zip(profile["pct_customers"], profile["pct_revenue"])):
    ax.text(c_ + 0.4, yi - h/2, f"{c_:.1f}%", va="center", fontsize=8, color=INK2)
    ax.text(r_ + 0.4, yi + h/2, f"{r_:.1f}%", va="center", fontsize=8, color=INK2)
ax.set_yticks(y, profile.index)
ax.invert_yaxis()
ax.set_xlabel("% of total")
ax.grid(axis="y", visible=False)
hv = profile.loc[["Potential Loyalists", "At Risk"]]
ax.set_title(f"High-value one-time buyers: {hv['pct_customers'].sum():.0f}% of customers, "
             f"{hv['pct_revenue'].sum():.0f}% of revenue")
ax.set_xlim(0, max(profile["pct_customers"].max(), profile["pct_revenue"].max()) * 1.15)
ax.legend(loc="upper right")
fig.tight_layout()
save(fig, "rfm_segments_customers_vs_revenue.png")

# %% [markdown]
# **Висновок:** Повторні покупці (Champions + Loyal Customers) становлять лише 3.0% клієнтів і 5.6% доходу. Цінні одноразові покупці (Potential Loyalists + At Risk) - це 30.3% клієнтів, але 54.8% доходу. Дохід сконцентрований: топ 20% клієнтів приносять 53.5% доходу. Розподіл сегментів за штатами схожий (SP 35-50% скрізь), тож географія їх не розділяє.

# %% [markdown]
# ## 7. Експорт для Power BI

# %%
rfm.reset_index().to_csv(TABLES / "rfm_segments.csv", index=False)
print("saved", TABLES / "rfm_segments.csv", rfm.shape)

# %% [markdown]
# ## Підсумок (C5)
#
# Класичний RFM **слабкий на цьому датасеті**, бо Frequency майже не змінюється - на практиці це **R x M сегментація** одноразових покупців плюс невелика група повторних. Це саме по собі висновок: у бізнесу майже немає лояльної бази для сегментації.
# Проте вона корисна для дій: 28,326 цінних одноразових клієнтів (Potential Loyalists 14,503 нещодавніх + At Risk 13,823 давніших) дають 54.8% доходу і є природною ціллю для кампанії другої покупки; 40,389 клієнтів One-time Lapsed мають найнижчий пріоритет.
# Обмеження: пороги сегментів - це квінтилі цього датасету, а не перевірені бізнесом значення; сегменти описують минулу поведінку і не прогнозують, хто купить знову.
