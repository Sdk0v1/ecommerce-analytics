# %% [markdown]
# # Статистичний аналіз
# **Відповідає на:** D3, D4, D5, S1-S4 · Нотатки: P3 - Статистичний аналіз
# **Вхідні дані:** `reports/tables/orders_clean.csv` (з `data_cleaning.py`)
# **Сукупність:** доставлені замовлення, оформлені 2017-01 .. 2018-08, з датою доставки (те саме, що `analytics.delivery_orders` у SQL)
# **Визначення:** запізнення = дата доставки > очікуваної дати · оцінка відгуку = найновіший відгук на замовлення

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
from scipy import stats

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

# %%
orders = pd.read_csv(TABLES / "orders_clean.csv", parse_dates=["purchase_month"])
dlv = orders[orders["in_kpi_period"] & orders["has_delivery_date"]].copy()
dlv["status"] = np.where(dlv["is_late"] == 1, "late", "on time")
rev = dlv.dropna(subset=["review_score"])
print("delivered orders:", len(dlv), "| with review:", len(rev))

rng = np.random.default_rng(42)
N_BOOT = 2000

# %% [markdown]
# ## Частина A - Час доставки
# ### A1. Розподіл
# **Питання:** яку форму має розподіл `delivery_days`?

# %%
x = dlv["delivery_days"].to_numpy()
summary = pd.Series({"n": len(x), "mean": x.mean(), "median": np.median(x),
                     "p90": np.percentile(x, 90), "p99": np.percentile(x, 99),
                     "max": x.max(), "skewness": stats.skew(x)})
print(summary.round(2))

# %%
med, p90 = np.median(x), np.percentile(x, 90)
fig, ax = plt.subplots(figsize=(9, 3.8))
ax.hist(np.clip(x, 0, 60), bins=60, color=BLUE, edgecolor="white", linewidth=0.5)
for v, lab in [(med, f"median {med:.1f} d"), (p90, f"p90 {p90:.1f} d")]:
    ax.axvline(v, color=INK, linewidth=1.2, linestyle="--")
    ax.text(v + 0.6, ax.get_ylim()[1] * 0.92, lab, color=INK, fontsize=9)
ax.set_xlabel("delivery time, days (orders over 60 days shown at 60)")
ax.set_ylabel("orders")
ax.set_title(f"Half of orders arrive within {med:.0f} days, but 1 in 10 takes over {p90:.0f} days")
fig.tight_layout()
save(fig, "del_delivery_days_hist.png")

# %% [markdown]
# **Висновок:** Час доставки має сильну правосторонню асиметрію (коефіцієнт асиметрії 3.85): середнє 12.5 дня проти медіани 10.2, p90 23.1, p99 46.0 дня (96,203 доставлених замовлень). Довгий хвіст тягне середнє вгору, тому правильні підсумкові показники - медіана та p90.

# %% [markdown]
# ### A2. Bootstrap CI для медіани та p90
# **Чому bootstrap:** час доставки має сильну правосторонню асиметрію, і для CI 90-го перцентиля немає простої формули. Bootstrap багато разів робить вибірки замовлень із поверненням і дивиться, наскільки змінюється статистика.

# %%
def bootstrap_ci(values, stat_fn, n_boot=N_BOOT, level=0.95, rng=rng):
    """Percentile bootstrap: resample with replacement, recompute the statistic, take the middle 95%."""
    values = np.asarray(values)
    boots = np.empty(n_boot)
    for i in range(n_boot):
        sample = rng.choice(values, size=len(values), replace=True)
        boots[i] = stat_fn(sample)
    alpha = (1 - level) / 2
    return stat_fn(values), np.quantile(boots, alpha), np.quantile(boots, 1 - alpha)

p90_fn = lambda v: np.percentile(v, 90)
ci_table = pd.DataFrame(
    [bootstrap_ci(x, np.median), bootstrap_ci(x, p90_fn)],
    index=["median delivery days", "p90 delivery days"], columns=["estimate", "ci_low", "ci_high"])
print(ci_table.round(2))

# %%
# Перехресна перевірка власного bootstrap реалізацією SciPy (лише медіана - її повільніше векторизувати)
res = stats.bootstrap((x,), np.median, n_resamples=1000, confidence_level=0.95,
                      method="percentile", batch=50, rng=np.random.default_rng(7))
print("SciPy percentile CI for the median:", np.round(res.confidence_interval, 2))

