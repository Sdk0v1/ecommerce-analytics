-- =====================================================================
-- 00_create_tables.sql
-- Purpose : create raw tables for the Olist dataset, load the CSVs,
--           verify row counts, add keys and indexes.
-- Notes   : P1 - Data Loading (PostgreSQL), P1 - ERD and Relationships
-- Run     : from the repository root (so relative CSV paths work):
--             psql -d olist -f SQL/00_create_tables.sql
-- Rules   : ids -> TEXT, timestamps -> TIMESTAMP, money -> NUMERIC(10,2)
--           PRIMARY KEY only where uniqueness was verified (see checks)
-- =====================================================================

DROP SCHEMA IF EXISTS raw CASCADE;
CREATE SCHEMA raw;

-- ---------------------------------------------------------------------
-- orders : one row = one order
-- order_estimated_delivery_date is TIMESTAMP in the CSV, but every value
-- has time 00:00:00 -> it is effectively a DATE (see P1 - Definitions).
-- ---------------------------------------------------------------------
CREATE TABLE raw.orders (
    order_id                       TEXT,
    customer_id                    TEXT,
    order_status                   TEXT,
    order_purchase_timestamp       TIMESTAMP,
    order_approved_at              TIMESTAMP,
    order_delivered_carrier_date   TIMESTAMP,
    order_delivered_customer_date  TIMESTAMP,
    order_estimated_delivery_date  TIMESTAMP
);

-- order_items : one row = one item line (one unit) in an order
CREATE TABLE raw.order_items (
    order_id             TEXT,
    order_item_id        INTEGER,
    product_id           TEXT,
    seller_id            TEXT,
    shipping_limit_date  TIMESTAMP,
    price                NUMERIC(10,2),
    freight_value        NUMERIC(10,2)
);

-- customers : one row = one customer_id (= one order!)
CREATE TABLE raw.customers (
    customer_id               TEXT,
    customer_unique_id        TEXT,
    customer_zip_code_prefix  TEXT,
    customer_city             TEXT,
    customer_state            TEXT
);

-- products : one row = one product (column names keep the original typos)
CREATE TABLE raw.products (
    product_id                  TEXT,
    product_category_name       TEXT,
    product_name_lenght         INTEGER,
    product_description_lenght  INTEGER,
    product_photos_qty          INTEGER,
    product_weight_g            INTEGER,
    product_length_cm           INTEGER,
    product_height_cm           INTEGER,
    product_width_cm            INTEGER
);

-- sellers : one row = one seller
CREATE TABLE raw.sellers (
    seller_id               TEXT,
    seller_zip_code_prefix  TEXT,
    seller_city             TEXT,
    seller_state            TEXT
);

-- payments : one row = one payment method used in an order
CREATE TABLE raw.payments (
    order_id              TEXT,
    payment_sequential    INTEGER,
    payment_type          TEXT,
    payment_installments  INTEGER,
    payment_value         NUMERIC(10,2)
);

-- reviews : one row = one review (review_id is NOT unique - see K7)
CREATE TABLE raw.reviews (
    review_id                TEXT,
    order_id                 TEXT,
    review_score             SMALLINT,
    review_comment_title     TEXT,
    review_comment_message   TEXT,
    review_creation_date     TIMESTAMP,
    review_answer_timestamp  TIMESTAMP
);

-- category_translation : Portuguese -> English category names
CREATE TABLE raw.category_translation (
    product_category_name          TEXT,
    product_category_name_english  TEXT
);

-- =====================================================================
-- LOAD (psql meta-commands; paths are relative to the repository root)
-- FORMAT csv: unquoted empty fields become NULL; quoted line breaks in
-- review comments are handled correctly.
-- =====================================================================
\copy raw.orders               FROM 'data/raw/olist_orders_dataset.csv'              WITH (FORMAT csv, HEADER true)
\copy raw.order_items          FROM 'data/raw/olist_order_items_dataset.csv'         WITH (FORMAT csv, HEADER true)
\copy raw.customers            FROM 'data/raw/olist_customers_dataset.csv'           WITH (FORMAT csv, HEADER true)
\copy raw.products             FROM 'data/raw/olist_products_dataset.csv'            WITH (FORMAT csv, HEADER true)
\copy raw.sellers              FROM 'data/raw/olist_sellers_dataset.csv'             WITH (FORMAT csv, HEADER true)
\copy raw.payments             FROM 'data/raw/olist_order_payments_dataset.csv'      WITH (FORMAT csv, HEADER true)
\copy raw.reviews              FROM 'data/raw/olist_order_reviews_dataset.csv'       WITH (FORMAT csv, HEADER true)
\copy raw.category_translation FROM 'data/raw/product_category_name_translation.csv' WITH (FORMAT csv, HEADER true)

