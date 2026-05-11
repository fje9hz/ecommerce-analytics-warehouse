-- ============================================================================
-- 01_load_raw.sql
-- ----------------------------------------------------------------------------
-- Loads CSVs from the directory passed via psql variable `csv_dir`.
-- Invoke:
--   psql -v csv_dir="'/abs/path/to/data/csv'" -f etl/01_load_raw.sql
--
-- The raw layer is append-only; truncate first so re-runs are idempotent.
-- ============================================================================

TRUNCATE raw.customers, raw.products, raw.orders, raw.order_items, raw.sessions;

\set customers_csv   :csv_dir '/customers.csv'
\set products_csv    :csv_dir '/products.csv'
\set orders_csv      :csv_dir '/orders.csv'
\set order_items_csv :csv_dir '/order_items.csv'
\set sessions_csv    :csv_dir '/sessions.csv'

\copy raw.customers   (customer_id, email, full_name, signup_ts, country, region, city, marketing_optin)  FROM :customers_csv   CSV HEADER
\copy raw.products    (product_id, sku, name, category, subcategory, unit_price, list_price, is_active)    FROM :products_csv    CSV HEADER
\copy raw.orders      (order_id, customer_id, order_ts, status, channel, discount_code, shipping_cost)     FROM :orders_csv      CSV HEADER
\copy raw.order_items (order_id, line_no, product_id, quantity, unit_price)                                FROM :order_items_csv CSV HEADER
\copy raw.sessions    (session_id, customer_id, started_ts, ended_ts, pages_viewed, added_to_cart, reached_checkout, purchased, utm_source, utm_campaign) FROM :sessions_csv CSV HEADER

-- A friendly "what did we just load?" summary
SELECT 'customers'   AS table_name, count(*) FROM raw.customers
UNION ALL SELECT 'products',    count(*) FROM raw.products
UNION ALL SELECT 'orders',      count(*) FROM raw.orders
UNION ALL SELECT 'order_items', count(*) FROM raw.order_items
UNION ALL SELECT 'sessions',    count(*) FROM raw.sessions;
