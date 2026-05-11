-- ============================================================================
-- 06_build_fact_sessions.sql
-- ----------------------------------------------------------------------------
-- Builds fact_sessions. Anonymous sessions (customer_id IS NULL in staging)
-- are kept and joined to a NULL customer_key — useful for funnel analyses
-- that include pre-login behavior.
-- ============================================================================

TRUNCATE marts.fact_sessions;

INSERT INTO marts.fact_sessions
    (session_id, session_date_key, customer_key, started_ts, ended_ts,
     duration_seconds, pages_viewed, added_to_cart, reached_checkout,
     purchased, utm_source, utm_campaign)
SELECT
    s.session_id,
    TO_CHAR(s.started_ts, 'YYYYMMDD')::INT,
    dc.customer_key,                                       -- NULL when anonymous
    s.started_ts,
    s.ended_ts,
    EXTRACT(EPOCH FROM (s.ended_ts - s.started_ts))::INT,
    s.pages_viewed,
    s.added_to_cart,
    s.reached_checkout,
    s.purchased,
    s.utm_source,
    s.utm_campaign
FROM staging.sessions s
LEFT JOIN marts.dim_customer dc
  ON dc.customer_id    = s.customer_id
 AND s.started_ts     >= dc.effective_from
 AND s.started_ts      < dc.effective_to;
