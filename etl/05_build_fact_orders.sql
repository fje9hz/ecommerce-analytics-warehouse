-- ============================================================================
-- 05_build_fact_orders.sql
-- ----------------------------------------------------------------------------
-- Builds fact_orders at the order-line grain.
--
-- Notes:
--   • Joins to dim_customer use the SCD2 effective-window so each order line
--     attaches to the customer's state at the time of the order — not their
--     current state. This is the correct way to do "state at point in time."
--   • A simple discount model: orders with a discount_code get 10% off gross.
--     Real shops would carry the actual amount through; this keeps the demo
--     focused on warehouse mechanics rather than coupon engines.
-- ============================================================================

TRUNCATE marts.fact_orders;

INSERT INTO marts.fact_orders
    (order_id, line_no, order_date_key, customer_key, product_key,
     quantity, unit_price, gross_revenue, discount_amount, net_revenue,
     shipping_cost, status, channel, discount_code)
SELECT
    o.order_id,
    oi.line_no,
    TO_CHAR(o.order_ts, 'YYYYMMDD')::INT                           AS order_date_key,
    dc.customer_key,
    dp.product_key,
    oi.quantity,
    oi.unit_price,
    (oi.quantity * oi.unit_price)                                   AS gross_revenue,
    CASE WHEN o.discount_code IS NOT NULL
         THEN ROUND(oi.quantity * oi.unit_price * 0.10, 2)
         ELSE 0
    END                                                             AS discount_amount,
    (oi.quantity * oi.unit_price)
      - CASE WHEN o.discount_code IS NOT NULL
             THEN ROUND(oi.quantity * oi.unit_price * 0.10, 2)
             ELSE 0
        END                                                         AS net_revenue,
    o.shipping_cost,
    o.status,
    o.channel,
    o.discount_code
FROM staging.orders o
JOIN staging.order_items oi
  ON oi.order_id = o.order_id
JOIN marts.dim_product dp
  ON dp.product_id = oi.product_id
JOIN marts.dim_customer dc
  ON dc.customer_id    = o.customer_id
 AND o.order_ts       >= dc.effective_from
 AND o.order_ts        < dc.effective_to;
