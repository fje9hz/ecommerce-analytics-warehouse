-- ============================================================================
-- 03_staging.sql
-- ----------------------------------------------------------------------------
-- Staging: properly typed, deduplicated, no business logic yet. The goal is
-- to make every downstream query trust that one row = one real-world event.
-- ============================================================================

DROP TABLE IF EXISTS staging.customers   CASCADE;
DROP TABLE IF EXISTS staging.products    CASCADE;
DROP TABLE IF EXISTS staging.orders      CASCADE;
DROP TABLE IF EXISTS staging.order_items CASCADE;
DROP TABLE IF EXISTS staging.sessions    CASCADE;

CREATE TABLE staging.customers (
    customer_id      BIGINT      PRIMARY KEY,
    email            TEXT        NOT NULL,
    full_name        TEXT,
    signup_ts        TIMESTAMP   NOT NULL,
    country          TEXT,
    region           TEXT,
    city             TEXT,
    marketing_optin  BOOLEAN     NOT NULL DEFAULT FALSE
);

CREATE TABLE staging.products (
    product_id   BIGINT      PRIMARY KEY,
    sku          TEXT        NOT NULL UNIQUE,
    name         TEXT        NOT NULL,
    category     TEXT,
    subcategory  TEXT,
    unit_price   NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
    list_price   NUMERIC(10,2) NOT NULL CHECK (list_price >= 0),
    is_active    BOOLEAN     NOT NULL DEFAULT TRUE
);

CREATE TABLE staging.orders (
    order_id       BIGINT       PRIMARY KEY,
    customer_id    BIGINT       NOT NULL REFERENCES staging.customers(customer_id),
    order_ts       TIMESTAMP    NOT NULL,
    status         TEXT         NOT NULL
                                CHECK (status IN ('placed','fulfilled','cancelled','refunded')),
    channel        TEXT         NOT NULL
                                CHECK (channel IN ('web','ios','android')),
    discount_code  TEXT,
    shipping_cost  NUMERIC(10,2) NOT NULL DEFAULT 0
);

CREATE TABLE staging.order_items (
    order_id    BIGINT       NOT NULL REFERENCES staging.orders(order_id),
    line_no     INT          NOT NULL,
    product_id  BIGINT       NOT NULL REFERENCES staging.products(product_id),
    quantity    INT          NOT NULL CHECK (quantity > 0),
    unit_price  NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
    PRIMARY KEY (order_id, line_no)
);

CREATE TABLE staging.sessions (
    session_id        UUID        PRIMARY KEY,
    customer_id       BIGINT      REFERENCES staging.customers(customer_id),  -- nullable: anonymous browsing
    started_ts        TIMESTAMP   NOT NULL,
    ended_ts          TIMESTAMP   NOT NULL,
    pages_viewed      INT         NOT NULL CHECK (pages_viewed >= 0),
    added_to_cart     BOOLEAN     NOT NULL,
    reached_checkout  BOOLEAN     NOT NULL,
    purchased         BOOLEAN     NOT NULL,
    utm_source        TEXT,
    utm_campaign      TEXT,
    CHECK (ended_ts >= started_ts)
);

CREATE INDEX ON staging.orders        (customer_id, order_ts);
CREATE INDEX ON staging.order_items   (product_id);
CREATE INDEX ON staging.sessions      (customer_id, started_ts);
