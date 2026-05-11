-- ============================================================================
-- 02_rfm_segmentation.sql
-- ----------------------------------------------------------------------------
-- RFM (Recency, Frequency, Monetary) segmentation.
--
-- For each customer, compute:
--   • Recency:  days since last order
--   • Frequency: distinct orders in trailing 12 months
--   • Monetary: total net revenue in trailing 12 months
--
-- Score each on a 1–5 scale using NTILE, where 5 is best. Combine into
-- canonical segment names (Champions, Loyal, At Risk, etc.) using a CASE
-- expression based on the standard RFM segmentation matrix.
-- ============================================================================

CREATE OR REPLACE VIEW analysis.rfm_segments AS
WITH cutoff AS (
    SELECT MAX(d.full_date)::DATE AS as_of_date
    FROM marts.fact_orders f
    JOIN marts.dim_date d ON d.date_key = f.order_date_key
),
customer_rfm AS (
    SELECT
        f.customer_key,
        (SELECT as_of_date FROM cutoff) - MAX(d.full_date)::DATE AS recency_days,
        COUNT(DISTINCT f.order_id)                                AS frequency,
        SUM(f.net_revenue)                                        AS monetary
    FROM marts.fact_orders f
    JOIN marts.dim_date d ON d.date_key = f.order_date_key
    WHERE f.status IN ('placed','fulfilled')
      AND d.full_date >= (SELECT as_of_date - INTERVAL '365 day' FROM cutoff)
    GROUP BY f.customer_key
),
scored AS (
    SELECT
        customer_key,
        recency_days,
        frequency,
        monetary,
        -- Lower recency = better, so reverse the NTILE.
        6 - NTILE(5) OVER (ORDER BY recency_days)              AS r_score,
        NTILE(5) OVER (ORDER BY frequency)                     AS f_score,
        NTILE(5) OVER (ORDER BY monetary)                      AS m_score
    FROM customer_rfm
)
SELECT
    s.customer_key,
    dc.customer_id,
    dc.email,
    s.recency_days,
    s.frequency,
    s.monetary,
    s.r_score, s.f_score, s.m_score,
    (s.r_score::TEXT || s.f_score::TEXT || s.m_score::TEXT)    AS rfm_cell,
    CASE
        WHEN s.r_score = 5 AND s.f_score >= 4 AND s.m_score >= 4 THEN 'Champions'
        WHEN s.r_score >= 4 AND s.f_score >= 3                   THEN 'Loyal Customers'
        WHEN s.r_score = 5 AND s.f_score <= 2                    THEN 'New Customers'
        WHEN s.r_score >= 3 AND s.f_score >= 3 AND s.m_score >= 3 THEN 'Potential Loyalists'
        WHEN s.r_score >= 4 AND s.f_score <= 2                   THEN 'Promising'
        WHEN s.r_score = 3 AND s.f_score = 3                     THEN 'Need Attention'
        WHEN s.r_score <= 2 AND s.f_score >= 4                   THEN 'At Risk'
        WHEN s.r_score = 1 AND s.f_score = 5 AND s.m_score = 5   THEN 'Cannot Lose Them'
        WHEN s.r_score <= 2 AND s.f_score <= 2                   THEN 'Hibernating'
        ELSE 'Other'
    END AS segment
FROM scored s
JOIN marts.dim_customer dc
  ON dc.customer_key = s.customer_key
 AND dc.is_current;

-- ----------------------------------------------------------------------------
-- Segment size + revenue contribution
-- ----------------------------------------------------------------------------
SELECT
    segment,
    COUNT(*)                                                 AS customers,
    ROUND(AVG(recency_days), 1)                              AS avg_recency_days,
    ROUND(AVG(frequency), 2)                                 AS avg_frequency,
    ROUND(AVG(monetary), 2)                                  AS avg_monetary,
    ROUND(SUM(monetary), 2)                                  AS total_revenue,
    ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 2) AS pct_of_revenue
FROM analysis.rfm_segments
GROUP BY segment
ORDER BY total_revenue DESC;