-- =====================================================================
-- VERIFY row counts (expected from the CSVs / Python len())
-- orders 99,441 · order_items 112,650 · customers 99,441 · products 32,951
-- sellers 3,095 · payments 103,886 · reviews 99,224 · category_translation 71
-- =====================================================================
SELECT 'orders' AS table_name, COUNT(*) AS n_rows FROM raw.orders
UNION ALL SELECT 'order_items',          COUNT(*) FROM raw.order_items
UNION ALL SELECT 'customers',            COUNT(*) FROM raw.customers
UNION ALL SELECT 'products',             COUNT(*) FROM raw.products
UNION ALL SELECT 'sellers',              COUNT(*) FROM raw.sellers
UNION ALL SELECT 'payments',             COUNT(*) FROM raw.payments
UNION ALL SELECT 'reviews',              COUNT(*) FROM raw.reviews
UNION ALL SELECT 'category_translation', COUNT(*) FROM raw.category_translation;

-- =====================================================================
-- KEY CHECKS (K1-K10 in P1 - ERD and Relationships)
-- =====================================================================

-- K1 / K2 / K4: uniqueness of candidate keys (duplicates should be 0)
SELECT 'K1 orders.order_id'            AS check_name, COUNT(*) - COUNT(DISTINCT order_id)    AS duplicates FROM raw.orders
UNION ALL
SELECT 'K2 customers.customer_id',                    COUNT(*) - COUNT(DISTINCT customer_id)           FROM raw.customers
UNION ALL
SELECT 'K4 order_items (order_id, order_item_id)',    COUNT(*) - COUNT(DISTINCT (order_id, order_item_id)) FROM raw.order_items
UNION ALL
SELECT 'products.product_id',                         COUNT(*) - COUNT(DISTINCT product_id)            FROM raw.products
UNION ALL
SELECT 'sellers.seller_id',                           COUNT(*) - COUNT(DISTINCT seller_id)             FROM raw.sellers
UNION ALL
SELECT 'K7 reviews.review_id',                        COUNT(*) - COUNT(DISTINCT review_id)             FROM raw.reviews;

-- K2: customer_id vs customer_unique_id
SELECT COUNT(DISTINCT customer_id)        AS customer_ids,
       COUNT(DISTINCT customer_unique_id) AS unique_customers
FROM raw.customers;

-- K3: people (customer_unique_id) with more than one customer_id
SELECT COUNT(*) AS unique_ids_with_several_customer_ids
FROM (
    SELECT customer_unique_id
    FROM raw.customers
    GROUP BY customer_unique_id
    HAVING COUNT(DISTINCT customer_id) > 1
) t;

-- K5: orders without items, by status
SELECT o.order_status, COUNT(*) AS orders_without_items
FROM raw.orders o
LEFT JOIN raw.order_items i ON i.order_id = o.order_id
WHERE i.order_id IS NULL
GROUP BY o.order_status
ORDER BY orders_without_items DESC;

-- K6: payment rows per order
SELECT MIN(n) AS min_rows, MAX(n) AS max_rows,
       COUNT(*) FILTER (WHERE n > 1) AS orders_with_several_payment_rows
FROM (SELECT order_id, COUNT(*) AS n FROM raw.payments GROUP BY order_id) t;

-- K7: orders with more than one review
SELECT COUNT(*) AS orders_with_several_reviews
FROM (SELECT order_id FROM raw.reviews GROUP BY order_id HAVING COUNT(*) > 1) t;