# %% [markdown]
# **Висновок:** Із 96k замовлень обидві оцінки точні: медіана 10.21 дня (95% CI 10.17-10.26), p90 23.06 дня (95% CI 22.93-23.17). Bootstrap від SciPy дає такий самий інтервал для медіани.

# %% [markdown]
# ### A3. Найгірші штати, з CI
# **Питання:** чи найповільніші штати явно відрізняються від загальнонаціонального значення, чи це може бути шум? (Штати з >= 300 доставленими замовленнями; 5 найвищих часток запізнень.)

# %%
state_stats = (dlv.groupby("customer_state")
                  .agg(orders=("order_id", "size"), late_rate=("is_late", "mean"))
                  .query("orders >= 300")
                  .sort_values("late_rate", ascending=False))
worst = state_stats.head(5).index

rows = []
for st in worst:
    v = dlv.loc[dlv["customer_state"] == st, "delivery_days"].to_numpy()
    m, m_lo, m_hi = bootstrap_ci(v, np.median, n_boot=1000)
    q, q_lo, q_hi = bootstrap_ci(v, p90_fn, n_boot=1000)
    rows.append({"state": st, "orders": len(v), "late_pct": 100 * state_stats.loc[st, "late_rate"],
                 "median": m, "median_ci": f"[{m_lo:.1f}, {m_hi:.1f}]",
                 "p90": q, "p90_ci": f"[{q_lo:.1f}, {q_hi:.1f}]"})
worst_table = pd.DataFrame(rows).set_index("state")
print(f"national: median {med:.1f} days, p90 {p90:.1f} days, late {100 * dlv['is_late'].mean():.1f}%")
print(worst_table.round(1))

# %% [markdown]
# **Висновок:** П'ять штатів із найвищою часткою запізнень (AL, MA, SE, PI, CE - усі на Північному Сході) мають і значно довшу доставку: медіана 16-22 дні та p90 30-40 днів проти 10.2 / 23.1 по країні. Кожен CI лежить значно вище загальнонаціонального значення, тож різниця - не шум вибірки.

# %% [markdown]
# ## Частина B - Оцінка відгуку: вчасно чи із запізненням
# ### B1. Описати перед тестуванням

# %%
def describe_scores(s):
    return pd.Series({"n": len(s), "mean": s.mean(), "median": s.median(),
                      "pct_1_2_stars": 100 * (s <= 2).mean(), "pct_5_stars": 100 * (s == 5).mean(),
                      "std": s.std()})

groups = rev.groupby("status")["review_score"].apply(describe_scores).unstack()
groups.loc["difference (late - on time)"] = groups.loc["late"] - groups.loc["on time"]
groups.loc["difference (late - on time)", "n"] = np.nan
print("S1 - all reviews: mean", round(rev["review_score"].mean(), 3), "| median", rev["review_score"].median())
print(groups.round(3))

# %%
dist = (pd.crosstab(rev["status"], rev["review_score"], normalize="index") * 100).loc[["on time", "late"]]
fig, ax = plt.subplots(figsize=(8.5, 3.8))
xs = np.arange(1, 6)
w = 0.38
ax.bar(xs - w/2 - 0.01, dist.loc["on time"], width=w, color=BLUE, label=f"on time (n={groups.loc['on time','n']:,.0f})")
ax.bar(xs + w/2 + 0.01, dist.loc["late"], width=w, color=ORANGE, label=f"late (n={groups.loc['late','n']:,.0f})")
ax.set_xticks(xs, [f"{i} star" + ("s" if i > 1 else "") for i in xs])
ax.set_ylabel("% of reviews in the group")
ax.grid(axis="x", visible=False)
ax.legend(loc="upper center")
ax.set_title(f"{dist.loc['late', 1]:.0f}% of late orders get 1 star vs {dist.loc['on time', 1]:.0f}% of on-time orders")
fig.tight_layout()
save(fig, "sat_review_distribution_on_time_vs_late.png")
print(dist.round(1))

# %% [markdown]
# ### B2. Характеристики даних -> вибір методу

# %%
late_s = rev.loc[rev["status"] == "late", "review_score"].to_numpy()
ontime_s = rev.loc[rev["status"] == "on time", "review_score"].to_numpy()
print(pd.Series({
    "distinct values of the outcome": rev["review_score"].nunique(),
    "n on time": len(ontime_s), "n late": len(late_s),
    "ratio of group sizes": len(ontime_s) / len(late_s),
    "std on time": ontime_s.std(ddof=1), "std late": late_s.std(ddof=1),
    "skewness on time": stats.skew(ontime_s), "skewness late": stats.skew(late_s),
    "customers with > 1 order in this population": (rev.groupby("customer_unique_id").size() > 1).sum(),
}).round(3))

