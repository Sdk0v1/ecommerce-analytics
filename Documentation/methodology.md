# Methodology

All definitions live in one place — `SQL/01_analytics_views.sql` — and are repeated identically in `Python/data_cleaning.py`.

## 1. Definitions
| Term | Definition | Population | Rows excluded |
| --- | --- | --- | --- |
| Order | order with `order_status = 'delivered'` | 96,478 delivered orders; KPIs use purchase months 2017-01 .. 2018-08 (96,211) | 2,963 non-delivered orders; 267 delivered orders outside the KPI period (2016 is sparse with a gap, 2018-09/10 have < 20 orders) |
| Revenue | `SUM(price + freight_value)` over the order's items — what the customer paid for goods + shipping; item level, so category revenue adds up to total | KPI period | same as Order |
| AOV | Revenue / Orders | KPI period | same as Order |
| Customer | `customer_unique_id` (`customer_id` is created per order) | all delivered orders, whole history (93,358) | non-delivered orders |
| Repeat customer | customer with ≥ 2 delivered orders; *strict* repeat = orders on ≥ 2 different purchase dates | 93,358 customers | — |
| Delivery time | `delivered_customer_date − purchase_timestamp` in fractional days | KPI period, with a delivery date (96,203) | 8 delivered orders without a customer delivery date |
| Late delivery | delivered **date** > estimated delivery **date**; delivered on the promised day = on time (the estimated date always has time 00:00, so the comparison is on DATE level) | 96,203 | same as Delivery time |
| Order review score | score of the **latest** review of the order (by answer timestamp, then creation date, then review_id) | 95,560 reviewed orders in the delivery population | 646 delivered orders without a review; 547 orders had > 1 review (202 with different scores) |

## 2. Data quality and exclusions
| Check | Result | Decision |
| --- | --- | --- |
| Row counts vs CSV | all 8 tables match (orders 99,441 · items 112,650 · customers 99,441 · products 32,951 · sellers 3,095 · payments 103,886 · reviews 99,224 · translations 71) | — |
| Unparseable dates | 0 — every NaT was an empty field | — |
| Missing delivery dates | explained by status; only 8 of 96,478 delivered orders lack one | excluded from delivery analysis only |
| Missing product category | 610 products (1.9%) | reported as `unknown` |
| Duplicates | no duplicate rows or keys, except 789 `review_id`s used on two different orders | reviews joined by `order_id`, not `review_id` |
| Timestamp order | no order delivered before purchase; 165 carrier dates before purchase, 1,350 before approval, 23 customer deliveries before carrier pickup | only purchase → customer delivery is used, not the seller/carrier split |
| Delivery outliers | median 10.2, p90 23.1, p99 46.1, max 209.6 days; 306 orders > 60 days | kept — plausible long tail; median/p90 are robust |
| Multiple reviews | 547 orders; 202 with different scores | keep the latest review |
| Reviews before delivery | 4,976; 74.5% of late orders' reviews vs 0.3% on time | kept in the primary analysis, removed in a sensitivity check |
| Review comments | 59% without a message, 88% without a title | not used |

## 3. Revenue driver decomposition
Revenue = Orders × AOV (R = N · A). The change between two periods splits exactly into three parts:

ΔR = ΔN · A₀ (volume effect) + N₀ · ΔA (AOV effect) + ΔN · ΔA (interaction)

It is calculated month over month (main driver = the larger absolute effect) and for the whole period, comparing the average of 2017-01..03 with 2018-06..08; a log decomposition (ln R = ln N + ln A) is added because it has no interaction term. It was chosen because it answers R2/R3 directly in R$ and the parts add up to the actual change (a `check_sum` column verifies this). Result: orders ranged 750–7,289 a month while AOV stayed at R$ 146–170, so volume is the driver.

## 4. Cohort and repeat analysis
- **Cohort** = month of the customer's first delivered order; cohorts 2017-01 .. 2018-08 are shown (2016 cohorts have < 350 customers).
- **month_number** = calendar months between the cohort month and the order month (0 = first month).
- **Retention(k)** = customers of the cohort with an order in month k / cohort size.
- **Right-censoring:** the data ends in 2018-08, so newer cohorts have fewer observable months. Unobservable cells are NULL (blank in the heatmap), never 0. The 90-day repeat rate only uses first-purchase months up to 2018-05, and C4 excludes customers whose first order was after 2018-05-31, so every customer had ≥ 90 days to return.
- Same-day second orders are often one basket split in two, so a *strict* repeat (a later purchase date) is reported as well.

## 5. RFM segmentation
Reference date = the day after the last purchase (2018-08-30), not "today".

| Metric | Method | Thresholds | Why |
| --- | --- | --- | --- |
| R (recency) | quintiles, 5 = most recent | 93 / 178 / 269 / 383 days | many distinct values, no natural business thresholds |
| F (frequency) | rule-based: 1 → 1, 2 → 2, 3+ → 3 | — | quintiles are impossible: 97.0% of customers have exactly 1 order (4 of 5 quintile edges = 1) |
| M (monetary) | quintiles, 5 = highest | R$ 55.25 / 87.36 / 132.69 / 208.55 | right-skewed but continuous; quantiles are robust to the skew |