-- K8: orphans
SELECT 'items without product' AS check_name, COUNT(*) AS n
FROM raw.order_items i LEFT JOIN raw.products p ON p.product_id = i.product_id
WHERE p.product_id IS NULL
UNION ALL
SELECT 'items without seller', COUNT(*)
FROM raw.order_items i LEFT JOIN raw.sellers s ON s.seller_id = i.seller_id
WHERE s.seller_id IS NULL
UNION ALL
SELECT 'orders without customer', COUNT(*)
FROM raw.orders o LEFT JOIN raw.customers c ON c.customer_id = o.customer_id
WHERE c.customer_id IS NULL
UNION ALL
SELECT 'payments without order', COUNT(*)
FROM raw.payments p LEFT JOIN raw.orders o ON o.order_id = p.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'reviews without order', COUNT(*)
FROM raw.reviews r LEFT JOIN raw.orders o ON o.order_id = r.order_id
WHERE o.order_id IS NULL;

-- K9: item value (price + freight) vs payments, per order
-- Aggregate each "many" table to order level FIRST, then join (fan-out trap).
WITH items AS (
    SELECT order_id, SUM(price + freight_value) AS item_value
    FROM raw.order_items
    GROUP BY order_id
), pays AS (
    SELECT order_id, SUM(payment_value) AS paid_value
    FROM raw.payments
    GROUP BY order_id
)
SELECT COUNT(*)                                                         AS orders_with_both,
       COUNT(*) FILTER (WHERE ABS(i.item_value - p.paid_value) > 0.01)   AS orders_that_differ,
       SUM(i.item_value)                                                AS total_item_value,
       SUM(p.paid_value)                                                AS total_paid_value,
       SUM(p.paid_value) - SUM(i.item_value)                            AS total_difference
FROM items i
JOIN pays  p USING (order_id);

-- K10: categories without an English translation
SELECT p.product_category_name, COUNT(*) AS products
FROM raw.products p
LEFT JOIN raw.category_translation t USING (product_category_name)
WHERE p.product_category_name IS NOT NULL
  AND t.product_category_name IS NULL
GROUP BY p.product_category_name;

-- =====================================================================
-- KEYS (only where the checks above proved uniqueness)
-- review_id is NOT unique -> no primary key on raw.reviews.
-- =====================================================================
ALTER TABLE raw.orders               ADD PRIMARY KEY (order_id);
ALTER TABLE raw.customers            ADD PRIMARY KEY (customer_id);
ALTER TABLE raw.order_items          ADD PRIMARY KEY (order_id, order_item_id);
ALTER TABLE raw.products             ADD PRIMARY KEY (product_id);
ALTER TABLE raw.sellers              ADD PRIMARY KEY (seller_id);
ALTER TABLE raw.payments             ADD PRIMARY KEY (order_id, payment_sequential);
ALTER TABLE raw.category_translation ADD PRIMARY KEY (product_category_name);

ALTER TABLE raw.orders      ADD FOREIGN KEY (customer_id) REFERENCES raw.customers (customer_id);
ALTER TABLE raw.order_items ADD FOREIGN KEY (order_id)    REFERENCES raw.orders (order_id);
ALTER TABLE raw.order_items ADD FOREIGN KEY (product_id)  REFERENCES raw.products (product_id);
ALTER TABLE raw.order_items ADD FOREIGN KEY (seller_id)   REFERENCES raw.sellers (seller_id);
ALTER TABLE raw.payments    ADD FOREIGN KEY (order_id)    REFERENCES raw.orders (order_id);
ALTER TABLE raw.reviews     ADD FOREIGN KEY (order_id)    REFERENCES raw.orders (order_id);
-- products -> category_translation is NOT enforced: 2 categories have no translation (K10).

-- =====================================================================
-- INDEXES
-- =====================================================================
CREATE INDEX ON raw.orders (customer_id);
CREATE INDEX ON raw.orders (order_purchase_timestamp);
CREATE INDEX ON raw.order_items (product_id);
CREATE INDEX ON raw.payments (order_id);
CREATE INDEX ON raw.reviews (order_id);
CREATE INDEX ON raw.customers (customer_unique_id);

ANALYZE;
