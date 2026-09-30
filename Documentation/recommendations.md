# Recommendations

Format: Finding → Business Impact → Recommendation (+ evidence strength, what would confirm it, metric to track)

## 1. Manage late deliveries before they become 1-star reviews
- **Finding:** late orders score 2.27 vs 4.29 stars (−2.02, 95% CI −2.06 to −1.98); 62.4% of late orders get 1–2 stars vs 9.2% on time. Late orders are 6.7% of reviewed orders but 32.6% of all 1–2 star reviews, and the share of low reviews rises from 12% (on the promised day) to 79% (8+ days late). (D5, S2–S4)
- **Business impact:** a third of all bad reviews come from a small, identifiable group of orders; bad reviews hurt conversion for sellers and the marketplace.
- **Recommendation:** flag orders predicted to miss the estimated date and notify the customer proactively (new date, small voucher); set more realistic estimated dates where lateness is systematic.
- **Evidence strength:** strong association (narrow CI, holds within all 5 largest states, dose-response, survives removing pre-delivery reviews at −0.77 stars); not causal.
- **What would confirm it:** an A/B test of proactive notification on predicted-late orders, comparing review scores and complaints.
- **Metric to track:** % of 1–2 star reviews among late orders; late % overall.

## 2. Fix delivery in the North-East first
- **Finding:** AL (21.5%), MA (17.5%), SE (15.4%), PI (13.9%) and CE (13.8%) are late 2–3x as often as the national 6.8%; their median delivery is 16–22 days and p90 30–40 days vs 10.2 / 23.1 nationally; all CIs lie far above the national value. (D2)
- **Business impact:** customers in these states get the worst experience and — per recommendation 1 — the worst reviews.
- **Recommendation:** review carriers and routes to the North-East, and recalibrate the promised delivery date per state so it reflects the real p90.
- **Evidence strength:** strong (large n, bootstrap CIs).
- **What would confirm it:** a pilot with a different carrier or adjusted estimates in 1–2 of these states, compared with the others.
- **Metric to track:** late % and median / p90 delivery days by state, monthly.

## 3. Launch a second-purchase programme
- **Finding:** 97.0% of 93,358 customers ordered once; the repeat rate is 3.0%; in every cohort under 1% of customers order again in any later month. (C1–C3)
- **Business impact:** all growth depends on acquiring new customers; even a small increase in repeat rate adds revenue at low acquisition cost.
- **Recommendation:** send a time-limited second-purchase offer after delivery, with a hold-out control group to measure the real uplift.
- **Evidence strength:** strong descriptive fact; the effect of any campaign is unknown.
- **What would confirm it:** repeat rate in the treated group vs control after 90 days.
- **Metric to track:** 90-day repeat rate by first-purchase month.

## 4. Target the high-value one-time buyers
- **Finding:** Potential Loyalists (14,503, recent and high first order) and At Risk (13,823, older and high first order) are 30.3% of customers but 54.8% of revenue; One-time Lapsed (40,389) are 43% of customers. The top 20% of customers bring 53.5% of revenue. (C5)
- **Business impact:** the customers most worth re-activating are known and can be addressed by name.
- **Recommendation:** spend the campaign budget from recommendation 3 on Potential Loyalists first, At Risk second; keep One-time Lapsed only in cheap mass channels.
- **Evidence strength:** descriptive; segments describe past behaviour and do not predict who will return.
- **What would confirm it:** campaign response and repeat rate by segment.
- **Metric to track:** repeat rate and revenue per contacted customer, by RFM segment.

## 5. Grow orders, not basket size
- **Finding:** monthly orders ranged 750–7,289 while AOV stayed at R$ 146–170; revenue has been flat at ~R$ 1.0–1.13M a month since Jan 2018. No category dominates (top 10 = 62%, #1 health_beauty 9.2%). (R1–R4)
- **Business impact:** revenue growth has stalled because order growth has stalled; AOV levers would move revenue only a little.
- **Recommendation:** make orders and new/returning customers the primary growth KPIs; treat AOV tactics (bundles, free-shipping thresholds) as secondary.
- **Evidence strength:** strong descriptive (decomposition adds up exactly).
- **What would confirm it:** the decomposition on new months of data.
- **Metric to track:** monthly orders, MoM % and YoY %, volume vs AOV effect.

## What we could not answer with this data
- Whether late delivery *causes* lower scores — no experiment, and category, seller, price, distance and carrier are not controlled.
- Profitability — there is no cost, margin or marketing-spend data, so revenue ≠ profit and campaign ROI cannot be estimated.
- Why customers do not return — no browsing, marketing or customer-service data.
- Whether a delay is the seller's or the carrier's fault — intermediate timestamps are unreliable.
- Satisfaction of customers who never left a review.
- Long-term retention of recent cohorts — the data ends in 2018-08.
