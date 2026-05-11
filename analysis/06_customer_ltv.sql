-- ============================================================================
-- 06_customer_ltv.sql
-- ----------------------------------------------------------------------------
-- A simple historical-average LTV by signup cohort.
-- For each monthly signup cohort, compute:
--   • cumulative revenue per customer through month N since signup
--   • % of cohort still active by month N
-- The output makes it easy to compare cohorts (are newer cohorts spending
-- more in their first 6 months than older ones did?).
-- ============================================================================

CREATE OR REPLACE VIEW analysis.customer_ltv AS
WITH signup AS (
    SELECT
        customer_key,
        DATE_TRUNC('month', MIN(d.full_date))::DATE AS cohort_month,
        MIN(d.full_date)::DATE                       AS signup_date
    FROM marts.fact_orders f
    JOIN marts.dim_date d ON d.date_key = f.order_date_key
    WHERE f.status IN ('placed','fulfilled')
    GROUP BY customer_key
),
revenue_by_month AS (
    SELECT
        s.cohort_month,
        s.customer_key,
        (EXTRACT(YEAR FROM AGE(DATE_TRUNC('month', d.full_date), s.cohort_month)) * 12
         + EXTRACT(MONTH FROM AGE(DATE_TRUNC('month', d.full_date), s.cohort_month)))::INT
                                                                 AS months_since_signup,
        SUM(f.net_revenue)                                       AS month_revenue
    FROM marts.fact_orders f
    JOIN marts.dim_date d ON d.date_key = f.order_date_key
    JOIN signup s         ON s.customer_key = f.customer_key
    WHERE f.status IN ('placed','fulfilled')
    GROUP BY s.cohort_month, s.customer_key, months_since_signup
),
cumulative AS (
    SELECT
        cohort_month,
        customer_key,
        months_since_signup,
        SUM(month_revenue) OVER (
            PARTITION BY customer_key
            ORDER BY months_since_signup
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS cumulative_revenue
    FROM revenue_by_month
),
cohort_sizes AS (
    SELECT cohort_month, COUNT(*) AS cohort_size
    FROM signup GROUP BY cohort_month
)
SELECT
    c.cohort_month,
    c.months_since_signup,
    cs.cohort_size,
    COUNT(DISTINCT c.customer_key)                                AS active_customers,
    ROUND(100.0 * COUNT(DISTINCT c.customer_key) / cs.cohort_size, 2) AS pct_active,
    ROUND(AVG(c.cumulative_revenue), 2)                           AS avg_cumulative_revenue_per_active,
    ROUND(SUM(c.cumulative_revenue) / cs.cohort_size, 2)          AS avg_cumulative_revenue_per_cohort_member
FROM cumulative c
JOIN cohort_sizes cs USING (cohort_month)
GROUP BY c.cohort_month, c.months_since_signup, cs.cohort_size
ORDER BY c.cohort_month, c.months_since_signup;

-- Compare LTV at month 6 across cohorts
SELECT cohort_month, cohort_size, avg_cumulative_revenue_per_cohort_member AS ltv_month_6
FROM analysis.customer_ltv
WHERE months_since_signup = 6
ORDER BY cohort_month;
