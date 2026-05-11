-- ============================================================================
-- 05_time_series.sql
-- ----------------------------------------------------------------------------
-- Daily revenue with rolling averages and YoY comparison.
--   • 7-day trailing average    — smooths the weekly cycle
--   • 28-day trailing average   — medium-term trend
--   • WoW growth                — same day-of-week last week
--   • YoY growth                — same date 365 days ago
-- ============================================================================

CREATE OR REPLACE VIEW analysis.daily_revenue AS
SELECT
    d.full_date,
    SUM(f.net_revenue)                AS net_revenue,
    COUNT(DISTINCT f.order_id)        AS orders,
    COUNT(DISTINCT f.customer_key)    AS unique_customers
FROM marts.fact_orders f
JOIN marts.dim_date    d ON d.date_key = f.order_date_key
WHERE f.status IN ('placed','fulfilled')
GROUP BY d.full_date;

CREATE OR REPLACE VIEW analysis.daily_revenue_trend AS
SELECT
    full_date,
    net_revenue,
    orders,
    unique_customers,
    ROUND(AVG(net_revenue) OVER (ORDER BY full_date
                                 ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2) AS rev_7d_avg,
    ROUND(AVG(net_revenue) OVER (ORDER BY full_date
                                 ROWS BETWEEN 27 PRECEDING AND CURRENT ROW), 2) AS rev_28d_avg,
    LAG(net_revenue, 7)   OVER (ORDER BY full_date)                              AS rev_same_dow_lw,
    LAG(net_revenue, 365) OVER (ORDER BY full_date)                              AS rev_same_day_ly,
    ROUND(100.0 * (net_revenue - LAG(net_revenue, 7)   OVER (ORDER BY full_date))
              / NULLIF(LAG(net_revenue, 7)   OVER (ORDER BY full_date), 0), 2)   AS wow_growth_pct,
    ROUND(100.0 * (net_revenue - LAG(net_revenue, 365) OVER (ORDER BY full_date))
              / NULLIF(LAG(net_revenue, 365) OVER (ORDER BY full_date), 0), 2)   AS yoy_growth_pct
FROM analysis.daily_revenue;

-- Last 30 days, smoothed
SELECT *
FROM analysis.daily_revenue_trend
ORDER BY full_date DESC
LIMIT 30;
