-- ============================================================================
-- 07_data_quality.sql
-- ----------------------------------------------------------------------------
-- Pipeline-level data-quality tests. Each check is a SELECT that returns 0
-- rows on success; non-zero rows mean the test failed. RAISE EXCEPTION halts
-- the pipeline so bad data never silently lands in the marts.
-- ============================================================================

DO $$
DECLARE v_count INT;
BEGIN
    -- ------- 1. Every fact_orders row joins to a dim_customer row ----------
    SELECT COUNT(*) INTO v_count
    FROM marts.fact_orders f
    LEFT JOIN marts.dim_customer d ON d.customer_key = f.customer_key
    WHERE d.customer_key IS NULL;
    IF v_count > 0 THEN RAISE EXCEPTION 'DQ FAIL: % orphan customers in fact_orders', v_count; END IF;

    -- ------- 2. Every fact_orders row joins to a dim_product row -----------
    SELECT COUNT(*) INTO v_count
    FROM marts.fact_orders f
    LEFT JOIN marts.dim_product d ON d.product_key = f.product_key
    WHERE d.product_key IS NULL;
    IF v_count > 0 THEN RAISE EXCEPTION 'DQ FAIL: % orphan products in fact_orders', v_count; END IF;

    -- ------- 3. Exactly one current row per customer in dim_customer ------
    SELECT COUNT(*) INTO v_count
    FROM (
        SELECT customer_id, COUNT(*) FILTER (WHERE is_current) AS n_current
        FROM marts.dim_customer
        GROUP BY customer_id
        HAVING COUNT(*) FILTER (WHERE is_current) <> 1
    ) bad;
    IF v_count > 0 THEN RAISE EXCEPTION 'DQ FAIL: % customers without exactly one current row', v_count; END IF;

    -- ------- 4. SCD2 windows don't overlap -------------------------------
    SELECT COUNT(*) INTO v_count
    FROM marts.dim_customer a
    JOIN marts.dim_customer b
      ON a.customer_id = b.customer_id
     AND a.customer_key <> b.customer_key
     AND a.effective_from < b.effective_to
     AND b.effective_from < a.effective_to;
    IF v_count > 0 THEN RAISE EXCEPTION 'DQ FAIL: % overlapping SCD2 windows', v_count; END IF;

    -- ------- 5. net_revenue is internally consistent ----------------------
    SELECT COUNT(*) INTO v_count
    FROM marts.fact_orders
    WHERE ROUND(net_revenue, 2) <> ROUND(gross_revenue - discount_amount, 2);
    IF v_count > 0 THEN RAISE EXCEPTION 'DQ FAIL: % rows with bad net_revenue math', v_count; END IF;

    -- ------- 6. No negative quantities or prices --------------------------
    SELECT COUNT(*) INTO v_count
    FROM marts.fact_orders
    WHERE quantity <= 0 OR unit_price < 0;
    IF v_count > 0 THEN RAISE EXCEPTION 'DQ FAIL: % rows with non-positive qty/price', v_count; END IF;

    RAISE NOTICE 'All data-quality checks passed.';
END $$;
