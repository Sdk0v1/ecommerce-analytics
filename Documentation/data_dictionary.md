# Data Dictionary

Source: Olist Brazilian E-Commerce Public Dataset (Kaggle), licence CC BY-NC-SA 4.0.
Types as loaded into PostgreSQL (`SQL/00_create_tables.sql`): ids → TEXT, timestamps → TIMESTAMP, money → NUMERIC(10,2).

## Raw tables
### orders (99,441 rows · one row = one order)
| Column | Type | Description | Notes |
| --- | --- | --- | --- |
| order_id | text | order identifier | primary key |
| customer_id | text | customer id for this order | a new id per order — use `customer_unique_id` for people |
| order_status | text | delivered, shipped, canceled, unavailable, invoiced, processing, created, approved | only `delivered` (96,478) is analysed |
| order_purchase_timestamp | timestamp | when the order was placed | defines the month and the cohort |
| order_approved_at | timestamp | payment approval | 160 missing; not used |
| order_delivered_carrier_date | timestamp | handed to the carrier | 1,783 missing; unreliable ordering — not used |
| order_delivered_customer_date | timestamp | delivered to the customer | 2,965 missing (8 for delivered orders) |
| order_estimated_delivery_date | timestamp | date promised at purchase | always 00:00 → compared as a DATE |

### order_items (112,650 rows · one row = one item line)
| Column | Type | Description | Notes |
| --- | --- | --- | --- |
| order_id | text | order | FK → orders |
| order_item_id | integer | sequence number of the item within the order | PK = (order_id, order_item_id) |
| product_id | text | product | FK → products |
| seller_id | text | seller | FK → sellers |
| shipping_limit_date | timestamp | seller's deadline to hand over to the carrier | not used |
| price | numeric | item price, R$ | part of revenue |
| freight_value | numeric | freight charged for the item, R$ | part of revenue |

### customers (99,441 rows · one row = one customer_id)
| Column | Type | Description | Notes |
| --- | --- | --- | --- |
| customer_id | text | per-order customer id | PK; 1:1 with orders |
| customer_unique_id | text | the actual customer | 93,358 with a delivered order |
| customer_zip_code_prefix | text | first 5 digits of the zip code | read as text to keep leading zeros |
| customer_city | text | city | |
| customer_state | text | state (UF) | used for R5, D2 |

### products (32,951 rows · one row = one product)
| Column | Type | Description | Notes |
| --- | --- | --- | --- |
| product_id | text | product | PK |
| product_category_name | text | category in Portuguese | 610 missing → `unknown` |
| product_name_lenght | integer | characters in the product name | original typo kept; 610 missing |
| product_description_lenght | integer | characters in the description | original typo kept; 610 missing |
| product_photos_qty | integer | number of photos | 610 missing |
| product_weight_g | integer | weight, g | 2 missing |
| product_length_cm / product_height_cm / product_width_cm | integer | dimensions, cm | 2 missing |

### sellers (3,095 rows · one row = one seller)
| Column | Type | Description | Notes |
| --- | --- | --- | --- |
| seller_id | text | seller | PK |
| seller_zip_code_prefix | text | zip prefix | |
| seller_city | text | city | |
| seller_state | text | state | |

### payments (103,886 rows · one row = one payment method in an order)
| Column | Type | Description | Notes |
| --- | --- | --- | --- |
| order_id | text | order | FK → orders |
| payment_sequential | integer | sequence of the payment within the order | PK = (order_id, payment_sequential) |
| payment_type | text | credit_card, boleto, voucher, debit_card, ... | main type = largest payment |
| payment_installments | integer | number of instalments | |
| payment_value | numeric | amount, R$ | revenue uses items, not payments |

### reviews (99,224 rows · one row = one review)
| Column | Type | Description | Notes |
| --- | --- | --- | --- |
| review_id | text | review | **not unique**: 789 ids appear on two orders |
| order_id | text | reviewed order | 547 orders have > 1 review → latest kept |
| review_score | smallint | 1–5 stars | |
| review_comment_title | text | title | 88% missing; not used |
| review_comment_message | text | text | 59% missing; not used |
| review_creation_date | timestamp | when the survey was sent/created | 4,976 before delivery |
| review_answer_timestamp | timestamp | when the customer answered | used to pick the latest review |

### category_translation (71 rows)
| Column | Type | Description | Notes |
| --- | --- | --- | --- |
| product_category_name | text | Portuguese name | PK |
| product_category_name_english | text | English name | 2 categories have no translation → Portuguese name kept |

## Derived columns / views
| Name | Table / view | Formula | Purpose |
| --- | --- | --- | --- |
| revenue | `analytics.order_base` | `SUM(price + freight_value)` per order | R1–R5, C5 |
| item_revenue | `analytics.item_base` | `price + freight_value` | R4 |
| category | `analytics.item_base` | English name → Portuguese name → `'unknown'` | R4 |
| purchase_month | `analytics.order_base` | `DATE_TRUNC('month', order_purchase_timestamp)` | R1, cohorts |
| in_kpi_period | `analytics.order_base` | purchase between 2017-01-01 and 2018-08-31 | all KPIs |
| delivery_days | `analytics.order_base` | `(delivered_customer_date − purchase_timestamp)` in fractional days | D3, D4 |
| estimated_days | `analytics.order_base` | `(estimated_delivery_date − purchase_timestamp)` in days | promised time |
| delay_days | `analytics.order_base` | `delivered_date − estimated_date` in whole days (> 0 = late) | S4 dose-response |
| is_late | `analytics.order_base` | 1 if `delivered_customer_date::date > estimated_delivery_date::date`, 0 otherwise, NULL without delivery date | D1, D2, D5 |
| review_score | `analytics.order_base` | score of the latest review (ROW_NUMBER by answer timestamp) | S1–S4 |
| review_before_delivery | `analytics.order_base` | `review_creation_date < delivered_customer_date::date` | S4 sensitivity |
| main_payment_type | `analytics.order_base` | payment type with the largest value | C4 |
| cohort_month, month_number, retention_pct | `analytics.cohort_retention` | first purchase month; months since; active / cohort size | C1, C3 |
| R, F, M, rfm_segment | `reports/tables/rfm_segments.csv` | R, M quintiles; F = 1 / 2 / 3+; rules in `methodology.md` §5 | C5 |

## Relationships
<!-- ![ERD](../reports/figures/erd.png) -->
| From | To | Key | Cardinality |
| --- | --- | --- | --- |
| customers | orders | customer_id | 1 : 1 (a new customer_id per order) |
| customer_unique_id | customers | customer_unique_id | 1 : many |
| orders | order_items | order_id | 1 : 0..many |
| products | order_items | product_id | 1 : many |
| sellers | order_items | seller_id | 1 : many |
| orders | payments | order_id | 1 : 1..many |
| orders | reviews | order_id | 1 : 0..many (latest review kept) |
| category_translation | products | product_category_name | 1 : many |
