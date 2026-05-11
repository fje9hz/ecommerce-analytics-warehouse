-- ============================================================================
-- 01_create_schemas.sql
-- ----------------------------------------------------------------------------
-- Creates the four logical layers of the warehouse. Separate schemas make
-- access control and lineage easy: analysts get SELECT on `marts` and
-- `analysis`; only the ETL role can touch `raw` and `staging`.
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS marts;
CREATE SCHEMA IF NOT EXISTS analysis;

COMMENT ON SCHEMA raw       IS 'Append-only landing zone. Untyped, may contain duplicates.';
COMMENT ON SCHEMA staging   IS 'Cleaned, typed, deduplicated. One row per real-world event.';
COMMENT ON SCHEMA marts     IS 'Kimball-style dimensional model (star schema).';
COMMENT ON SCHEMA analysis  IS 'Saved analytical queries and reporting views.';
