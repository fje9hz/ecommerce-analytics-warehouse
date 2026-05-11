-- ============================================================================
-- 02_raw.sql
-- ----------------------------------------------------------------------------
-- Landing tables. Everything is TEXT/timestamp-without-tz on purpose: the raw
-- layer should accept whatever upstream sends, even when it's malformed.
-- Cleanup happens in the staging layer.
-- ============================================================================

DROP TABLE IF EXISTS raw.customers   CASCADE;
DROP TABLE IF EXISTS raw.products    CASCADE;
DROP TABLE IF EXISTS raw.orders      CASCADE;
DROP TABLE IF EXISTS raw.order_items CASCADE;
DROP TABLE IF EXISTS raw.sessions    CASCADE;

CREATE TABLE raw.customers (
    customer_id     TEXT,
    email           TEXT,
    full_name       TEXT,
    signup_ts       TEXT,           -- intentionally TEXT, dates come in as strings
    country         TEXT,
    region          TEXT,
    city            TEXT,
    marketing_optin TEXT,           -- 'true'/'false'/'1'/'0' — normalize in staging
    loaded_at       TIMESTAMP DEFAULT now()
);

CREATE TABLE raw.products (
    product_id   TEXT,
    sku          TEXT,
    name         TEXT,
    category     TEXT,
    subcategory  TEXT,
    unit_price   TEXT,              -- TEXT to absorb '$' prefixes, commas, etc.
    list_price   TEXT,
    is_active    TEXT,
    loaded_at    TIMESTAMP DEFAULT now()
);

CREATE TABLE raw.orders (
    order_id      TEXT,
    customer_id   TEXT,
    order_ts      TEXT,
    status        TEXT,              -- placed / fulfilled / cancelled / refunded
    channel       TEXT,              -- web / ios / android
    discount_code TEXT,
    shipping_cost TEXT,
    loaded_at     TIMESTAMP DEFAULT now()
);

CREATE TABLE raw.order_items (
    order_id    TEXT,
    line_no     TEXT,
    product_id  TEXT,
    quantity    TEXT,
    unit_price  TEXT,                -- captured at time of sale
    loaded_at   TIMESTAMP DEFAULT now()
);

CREATE TABLE raw.sessions (
    session_id      TEXT,
    customer_id     TEXT,
    started_ts      TEXT,
    ended_ts        TEXT,
    pages_viewed    TEXT,
    added_to_cart   TEXT,
    reached_checkout TEXT,
    purchased       TEXT,
    utm_source      TEXT,
    utm_campaign    TEXT,
    loaded_at       TIMESTAMP DEFAULT now()
);

-- Helpful indexes for the staging-layer joins. None are unique because the raw
-- layer explicitly tolerates duplicates.
CREATE INDEX ON raw.customers   (customer_id);
CREATE INDEX ON raw.products    (product_id);
CREATE INDEX ON raw.orders      (order_id);
CREATE INDEX ON raw.order_items (order_id);
CREATE INDEX ON raw.sessions    (session_id);
