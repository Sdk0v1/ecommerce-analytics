# Business Questions

Population unless stated otherwise: delivered orders purchased 2017-01 .. 2018-08 (96,211 orders; 96,203 with a delivery date; 95,560 with a review). Customer questions use the whole history (93,358 customers).

| ID | Question | Hypothesis | Method | Verdict | Key number |
| --- | --- | --- | --- | --- | --- |
| R1 | How does revenue change month by month? | Revenue grows inconsistently | Monthly orders / revenue / AOV, MoM via LAG (`SQL/monthly_kpis.sql`) | **Supported.** Fast growth through 2017, Nov-2017 spike, flat in 2018 | R$ 0.13M (Jan 2017) → R$ 1.15M (Nov 2017) → ~R$ 1.0–1.13M/month in 2018; total R$ 15.38M |
| R2 | What causes revenue growth or decline? | Changes come from the number of orders | Decomposition ΔR = ΔN·A₀ + N₀·ΔA + ΔN·ΔA per month (`SQL/revenue_analysis.sql`) | **Supported.** Order volume moves revenue; AOV is stable | Orders 750–7,289 per month; AOV R$ 146–170 |
| R3 | Is growth driven by orders, AOV, or both? | Orders | Same decomposition, whole-period start (2017-01..03) vs end (2018-06..08) | **Orders.** AOV contributes little | Orders ~10x from min to max month vs AOV ±8% around R$ 160 |
| R4 | Which categories contribute most to revenue? | A few categories dominate | Revenue by category with RANK() and cumulative share | **Not supported** — revenue is spread out | Top 10 of ~70 categories = 62%; #1 health_beauty 9.2% (R$ 1.41M) |
| R5 | Which states generate the most revenue? | SP dominates | Revenue by `customer_state` with RANK() and cumulative share | **Supported** (by order volume) | SP 42% of delivered orders (40,399 of 96,203), then RJ 12.8%, MG 11.8%; revenue shares: run `revenue_analysis.sql` R5.1 |
| C1 | What % of customers purchase again? | Repeat rate is low | Orders per `customer_unique_id` (`SQL/customer_retention.sql`) | **Supported** | 2,801 of 93,358 customers = **3.0%** |
| C2 | How many customers buy only once? | The large majority | Same | **Supported** | 90,557 (97.0%); 2,573 bought twice, 228 three or more times |
| C3 | How quickly do customers return? | — | First-purchase-month cohorts (`SQL/cohort_analysis.sql`), time to 2nd order (LEAD) | Returns are rare in every month after the first purchase | Cohort retention in month 1..12: 0.02–0.72% per month; no cohort reaches 1% |
| C4 | Which segments are more likely to return? | High-value / well-served customers return more | Repeat rate by state, first-order value quartile, payment type, first delivery late/on time, first review (`customer_retention.sql` C4.1) | Partly answered: RFM segments do not differ by state (SP 35–50% in every segment) | Rates per segment: run `customer_retention.sql` C4.1 |
| C5 | Does RFM reveal meaningful groups? | Yes | RFM: R and M quintiles, F rule-based (1 / 2 / 3+) (`Python/rfm_analysis.ipynb`) | **Partly.** Classic RFM is weak (F hardly varies); R × M split of one-time buyers is actionable | Potential Loyalists + At Risk: 30.3% of customers, 54.8% of revenue |
| D1 | What % of orders are delivered on time? | Most orders are on time | `AVG(1 - is_late)` (`SQL/delivery_analysis.sql`) | **Supported** | **93.2%** on time (6.8% late) |
| D2 | Which states have the worst delivery performance? | Some regions are much worse | Late % and median/p90 by state, n ≥ 300; bootstrap CIs | **Supported** — the North-East | AL 21.5%, MA 17.5%, SE 15.4%, PI 13.9%, CE 13.8% late vs 6.8% national |
| D3 | What is the median delivery time? | — | PERCENTILE_CONT(0.5) + bootstrap CI | — | **10.21 days** (95% CI 10.17–10.26) |
| D4 | What is the p90 delivery time? | — | PERCENTILE_CONT(0.9) + bootstrap CI | — | **23.06 days** (95% CI 22.93–23.17) |
| D5 | Are late deliveries associated with lower review scores? | Yes | Bootstrap CI, Welch, Mann-Whitney, robustness (`Python/statistical_analysis.ipynb`) | **Supported** | −2.02 stars (95% CI −2.06 to −1.98) |
| S1 | What is the average review score? | — | Mean / median of the latest review per order | — | **4.16** (median 5), n = 95,560 |
| S2 | How do scores differ between on-time and late? | Late orders score lower | Group comparison, distribution of stars | **Supported** | 2.27 vs 4.29; 1–2 stars: 62.4% vs 9.2%; 1 star: 54% vs 7% |
| S3 | Is the difference statistically meaningful? | Yes | Bootstrap CIs (primary), Welch t, Mann-Whitney U, Cohen's d | **Yes**, large effect | +53.2 pp 1–2 stars (CI 51.9–54.4); d = −1.71; rank-biserial −0.64 |
| S4 | Could delivery performance contribute to dissatisfaction? | Yes | Within-state comparison, dose-response by delay, share of low reviews, sensitivity without pre-delivery reviews | **Plausible, not proven** (association, not causation) | Late = 6.7% of reviewed orders but 32.6% of 1–2 star reviews; 1–2 stars rise 12% → 79% with delay; −0.77 stars after removing pre-delivery reviews |
