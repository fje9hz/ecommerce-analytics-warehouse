-- ============================================================================
-- 02_staging.sql
-- ----------------------------------------------------------------------------
-- Cleans the raw layer into typed, deduplicated staging tables.
--
-- Conventions:
--   • Dedup with ROW_NUMBER() OVER (... ORDER BY loaded_at DESC) — keep newest.
--   • Cast everything explicitly. No implicit conversions.
--   • Normalize obvious mess (currency symbols, casing, booleans).
-- ============================================================================

TRUNCATE staging.sessions, staging.order_items, staging.orders,
         staging.products, staging.customers RESTART IDENTITY;

-- ----- customers -----------------------------------------------------------
INSERT INTO staging.customers
    (customer_id, email, full_name, signup_ts, country, region, city, marketing_optin)
SELECT
    customer_id::BIGINT,
    LOWER(TRIM(email)),
    TRIM(full_name),
    signup_ts::TIMESTAMP,
    NULLIF(TRIM(country), ''),
    NULLIF(TRIM(region), ''),
    NULLIF(TRIM(city), ''),
    CASE LOWER(TRIM(marketing_optin))
        WHEN 'true'  THEN TRUE
        WHEN 't'     THEN TRUE
        WHEN '1'     THEN TRUE
        WHEN 'yes'   THEN TRUE
        ELSE FALSE
    END
FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY loaded_at DESC) AS rn
    FROM raw.customers
    WHERE customer_id IS NOT NULL AND email IS NOT NULL
) deduped
WHERE rn = 1;

-- ----- products ------------------------------------------------------------
INSERT INTO staging.products
    (product_id, sku, name, category, subcategory, unit_price, list_price, is_active)
SELECT
    product_id::BIGINT,
    UPPER(TRIM(sku)),
    TRIM(name),
    INITCAP(NULLIF(TRIM(category), '')),
    INITCAP(NULLIF(TRIM(subcategory), '')),
    REPLACE(REPLACE(unit_price, '$', ''), ',', '')::NUMERIC(10,2),
    REPLACE(REPLACE(list_price, '$', ''), ',', '')::NUMERIC(10,2),
    CASE LOWER(TRIM(is_active)) WHEN 'false' THEN FALSE WHEN '0' THEN FALSE ELSE TRUE END
FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY loaded_at DESC) AS rn
    FROM raw.products
    WHERE product_id IS NOT NULL
) deduped
WHERE rn = 1;

-- ----- orders --------------------------------------------------------------
-- Drop orders whose customer or status is nonsense; we'll never reach the
-- fact-build step if these slip through, but it's cheaper to fail loudly here.
INSERT INTO staging.orders
    (order_id, customer_id, order_ts, status, channel, discount_code, shipping_cost)
SELECT
    o.order_id::BIGINT,
    o.customer_id::BIGINT,
    o.order_ts::TIMESTAMP,
    LOWER(TRIM(o.status)),
    LOWER(TRIM(o.channel)),
    NULLIF(TRIM(o.discount_code), ''),
    COALESCE(NULLIF(o.shipping_cost, '')::NUMERIC(10,2), 0)
FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY loaded_at DESC) AS rn
    FROM raw.orders
    WHERE order_id IS NOT NULL
) o
WHERE rn = 1
  AND LOWER(TRIM(o.status))  IN ('placed','fulfilled','cancelled','refunded')
  AND LOWER(TRIM(o.channel)) IN ('web','ios','android')
  AND EXISTS (SELECT 1 FROM staging.customers c WHERE c.customer_id = o.customer_id::BIGINT);

-- ----- order_items ---------------------------------------------------------
INSERT INTO staging.order_items
    (order_id, line_no, product_id, quantity, unit_price)
SELECT
    oi.order_id::BIGINT,
    oi.line_no::INT,
    oi.product_id::BIGINT,
    oi.quantity::INT,
    REPLACE(REPLACE(oi.unit_price, '$', ''), ',', '')::NUMERIC(10,2)
FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY order_id, line_no ORDER BY loaded_at DESC) AS rn
    FROM raw.order_items
) oi
WHERE rn = 1
  AND EXISTS (SELECT 1 FROM staging.orders o WHERE o.order_id = oi.order_id::BIGINT)
  AND EXISTS (SELECT 1 FROM staging.products p WHERE p.product_id = oi.product_id::BIGINT);

-- ----- sessions ------------------------------------------------------------
INSERT INTO staging.sessions
    (session_id, customer_id, started_ts, ended_ts, pages_viewed,
     added_to_cart, reached_checkout, purchased, utm_source, utm_campaign)
SELECT
    session_id::UUID,
    NULLIF(customer_id, '')::BIGINT,
    started_ts::TIMESTAMP,
    ended_ts::TIMESTAMP,
    pages_viewed::INT,
    added_to_cart::BOOLEAN,
    reached_checkout::BOOLEAN,
    purchased::BOOLEAN,
    NULLIF(TRIM(utm_source), ''),
    NULLIF(TRIM(utm_campaign), '')
FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY session_id ORDER BY loaded_at DESC) AS rn
    FROM raw.sessions
) deduped
WHERE rn = 1
  AND (customer_id IS NULL
       OR customer_id = ''
       OR EXISTS (SELECT 1 FROM staging.customers c
                  WHERE c.customer_id = deduped.customer_id::BIGINT));