# %% [markdown]
# | Характеристика | Що показують дані | Наслідок |
# | --- | --- | --- |
# | Шкала | 1-5 зірок, 5 різних значень -> **порядкова** | різницю середніх можна читати як "середні зірки", але медіани можуть лише перескакувати між цілими зірками |
# | Форма | оцінки вчасних замовлень скупчуються на 5 (лівостороння асиметрія); оцінки запізнілих - бімодальні (багато 1, частина 5) | припущення t-тесту про нормальність не виконується для окремих оцінок |
# | Розміри вибірок | десятки тисяч вчасних, тисячі запізнілих | велике n -> за центральною граничною теоремою **різниця середніх** розподілена ~нормально, хоча самі оцінки - ні |
# | Дисперсії | дуже різні між групами, розміри груп дуже нерівні | використовувати t-тест **Welch's**, ніколи не Стьюдента |
# | Незалежність | один рядок на замовлення; лише невелика кількість клієнтів має тут кілька замовлень | достатньо близько до незалежності - зазначено як припущення |
#
# **Методи:** T1 bootstrap CI для різниці середніх і T4 різниця у % відгуків з 1-2 зірками - **основні** результати (обидва в бізнесових одиницях). T2 Welch, T3 Mann-Whitney і T5 розміри ефекту - допоміжні перевірки.
# **Відгуки, написані до доставки,** залишено в основному аналізі (для запізнілих замовлень вони часто *і є* скаргою на очікування) і вилучено в перевірці чутливості (C4).

# %% [markdown]
# ### T1. Bootstrap 95% CI для різниці середньої оцінки (із запізненням - вчасно)

# %%
def bootstrap_diff(a, b, stat_fn=np.mean, n_boot=5000, rng=rng):
    """Resample each group separately, return the estimate and the percentile 95% CI of stat(a) - stat(b)."""
    a, b = np.asarray(a), np.asarray(b)
    boots = np.array([stat_fn(rng.choice(a, len(a))) - stat_fn(rng.choice(b, len(b))) for _ in range(n_boot)])
    return stat_fn(a) - stat_fn(b), np.quantile(boots, 0.025), np.quantile(boots, 0.975)

t1 = bootstrap_diff(late_s, ontime_s)
print(f"mean difference (late - on time): {t1[0]:.3f} stars, 95% CI [{t1[1]:.3f}, {t1[2]:.3f}]")

# %% [markdown]
# ### T2. Welch's t-test

# %%
t2 = stats.ttest_ind(late_s, ontime_s, equal_var=False)
ci_welch = t2.confidence_interval(confidence_level=0.95)
print(f"t = {t2.statistic:.2f}, df = {t2.df:.0f}, p = {t2.pvalue:.3g}")
print(f"Welch 95% CI for the mean difference: [{ci_welch.low:.3f}, {ci_welch.high:.3f}]")

# %% [markdown]
# ### T3. Mann-Whitney U (на основі рангів)
# Перевіряє, чи має випадкова оцінка запізнілого замовлення тенденцію бути нижчою за випадкову оцінку вчасного. Підходить для порядкових даних; лише з 5 значеннями є багато однакових рангів, які SciPy обробляє нормальною апроксимацією з поправкою на зв'язки.

# %%
t3 = stats.mannwhitneyu(late_s, ontime_s, alternative="two-sided", method="asymptotic")
rank_biserial = 2 * t3.statistic / (len(late_s) * len(ontime_s)) - 1     # -1..1, від'ємне = оцінки запізнілих нижчі
print(f"U = {t3.statistic:,.0f}, p = {t3.pvalue:.3g}, rank-biserial correlation = {rank_biserial:.3f}")

# %% [markdown]
# ### T4. Різниця у % відгуків з 1-2 зірками, з 95% CI

# %%
low_late, low_ontime = (late_s <= 2), (ontime_s <= 2)
p1, p2 = low_late.mean(), low_ontime.mean()
se = np.sqrt(p1 * (1 - p1) / len(late_s) + p2 * (1 - p2) / len(ontime_s))
wald = (p1 - p2 - 1.96 * se, p1 - p2 + 1.96 * se)
t4 = bootstrap_diff(low_late.astype(float), low_ontime.astype(float), n_boot=3000)
print(f"1-2 star share: late {100*p1:.1f}% vs on time {100*p2:.1f}%")
print(f"difference {100*(p1-p2):.1f} pp | normal-approx 95% CI [{100*wald[0]:.1f}, {100*wald[1]:.1f}] pp"
      f" | bootstrap 95% CI [{100*t4[1]:.1f}, {100*t4[2]:.1f}] pp")
