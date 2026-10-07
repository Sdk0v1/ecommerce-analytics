# Insights

Labels: **Fact** · **Calculation** · **Assumption** · **Hypothesis**

## Hypotheses from the brief
| Hypothesis | Verdict | Key number | Source |
| --- | --- | --- | --- |
| Revenue grows inconsistently | **Supported** — strong growth in 2017, Nov-2017 spike, −27% in Dec 2017, flat in 2018 | R$ 0.13M (Jan 2017) → R$ 1.15M (Nov 2017) → ~R$ 1.0–1.13M/month in 2018 | `SQL/monthly_kpis.sql`, `reports/figures/rev_monthly_trend.png` |
| Revenue driven by volume / AOV / both | **Volume** | Orders 750–7,289 per month; AOV R$ 146–170 | `SQL/revenue_analysis.sql`, `reports/figures/rev_orders_vs_aov.png` |
| Repeat rate is relatively low | **Supported** | 3.0% of 93,358 customers ordered twice or more | `SQL/customer_retention.sql`, `Python/data_cleaning.py` (validation) |
| Some regions have significantly longer delivery times | **Supported** | AL, MA, SE, PI, CE: median 16–22 days vs 10.2 national; all CIs above the national value | `Python/statistical_analysis.py` A3 |
| Late deliveries associated with lower review scores | **Supported** (association) | −2.02 stars, 95% CI −2.06 to −1.98; −0.77 after removing pre-delivery reviews | `Python/statistical_analysis.py` T1, C4 |

## Findings
| # | Label | Finding (number, n) | Question ID | Source |
| --- | --- | --- | --- | --- |
| 1 | Fact | KPI period (2017-01..2018-08): 96,211 delivered orders, revenue R$ 15,377,809.91, AOV R$ 159.83 — identical in SQL and Python | R1 | `data_cleaning.py` B |
| 2 | Fact | Revenue peaked in Nov 2017 at R$ 1,154,559.53 (7,289 orders — also the highest order count) | R1 | `sql_results_figures.py` |
| 3 | Calculation | Monthly orders varied ~10x (750–7,289), AOV only between R$ 146.25 and R$ 169.98 → revenue changes are volume changes | R2, R3 | `sql_results_figures.py` Fig. 3 |
| 4 | Fact | Revenue has been flat at ~R$ 1.0–1.13M/month since Jan 2018; Aug 2018 R$ 985,558 | R1 | `rev_monthly_trend.png` |
| 5 | Calculation | Top 10 categories = 62% of revenue; health_beauty 9.2%, watches_gifts 8.2%, bed_bath_table 8.0%, sports_leisure 7.3%, computers_accessories 6.7% | R4 | `rev_top_categories.png` |
| 6 | Fact | SP has 42% of delivered orders (40,399 of 96,203), RJ 12.8% (12,310), MG 11.8% (11,319) | R5 | `del_late_rate_by_state.png` (n per state) |
| 7 | Fact | 97.0% of customers (90,557 of 93,358) ordered once; 2,573 twice; 228 three or more times | C1, C2 | `rfm_analysis.py` step 2 |
| 8 | Calculation | In every cohort 2017-01..2018-07, under 1% of customers order in any single later month (0.02–0.72%) | C3 | `ret_cohort_heatmap.png` |
| 9 | Calculation | Potential Loyalists (14,503) + At Risk (13,823) = 30.3% of customers, 54.8% of revenue; repeat buyers (Champions + Loyal) = 3.0% of customers, 5.6% of revenue | C5 | `rfm_analysis.py` step 5 |
| 10 | Calculation | Top 10% of customers bring 38.3% of revenue, top 20% bring 53.5% | C5 | `rfm_analysis.py` |
| 11 | Fact | RFM segments have a similar state mix (SP 35–50% in every segment) — geography does not separate them | C4, C5 | `rfm_analysis.py` |
| 12 | Fact | 93.2% of 96,203 delivered orders arrived on time; late 6.8% | D1 | `data_cleaning.py` B, `statistical_analysis.py` |
| 13 | Calculation | Delivery time: median 10.21 days (CI 10.17–10.26), p90 23.06 (CI 22.93–23.17), mean 12.5, p99 46.0, max 209.6; skewness 3.85 | D3, D4 | `statistical_analysis.py` A1–A2 |
| 14 | Calculation | Late % by state (n ≥ 300): AL 21.5%, MA 17.5%, SE 15.4%, PI 13.9%, CE 13.8%; best PR 4.1%, SP 4.5%, MG 4.6% | D2 | `del_late_rate_by_state.png` |
| 15 | Calculation | Worst 5 states: median 16.3–22.3 days, p90 30.1–39.6 days vs 10.2 / 23.1 nationally | D2 | `statistical_analysis.py` A3 |
| 16 | Fact | Average review score 4.16 (median 5), n = 95,560 | S1 | `statistical_analysis.py` B1 |
| 17 | Calculation | Late 2.27 vs on time 4.29 stars: −2.02 (95% CI −2.06 to −1.98); Cohen's d −1.71 | S2, S3, D5 | `statistical_analysis.py` T1, T5 |
| 18 | Calculation | 1–2 star share: late 62.4% vs on time 9.2% → +53.2 pp (CI 51.9–54.4), 6.7x as likely | S2, S3 | `statistical_analysis.py` T4 |
| 19 | Calculation | The gap holds within each of the 5 largest states: −1.63 (PR) to −2.33 (RJ), no CI includes 0 | S4 | `statistical_analysis.py` C1 |
| 20 | Calculation | Dose-response: 1–2 star share 9% (10+ days early), 12% (on the day), 32% (1–3 days late), 68% (4–7), 79% (8+) | S4 | `statistical_analysis.py` C2 |
| 21 | Calculation | Late orders are 6.7% of reviewed orders but 32.6% of all 1–2 star reviews | S4 | `statistical_analysis.py` C3 |
| 22 | Fact | 74.5% of late orders' reviews (4,751 of 6,381) were written before the order arrived vs 0.3% on time | S4 | `data_cleaning.py` A8 |
| 23 | Calculation | Without pre-delivery reviews the gap is −0.77 stars (CI −0.84 to −0.69) | S4 | `statistical_analysis.py` C4 |
| 24 | Hypothesis | Delay causes part of the dissatisfaction — not proven: category, seller, price, distance and carrier are not controlled | S4 | `statistical_analysis.py` Part D |
| 25 | Assumption | Orders are close enough to independent for the tests (only 2,752 customers have > 1 order in the review population) | S3 | `statistical_analysis.py` B2 |
