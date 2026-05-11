-- ============================================================================
-- 01_cohort_retention.sql
-- ----------------------------------------------------------------------------
-- Monthly cohort retention. Each cohort = customers who placed their first
-- order in a given month. We then count how many of them placed an order
-- in each subsequent month, expressed as a percentage of the cohort size.
--
-- The output is a long-format table you can pivot in any BI tool.
-- ============================================================================

CREATE OR REPLACE VIEW analysis.cohort_retention AS
WITH first_order AS (
    SELECT
        customer_key,
        DATE_TRUNC('month', MIN(d.full_date))::DATE AS cohort_month
    FROM marts.fact_orders f
    JOIN marts.dim_date d ON d.date_key = f.order_date_key
    WHERE f.status IN ('placed','fulfilled')
    GROUP BY customer_key
),
customer_activity AS (
    SELECT DISTINCT
        f.customer_key,
        DATE_TRUNC('month', d.full_date)::DATE AS activity_month
    FROM marts.fact_orders f
    JOIN marts.dim_date d ON d.date_key = f.order_date_key
    WHERE f.status IN ('placed','fulfilled')
),
joined AS (
    SELECT
        fo.cohort_month,
        ca.activity_month,
        (EXTRACT(YEAR FROM AGE(ca.activity_month, fo.cohort_month)) * 12
         + EXTRACT(MONTH FROM AGE(ca.activity_month, fo.cohort_month)))::INT AS months_since_signup,
        ca.customer_key
    FROM first_order fo
    JOIN customer_activity ca USING (customer_key)
),
cohort_size AS (
    SELECT cohort_month, COUNT(*) AS n_customers
    FROM first_order
    GROUP BY cohort_month
)
SELECT
    j.cohort_month,
    cs.n_customers                                                   AS cohort_size,
    j.months_since_signup,
    COUNT(DISTINCT j.customer_key)                                   AS active_customers,
    ROUND(100.0 * COUNT(DISTINCT j.customer_key) / cs.n_customers, 2) AS retention_pct
FROM joined j
JOIN cohort_size cs USING (cohort_month)
GROUP BY j.cohort_month, cs.n_customers, j.months_since_signup
ORDER BY j.cohort_month, j.months_since_signup;

-- ----------------------------------------------------------------------------
-- Quick look: retention curve for the three most recent cohorts.
-- ----------------------------------------------------------------------------
SELECT *
FROM analysis.cohort_retention
WHERE cohort_month >= (SELECT MAX(cohort_month) FROM analysis.cohort_retention) - INTERVAL '6 month'
ORDER BY cohort_month, months_since_signup;