print(f"relative risk of a 1-2 star review: {p1 / p2:.1f}x")

# %% [markdown]
# ### T5. Розмір ефекту

# %%
pooled_sd = np.sqrt(((len(late_s) - 1) * late_s.var(ddof=1) + (len(ontime_s) - 1) * ontime_s.var(ddof=1))
                    / (len(late_s) + len(ontime_s) - 2))
cohens_d = (late_s.mean() - ontime_s.mean()) / pooled_sd
print(f"Cohen's d = {cohens_d:.2f}  (|d| 0.2 small, 0.5 medium, 0.8 large)")
print(f"rank-biserial = {rank_biserial:.2f}")

# %%
results = pd.DataFrame([
    {"method": "T1 bootstrap mean difference", "estimate": t1[0], "ci": f"[{t1[1]:.3f}, {t1[2]:.3f}]", "p_value": np.nan},
    {"method": "T2 Welch t-test", "estimate": t2.statistic, "ci": f"[{ci_welch.low:.3f}, {ci_welch.high:.3f}]", "p_value": t2.pvalue},
    {"method": "T3 Mann-Whitney U (rank-biserial)", "estimate": rank_biserial, "ci": "-", "p_value": t3.pvalue},
    {"method": "T4 diff. in % 1-2 stars (pp)", "estimate": 100 * (p1 - p2), "ci": f"[{100*t4[1]:.1f}, {100*t4[2]:.1f}]", "p_value": np.nan},
    {"method": "T5 Cohen's d", "estimate": cohens_d, "ci": "-", "p_value": np.nan},
]).set_index("method")
print(results)

# %% [markdown]
# **Висновок (B):** Запізнілі замовлення в середньому отримують оцінку на **2.02 зірки нижчу** (2.27 проти 4.29; 95% CI від -2.06 до -1.98). 62.4% запізнілих замовлень отримують 1-2 зірки проти 9.2% вчасних: **+53.2 процентного пункту** (95% CI 51.9-54.4), у 6.7x разів імовірніше. p-значення Welch і Mann-Whitney нижчі за будь-яку виведену точність; ефект великий (Cohen's d -1.71, rank-biserial -0.64).

# %% [markdown]
# ## Частина C - Стійкість
# ### C1. Чи це лише географія? Розрив усередині 5 найбільших штатів

# %%
big_states = rev["customer_state"].value_counts().head(5).index
rows = []
for st in big_states:
    s = rev[rev["customer_state"] == st]
    a = s.loc[s["status"] == "late", "review_score"].to_numpy()
    b = s.loc[s["status"] == "on time", "review_score"].to_numpy()
    est, lo, hi = bootstrap_diff(a, b, n_boot=2000)
    rows.append({"state": st, "n_late": len(a), "n_on_time": len(b), "mean_late": a.mean(),
                 "mean_on_time": b.mean(), "difference": est, "ci_low": lo, "ci_high": hi})
within = pd.DataFrame(rows).set_index("state")
print(within.round(3))

# %% [markdown]
# **Висновок:** Розрив є всередині кожного з 5 найбільших штатів, від -1.63 зірки (PR) до -2.33 (RJ), і жоден CI не містить 0. Сама лише географія не пояснює цей зв'язок.

# %% [markdown]
# ### C2. Чи зростає розрив разом із тривалістю затримки? (доза-відповідь)

# %%
BUCKETS = [-np.inf, -10, -1, 0, 3, 7, np.inf]
LABELS = ["10+ days early", "1-9 days early", "on the day", "1-3 days late", "4-7 days late", "8+ days late"]
rev["delay_bucket"] = pd.cut(rev["delay_days"], bins=BUCKETS, labels=LABELS, right=True)
dose = (rev.groupby("delay_bucket", observed=True)["review_score"]
           .agg(n="size", mean_score="mean", pct_1_2_stars=lambda s: 100 * (s <= 2).mean()))
print(dose.round(2))

