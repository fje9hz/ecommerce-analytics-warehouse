-- ============================================================================
-- 04_product_performance.sql
-- ----------------------------------------------------------------------------
-- Product performance with window functions:
--   • Ranking products within their category by revenue (DENSE_RANK)
--   • Each product's share of category revenue
--   • PERCENT_RANK so we can quickly grab the "top 10%" of any category
--   • Quarter-over-quarter growth using LAG
-- ============================================================================

CREATE OR REPLACE VIEW analysis.product_performance_q AS
WITH product_quarter AS (
    SELECT
        dp.product_key,
        dp.name        AS product_name,
        dp.category,
        dp.subcategory,
        d.year,
        d.quarter,
        SUM(f.net_revenue)                AS net_revenue,
        SUM(f.quantity)                   AS units_sold,
        COUNT(DISTINCT f.customer_key)    AS unique_buyers
    FROM marts.fact_orders f
    JOIN marts.dim_product dp ON dp.product_key = f.product_key
    JOIN marts.dim_date    d  ON d.date_key     = f.order_date_key
    WHERE f.status IN ('placed','fulfilled')
    GROUP BY dp.product_key, dp.name, dp.category, dp.subcategory, d.year, d.quarter
)
SELECT
    product_key, product_name, category, subcategory, year, quarter,
    net_revenue, units_sold, unique_buyers,
    DENSE_RANK() OVER (PARTITION BY category, year, quarter
                       ORDER BY net_revenue DESC)            AS rank_in_category,
    ROUND(100.0 * net_revenue
           / NULLIF(SUM(net_revenue) OVER (PARTITION BY category, year, quarter), 0),
          2)                                                  AS pct_of_category,
    ROUND(PERCENT_RANK() OVER (PARTITION BY category, year, quarter
                               ORDER BY net_revenue) * 100, 2) AS percentile_in_category,
    LAG(net_revenue) OVER (PARTITION BY product_key
                           ORDER BY year, quarter)            AS prev_quarter_revenue,
    ROUND(100.0 * (net_revenue
                   - LAG(net_revenue) OVER (PARTITION BY product_key ORDER BY year, quarter))
          / NULLIF(LAG(net_revenue) OVER (PARTITION BY product_key ORDER BY year, quarter), 0),
          2)                                                  AS qoq_growth_pct
FROM product_quarter;

-- Top 3 products in each category, latest quarter
WITH latest AS (
    SELECT MAX(year * 10 + quarter) AS yq FROM analysis.product_performance_q
)
SELECT *
FROM analysis.product_performance_q
WHERE (year * 10 + quarter) = (SELECT yq FROM latest)
  AND rank_in_category <= 3
ORDER BY category, rank_in_category;
