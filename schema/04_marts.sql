-- ============================================================================
-- 04_marts.sql
-- ----------------------------------------------------------------------------
-- The dimensional model. Star schema with conformed dimensions and two facts:
--   fact_orders   (grain: one row per order line)
--   fact_sessions (grain: one row per web session)
--
-- Modeling choices worth defending in an interview:
--   • Surrogate keys (BIGSERIAL) on every dim — natural keys can change.
--   • SCD Type 2 on dim_customer so historical orders attach to the customer
--     state-at-the-time, not the current state.
--   • dim_date is fully pre-populated; never compute it on the fly.
--   • An "unknown" row exists in every dim so facts always join cleanly.
-- ============================================================================

DROP TABLE IF EXISTS marts.fact_orders     CASCADE;
DROP TABLE IF EXISTS marts.fact_sessions   CASCADE;
DROP TABLE IF EXISTS marts.dim_customer    CASCADE;
DROP TABLE IF EXISTS marts.dim_product     CASCADE;
DROP TABLE IF EXISTS marts.dim_geography   CASCADE;
DROP TABLE IF EXISTS marts.dim_date        CASCADE;

-- ----------------------------------------------------------------------------
-- dim_date
-- ----------------------------------------------------------------------------
CREATE TABLE marts.dim_date (
    date_key     INT         PRIMARY KEY,   -- YYYYMMDD
    full_date    DATE        NOT NULL UNIQUE,
    day_of_week  SMALLINT    NOT NULL,      -- 1=Mon ... 7=Sun (ISO)
    day_name     TEXT        NOT NULL,
    is_weekend   BOOLEAN     NOT NULL,
    day_of_month SMALLINT    NOT NULL,
    month        SMALLINT    NOT NULL,
    month_name   TEXT        NOT NULL,
    quarter      SMALLINT    NOT NULL,
    year         SMALLINT    NOT NULL,
    iso_week     SMALLINT    NOT NULL,
    is_holiday_us BOOLEAN    NOT NULL DEFAULT FALSE
);

-- ----------------------------------------------------------------------------
-- dim_geography  (conformed across customers, future-proof for shipping/billing)
-- ----------------------------------------------------------------------------
CREATE TABLE marts.dim_geography (
    geography_key BIGSERIAL PRIMARY KEY,
    country       TEXT      NOT NULL,
    region        TEXT,
    city          TEXT,
    UNIQUE (country, region, city)
);

-- ----------------------------------------------------------------------------
-- dim_customer  (SCD Type 2)
--
-- Every change to country/region/city/marketing_optin closes the current row
-- and opens a new one. `customer_key` is the surrogate; `customer_id` is the
-- natural key, repeated across versions.
-- ----------------------------------------------------------------------------
CREATE TABLE marts.dim_customer (
    customer_key     BIGSERIAL  PRIMARY KEY,
    customer_id      BIGINT     NOT NULL,
    email            TEXT       NOT NULL,
    full_name        TEXT,
    signup_date_key  INT        NOT NULL REFERENCES marts.dim_date(date_key),
    geography_key    BIGINT     NOT NULL REFERENCES marts.dim_geography(geography_key),
    marketing_optin  BOOLEAN    NOT NULL,
    effective_from   TIMESTAMP  NOT NULL,
    effective_to     TIMESTAMP  NOT NULL DEFAULT '9999-12-31'::TIMESTAMP,
    is_current       BOOLEAN    NOT NULL,
    UNIQUE (customer_id, effective_from)
);
CREATE INDEX dim_customer_natural_idx ON marts.dim_customer (customer_id, is_current);
CREATE INDEX dim_customer_effective_idx ON marts.dim_customer (customer_id, effective_from, effective_to);

-- ----------------------------------------------------------------------------
-- dim_product  (SCD Type 1 — we don't need product history for this use case)
-- ----------------------------------------------------------------------------
CREATE TABLE marts.dim_product (
    product_key   BIGSERIAL PRIMARY KEY,
    product_id    BIGINT    NOT NULL UNIQUE,
    sku           TEXT      NOT NULL UNIQUE,
    name          TEXT      NOT NULL,
    category      TEXT,
    subcategory   TEXT,
    current_unit_price NUMERIC(10,2) NOT NULL,
    current_list_price NUMERIC(10,2) NOT NULL,
    is_active     BOOLEAN   NOT NULL
);

-- ----------------------------------------------------------------------------
-- fact_orders
-- Grain: one row per order line item.
-- ----------------------------------------------------------------------------
CREATE TABLE marts.fact_orders (
    order_id         BIGINT       NOT NULL,
    line_no          INT          NOT NULL,
    order_date_key   INT          NOT NULL REFERENCES marts.dim_date(date_key),
    customer_key     BIGINT       NOT NULL REFERENCES marts.dim_customer(customer_key),
    product_key      BIGINT       NOT NULL REFERENCES marts.dim_product(product_key),
    quantity         INT          NOT NULL,
    unit_price       NUMERIC(10,2) NOT NULL,
    gross_revenue    NUMERIC(12,2) NOT NULL,    -- quantity * unit_price
    discount_amount  NUMERIC(12,2) NOT NULL DEFAULT 0,
    net_revenue      NUMERIC(12,2) NOT NULL,
    shipping_cost    NUMERIC(10,2) NOT NULL DEFAULT 0,
    status           TEXT         NOT NULL,
    channel          TEXT         NOT NULL,
    discount_code    TEXT,
    PRIMARY KEY (order_id, line_no)
);
CREATE INDEX fact_orders_date_idx     ON marts.fact_orders (order_date_key);
CREATE INDEX fact_orders_customer_idx ON marts.fact_orders (customer_key);
CREATE INDEX fact_orders_product_idx  ON marts.fact_orders (product_key);

-- ----------------------------------------------------------------------------
-- fact_sessions
-- Grain: one row per web session.
-- ----------------------------------------------------------------------------
CREATE TABLE marts.fact_sessions (
    session_id        UUID        PRIMARY KEY,
    session_date_key  INT         NOT NULL REFERENCES marts.dim_date(date_key),
    customer_key      BIGINT      REFERENCES marts.dim_customer(customer_key),  -- null = anonymous
    started_ts        TIMESTAMP   NOT NULL,
    ended_ts          TIMESTAMP   NOT NULL,
    duration_seconds  INT         NOT NULL,
    pages_viewed      INT         NOT NULL,
    added_to_cart     BOOLEAN     NOT NULL,
    reached_checkout  BOOLEAN     NOT NULL,
    purchased         BOOLEAN     NOT NULL,
    utm_source        TEXT,
    utm_campaign      TEXT
);
CREATE INDEX fact_sessions_date_idx     ON marts.fact_sessions (session_date_key);
CREATE INDEX fact_sessions_customer_idx ON marts.fact_sessions (customer_key);
