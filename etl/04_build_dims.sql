-- ============================================================================
-- 04_build_dims.sql
-- ----------------------------------------------------------------------------
-- Builds dim_product (SCD Type 1: overwrite). dim_date and dim_geography were
-- handled in 03 because dim_customer depends on them.
-- ============================================================================

-- ----- dim_product ---------------------------------------------------------
INSERT INTO marts.dim_product
    (product_id, sku, name, category, subcategory,
     current_unit_price, current_list_price, is_active)
SELECT
    product_id, sku, name, category, subcategory,
    unit_price, list_price, is_active
FROM staging.products
ON CONFLICT (product_id) DO UPDATE
SET sku                = EXCLUDED.sku,
    name               = EXCLUDED.name,
    category           = EXCLUDED.category,
    subcategory        = EXCLUDED.subcategory,
    current_unit_price = EXCLUDED.current_unit_price,
    current_list_price = EXCLUDED.current_list_price,
    is_active          = EXCLUDED.is_active;