| Segment | Rule (evaluated top to bottom) | Customers | % revenue |
| --- | --- | --- | --- |
| Champions | F ≥ 2 and R ≥ 4 | 1,214 | 2.5% |
| Loyal Customers | F ≥ 2 and R ≤ 3 | 1,587 | 3.1% |
| Potential Loyalists | F = 1, R ≥ 4, M ≥ 4 | 14,503 | 28.4% |
| Recent One-time | F = 1, R ≥ 4, M ≤ 3 | 21,842 | 10.3% |
| At Risk | F = 1, R ∈ {2, 3}, M ≥ 4 | 13,823 | 26.4% |
| One-time Lapsed | every other F = 1 customer | 40,389 | 29.3% |

A single "one-time" segment would contain 97% of customers, so the one-time base is split by recency and value — the two things that decide whether a second-purchase campaign is worth sending.

## 6. Statistical analysis
**Data characteristics → method**

| Characteristic | Data | Consequence |
| --- | --- | --- |
| Scale | review score 1–5, ordinal | report mean difference *and* % of 1–2 star reviews; use a rank test as a check |
| Shape | on-time scores pile up at 5 (skew −1.74); late scores bimodal (skew 0.73); delivery days skew 3.85 | no normality assumption for individual values; median/p90 for delivery |
| Sample sizes | 89,182 on time vs 6,378 late (14:1) | large n → the difference in means is ~normal (CLT) |
| Variances | SD 1.15 vs 1.57 | Welch's t-test, never Student's |
| Independence | one row per order; 2,752 customers have > 1 order | treated as independent (stated assumption) |

**Methods:** percentile bootstrap (2,000–5,000 resamples, seed 42) for the median/p90 delivery time and for the difference in mean score and in % 1–2 stars — these are the primary results. Welch's t-test, Mann-Whitney U (tie-corrected), Cohen's d and rank-biserial correlation are supporting checks. SciPy's bootstrap reproduces the median CI (10.17–10.25).

**Robustness:** (1) the gap within each of the 5 largest states (−1.63 to −2.33 stars); (2) dose-response by delay bucket (1–2 stars: 12% on the day → 79% at 8+ days late); (3) share of low reviews from late orders (32.6%); (4) sensitivity without the 4,970 reviews written before delivery (−0.77 stars, CI −0.84 to −0.69).

**CI interpretation:** if the sampling were repeated many times, 95% of intervals built this way would contain the true difference. The interval (−2.06 to −1.98) is narrow because the samples are large.

**What it proves / does not prove:** late delivery is strongly *associated* with lower scores, beyond sampling noise, within states, growing with the delay. It does not prove that delay *causes* lower scores, or that removing delays would add 2 stars: category, seller, price/size, distance, freight cost and carrier are not controlled, and customers who never reviewed are missing.

## 7. Validation (SQL vs Python)
Python recalculates every number from the raw CSVs (not from the PostgreSQL views) and compares with `reports/tables/sql_headline_numbers.csv`.

| Metric | SQL | Python | Difference | Explanation |
| --- | --- | --- | --- | --- |
| total_orders | 96,211 | 96,211 | 0 | identical definitions |
| total_revenue | 15,377,809.91 | 15,377,809.91 | 0 | |
| aov | 159.834 | 159.834 | 0 | |
| total_customers | 93,358 | 93,358 | 0 | |
| repeat_customers | 2,801 | 2,801 | 0 | |
| repeat_rate_pct | 3.000 | 3.000 | 0 | |
| top_category_revenue | 1,407,941.40 | 1,407,941.40 | 0 | health_beauty |
| on_time_pct | 93.211 | 93.211 | 0 | |
| median_delivery_days | 10.210 | 10.210 | 0 | PERCENTILE_CONT = linear interpolation in pandas |
| p90_delivery_days | 23.064 | 23.064 | < 0.001 | floating-point rounding |
| revenue_2017_11 | 1,154,559.53 | 1,154,559.53 | < 0.001 | floating-point rounding |
| monthly orders / revenue (20 months) | — | — | 0 months differ; max revenue difference 0.0 | |

## 8. Limitations
- Observational data: results are associations, not causal effects.
- Confounders not controlled: product category, seller, price/size, distance, freight cost, carrier.
- Reviews only for delivered orders; 646 delivered orders have none, and non-reviewers are not represented.
- Many late-order reviews were written before delivery — the headline gap mixes the product experience with the waiting.
- `customer_unique_id` may still split one person over several ids, which would understate the repeat rate.
- Data ends 2018-08: recent cohorts are right-censored; there is no cost or margin data (revenue ≠ profit).
- Intermediate timestamps (approval, carrier) are unreliable, so delays cannot be split into seller vs carrier time.
- RFM thresholds are quintiles of this dataset, not business-validated values; segments describe the past.
