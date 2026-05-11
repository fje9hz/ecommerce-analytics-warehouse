-- ============================================================================
-- 03_build_dim_customer.sql
-- ----------------------------------------------------------------------------
-- Builds dim_customer using Slowly Changing Dimension Type 2 logic.
--
-- A customer's "tracked attributes" are: country, region, city, marketing_optin.
-- A change to any of these closes the current row (sets effective_to and
-- is_current=false) and opens a new one.
--
-- This implementation is idempotent: running it again with the same staging
-- data is a no-op. Running it after staging.customers changes detects deltas.
--
-- Steps:
--   1) Build dim_date and dim_geography (no-op if already populated).
--   2) Insert brand-new customers as their first version.
--   3) Detect changed customers, close their current row, insert new version.
-- ============================================================================

-- Make sure dim_date covers the customer signup range.
INSERT INTO marts.dim_date (date_key, full_date, day_of_week, day_name,
                            is_weekend, day_of_month, month, month_name,
                            quarter, year, iso_week)
SELECT
    TO_CHAR(d, 'YYYYMMDD')::INT,
    d::DATE,
    EXTRACT(ISODOW FROM d)::SMALLINT,
    TO_CHAR(d, 'Day'),
    EXTRACT(ISODOW FROM d) IN (6,7),
    EXTRACT(DAY FROM d)::SMALLINT,
    EXTRACT(MONTH FROM d)::SMALLINT,
    TO_CHAR(d, 'Month'),
    EXTRACT(QUARTER FROM d)::SMALLINT,
    EXTRACT(YEAR FROM d)::SMALLINT,
    EXTRACT(WEEK FROM d)::SMALLINT
FROM GENERATE_SERIES(
        (SELECT LEAST(MIN(signup_ts)::DATE, MIN(order_ts)::DATE)
         FROM staging.customers, staging.orders),
        (SELECT GREATEST(MAX(signup_ts)::DATE, MAX(order_ts)::DATE) + INTERVAL '30 day'
         FROM staging.customers, staging.orders),
        INTERVAL '1 day'
     ) AS d
ON CONFLICT (date_key) DO NOTHING;

-- Populate dim_geography from staging.
INSERT INTO marts.dim_geography (country, region, city)
SELECT DISTINCT
    COALESCE(country, 'Unknown'),
    COALESCE(region,  'Unknown'),
    COALESCE(city,    'Unknown')
FROM staging.customers
ON CONFLICT (country, region, city) DO NOTHING;

-- ----------------------------------------------------------------------------
-- Insert brand-new customers (no existing row at all).
-- ----------------------------------------------------------------------------
INSERT INTO marts.dim_customer
    (customer_id, email, full_name, signup_date_key, geography_key,
     marketing_optin, effective_from, is_current)
SELECT
    s.customer_id,
    s.email,
    s.full_name,
    TO_CHAR(s.signup_ts, 'YYYYMMDD')::INT,
    g.geography_key,
    s.marketing_optin,
    s.signup_ts,
    TRUE
FROM staging.customers s
JOIN marts.dim_geography g
  ON g.country = COALESCE(s.country,'Unknown')
 AND g.region  = COALESCE(s.region, 'Unknown')
 AND g.city    = COALESCE(s.city,   'Unknown')
LEFT JOIN marts.dim_customer dc
  ON dc.customer_id = s.customer_id
WHERE dc.customer_id IS NULL;

-- ----------------------------------------------------------------------------
-- Detect deltas: customers whose current row differs from staging.
-- Close the current row, then insert a new "current" row.
-- ----------------------------------------------------------------------------
WITH changed AS (
    SELECT
        s.customer_id,
        s.email,
        s.full_name,
        s.signup_ts,
        g.geography_key AS new_geo_key,
        s.marketing_optin AS new_optin,
        dc.customer_key AS old_key,
        dc.geography_key AS old_geo_key,
        dc.marketing_optin AS old_optin
    FROM staging.customers s
    JOIN marts.dim_geography g
      ON g.country = COALESCE(s.country,'Unknown')
     AND g.region  = COALESCE(s.region, 'Unknown')
     AND g.city    = COALESCE(s.city,   'Unknown')
    JOIN marts.dim_customer dc
      ON dc.customer_id = s.customer_id
     AND dc.is_current
    WHERE g.geography_key       IS DISTINCT FROM dc.geography_key
       OR s.marketing_optin     IS DISTINCT FROM dc.marketing_optin
),
closed AS (
    UPDATE marts.dim_customer dc
    SET effective_to = now(),
        is_current   = FALSE
    FROM changed
    WHERE dc.customer_key = changed.old_key
    RETURNING changed.customer_id, changed.email, changed.full_name,
              changed.signup_ts, changed.new_geo_key, changed.new_optin
)
INSERT INTO marts.dim_customer
    (customer_id, email, full_name, signup_date_key, geography_key,
     marketing_optin, effective_from, is_current)
SELECT
    customer_id, email, full_name,
    TO_CHAR(signup_ts, 'YYYYMMDD')::INT,
    new_geo_key, new_optin, now(), TRUE
FROM closed;
