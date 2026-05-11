-- ============================================================================
-- 03_funnel.sql
-- ----------------------------------------------------------------------------
-- Session funnel: browse → cart → checkout → purchase.
--
-- Two views:
--   • analysis.funnel_overall    — single-row totals + step-over-step rates
--   • analysis.funnel_by_source  — broken out by UTM source
-- ============================================================================

CREATE OR REPLACE VIEW analysis.funnel_overall AS
WITH counts AS (
    SELECT
        COUNT(*)                                            AS visited,
        COUNT(*) FILTER (WHERE added_to_cart)               AS carted,
        COUNT(*) FILTER (WHERE reached_checkout)            AS checked_out,
        COUNT(*) FILTER (WHERE purchased)                   AS purchased
    FROM marts.fact_sessions
)
SELECT
    visited,
    carted,
    checked_out,
    purchased,
    ROUND(100.0 * carted      / NULLIF(visited, 0),     2) AS pct_browse_to_cart,
    ROUND(100.0 * checked_out / NULLIF(carted, 0),      2) AS pct_cart_to_checkout,
    ROUND(100.0 * purchased   / NULLIF(checked_out, 0), 2) AS pct_checkout_to_purchase,
    ROUND(100.0 * purchased   / NULLIF(visited, 0),     2) AS pct_visit_to_purchase
FROM counts;

CREATE OR REPLACE VIEW analysis.funnel_by_source AS
WITH counts AS (
    SELECT
        COALESCE(utm_source, '(none)')                      AS utm_source,
        COUNT(*)                                            AS visited,
        COUNT(*) FILTER (WHERE added_to_cart)               AS carted,
        COUNT(*) FILTER (WHERE reached_checkout)            AS checked_out,
        COUNT(*) FILTER (WHERE purchased)                   AS purchased
    FROM marts.fact_sessions
    GROUP BY 1
)
SELECT
    utm_source, visited, carted, checked_out, purchased,
    ROUND(100.0 * carted      / NULLIF(visited, 0),     2) AS pct_browse_to_cart,
    ROUND(100.0 * checked_out / NULLIF(carted, 0),      2) AS pct_cart_to_checkout,
    ROUND(100.0 * purchased   / NULLIF(checked_out, 0), 2) AS pct_checkout_to_purchase,
    ROUND(100.0 * purchased   / NULLIF(visited, 0),     2) AS pct_visit_to_purchase
FROM counts
ORDER BY visited DESC;

-- Quick look
SELECT * FROM analysis.funnel_overall;
SELECT * FROM analysis.funnel_by_source LIMIT 10;