# %%
fig, ax = plt.subplots(figsize=(9, 3.8))
colors = [BLUE if "late" not in str(l) else ORANGE for l in dose.index]
bars = ax.bar(range(len(dose)), dose["pct_1_2_stars"], color=colors, width=0.6)
for i, (v, n) in enumerate(zip(dose["pct_1_2_stars"], dose["n"])):
    ax.text(i, v + 1, f"{v:.0f}%", ha="center", fontsize=9, color=INK)
    ax.text(i, -6, f"n={n:,}", ha="center", fontsize=8, color=INK2)
ax.set_xticks(range(len(dose)), dose.index)
ax.set_ylim(-9, max(dose["pct_1_2_stars"]) + 10)
ax.set_ylabel("% of 1-2 star reviews")
ax.grid(axis="x", visible=False)
ax.set_title("The longer the delay, the higher the share of 1-2 star reviews")
fig.tight_layout()
save(fig, "sat_low_reviews_by_delay.png")

# %% [markdown]
# **Висновок:** Чітка залежність доза-відповідь: частка 1-2 зірок становить 9% для замовлень, доставлених на 10+ днів раніше, 12% - у обіцяний день, 32% - при запізненні на 1-3 дні, 68% - на 4-7 днів і 79% - на 8+ днів.

# %% [markdown]
# ### C3. Яка частка всіх відгуків з 1-2 зірками припадає на запізнілі замовлення?

# %%
low = rev[rev["review_score"] <= 2]
share_late_in_low = (low["status"] == "late").mean()
share_late_overall = (rev["status"] == "late").mean()
print(f"late orders are {100*share_late_overall:.1f}% of reviewed orders "
      f"but {100*share_late_in_low:.1f}% of all 1-2 star reviews")

# %% [markdown]
# ### C4. Чутливість: вилучити відгуки, написані до отримання замовлення

# %%
rev2 = rev[~rev["review_before_delivery"].astype(bool)]
a2 = rev2.loc[rev2["status"] == "late", "review_score"].to_numpy()
b2 = rev2.loc[rev2["status"] == "on time", "review_score"].to_numpy()
est2 = bootstrap_diff(a2, b2, n_boot=2000)
print(f"removed {len(rev) - len(rev2):,} reviews; late n={len(a2):,}, on-time n={len(b2):,}")
print(f"mean difference {est2[0]:.3f}, 95% CI [{est2[1]:.3f}, {est2[2]:.3f}]")

# %% [markdown]
# **Висновок (C3, C4):**
# Запізнілі замовлення становлять 6.7% замовлень із відгуками, але **32.6% усіх відгуків з 1-2 зірками**.
# **Чутливість:** вилучення 4,970 відгуків, написаних до отримання замовлення, прибирає більшість відгуків на запізнілі замовлення (n запізнілих падає з 6,378 до 1,629). Розрив зменшується з -2.02 до **-0.77 зірки (95% CI від -0.84 до -0.69)**, але залишається явно від'ємним. Отже, значна частина основного розриву походить від клієнтів, які пишуть відгук *ще під час очікування* - незадоволення стосується самої затримки; клієнти, які пишуть відгук після запізнілої доставки, все одно задоволені на ~0.8 зірки менше.

# %% [markdown]
# ## Частина D - Що це доводить і чого не доводить
#
# 1. **95% CI** (від -2.06 до -1.98 зірки): якби ми багато разів повторили вибірку, 95% інтервалів, побудованих таким чином, містили б справжню різницю середньої оцінки між запізнілими та вчасними замовленнями. Він вузький, бо вибірки великі.
# 2. **Що це показує:** у цих даних запізніла доставка сильно **пов'язана** з нижчими оцінками відгуків; зв'язок великий, значно перевищує шум вибірки, присутній у кожному великому штаті, зростає з тривалістю затримки і зберігається після вилучення відгуків, написаних до доставки (менший, -0.77 зірки).
# 3. **Чого це НЕ показує:** що запізніла доставка *спричиняє* нижчі оцінки або що скорочення запізнень підвищить середню оцінку на 2 зірки. Клієнти, які ніколи не залишали відгуків, не представлені.
# 4. **Неконтрольовані змішувальні чинники:** категорія товару, продавець, ціна/розмір товару, відстань і вартість доставки, а також перевізник - будь-що з цього може бути пов'язане і з запізненням, і з задоволеністю.
# 5. **Вердикт щодо гіпотези "запізнілі доставки пов'язані з нижчими оцінками відгуків": підтверджено.** Розмір ефекту залежить від того, коли написано відгук (-2.0 зірки загалом, -0.8 зірки для відгуків, написаних після доставки).
