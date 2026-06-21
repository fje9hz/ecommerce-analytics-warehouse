# E-Commerce Analytics Warehouse

A PostgreSQL analytics warehouse built on the Brazilian E-Commerce Public Dataset by Olist, showing the full path from real marketplace order data to an analyst-ready dimensional model and Power BI dashboard.

This project is not a "load a CSV and write SELECT *" exercise. It models the workflow a real analytics team would use:

```text
raw landing tables -> typed staging -> Kimball marts -> analysis views -> BI dashboard
```

## 5-Minute TL;DR

- Built a 4-layer PostgreSQL warehouse over real Brazilian marketplace data: roughly 100K orders, tens of thousands of customers, product/category data, seller geography, and multi-year transaction history.
- Modeled a Kimball-style star schema with conformed dimensions, surrogate keys, line-item order facts, web-session facts, and an SCD Type 2 customer dimension.
- Wrote idempotent ETL scripts that load raw CSVs, clean and dedupe records, build marts, and run data quality checks for orphan keys, SCD2 overlaps, and revenue math consistency.
- Created 6 analyst-grade SQL outputs: cohort retention, RFM segmentation, funnel conversion, product performance, daily revenue trends, and customer LTV.
- Built an interactive Power BI dashboard for the warehouse outputs: revenue trends, RFM segments, UTM conversion rates, product-quarter performance, and cohort LTV.

## Data Source

This project uses the **Brazilian E-Commerce Public Dataset by Olist**, a real marketplace dataset with Brazilian orders, customers, sellers, products, and geography context.

The raw public files were adapted into warehouse-ready CSV inputs for this SQL pipeline. The model and dashboard are based on real marketplace data, not toy data.

## Live Dashboard

Open the public Power BI report:

[Power BI Dashboard](https://app.powerbi.com/view?r=eyJrIjoiNzgzNjI5Y2QtMzlmYy00YjM2LTlmOTMtZmZkNzkzMzk5OGM3IiwidCI6IjdiMzQ4MGM3LTM3MDctNDg3My04Yjc3LWUyMTY3MzNhNjVhYyIsImMiOjF9)

## What This Demonstrates

- **Dimensional modeling:** star schema, conformed dimensions, surrogate keys, and fact tables at clean grains.
- **SCD Type 2 history:** customer geography and profile changes are versioned with `effective_from`, `effective_to`, and `is_current`.
- **Data quality engineering:** pipeline checks fail loudly when keys orphan, SCD2 windows overlap, or fact math stops reconciling.
- **Analytical SQL:** window functions, CTEs, cohort logic, RFM scoring, funnel metrics, LTV curves, ranking, and time-series calculations.
- **BI readiness:** the `analysis` schema exposes stable views that can be consumed directly by reporting tools.

## Architecture

```text
┌─────────────┐    ┌─────────────┐    ┌──────────────┐    ┌──────────────┐
│   raw_*     │ -> │  staging_*  │ -> │  dim_* /     │ -> │  analysis    │
│  landing    │    │  cleaned    │    │  fact_*      │    │  views       │
└─────────────┘    └─────────────┘    └──────────────┘    └──────────────┘
   schema: raw      schema: staging    schema: marts       schema: analysis
```

| Schema | Purpose |
| --- | --- |
| `raw` | Append-only landing zone with loose text types and intentionally messy rows. |
| `staging` | Typed, cleaned, deduped records that downstream logic can trust. |
| `marts` | Kimball dimensional model with facts and dimensions. |
| `analysis` | Saved views for recurring business questions and BI reporting. |

## Star Schema

```text
                ┌─────────────────┐
                │   dim_date      │
                └────────┬────────┘
                         │
┌──────────────┐    ┌────┴────────┐    ┌──────────────┐
│ dim_customer │────│ fact_orders │────│ dim_product  │
│  SCD Type 2  │    └────┬────────┘    └──────────────┘
└──────────────┘         │
                ┌────────┴────────┐
                │ dim_geography   │
                └─────────────────┘

                ┌─────────────────┐
                │ fact_sessions   │
                └─────────────────┘
```

## Analysis Outputs

| File | Business question |
| --- | --- |
| `analysis/01_cohort_retention.sql` | How do monthly customer cohorts retain over time? |
| `analysis/02_rfm_segmentation.sql` | Which customers are Champions, Loyal, At Risk, or Hibernating? |
| `analysis/03_funnel.sql` | Where do sessions drop from browse to cart to checkout to purchase? |
| `analysis/04_product_performance.sql` | Which products and categories are growing or declining by quarter? |
| `analysis/05_time_series.sql` | How is daily revenue trending with 7-day and 28-day smoothing? |
| `analysis/06_customer_ltv.sql` | How does cumulative customer value compare by cohort month? |

## Repo Layout

```text
ecommerce-analytics-warehouse/
├── README.md
├── data/
│   └── csv/                         # local Olist-derived CSV inputs
├── schema/
│   ├── 01_create_schemas.sql
│   ├── 02_raw.sql
│   ├── 03_staging.sql
│   └── 04_marts.sql
├── etl/
│   ├── 01_load_raw.sql
│   ├── 02_staging.sql
│   ├── 03_build_dim_customer.sql
│   ├── 04_build_dims.sql
│   ├── 05_build_fact_orders.sql
│   ├── 06_build_fact_sessions.sql
│   └── 07_data_quality.sql
├── analysis/
│   ├── 01_cohort_retention.sql
│   ├── 02_rfm_segmentation.sql
│   ├── 03_funnel.sql
│   ├── 04_product_performance.sql
│   ├── 05_time_series.sql
│   └── 06_customer_ltv.sql
└── docs/
    └── design_decisions.md
```

## Quick Start

```bash
# 1. Start PostgreSQL
docker run --name olist-pg -e POSTGRES_PASSWORD=olist -p 5432:5432 -d postgres:16

# 2. Add the cleaned Olist-derived CSV inputs under data/csv/
# Expected files: customers.csv, products.csv, orders.csv, order_items.csv, sessions.csv

# 3. Build schemas and tables
export PGPASSWORD=olist
psql -h localhost -U postgres -f schema/01_create_schemas.sql
psql -h localhost -U postgres -f schema/02_raw.sql
psql -h localhost -U postgres -f schema/03_staging.sql
psql -h localhost -U postgres -f schema/04_marts.sql

# 4. Run ETL and quality checks
psql -h localhost -U postgres -v csv_dir="'$(pwd)/data/csv'" -f etl/01_load_raw.sql
psql -h localhost -U postgres -f etl/02_staging.sql
psql -h localhost -U postgres -f etl/03_build_dim_customer.sql
psql -h localhost -U postgres -f etl/04_build_dims.sql
psql -h localhost -U postgres -f etl/05_build_fact_orders.sql
psql -h localhost -U postgres -f etl/06_build_fact_sessions.sql
psql -h localhost -U postgres -f etl/07_data_quality.sql

# 5. Create analysis views
psql -h localhost -U postgres -f analysis/01_cohort_retention.sql
psql -h localhost -U postgres -f analysis/02_rfm_segmentation.sql
psql -h localhost -U postgres -f analysis/03_funnel.sql
psql -h localhost -U postgres -f analysis/04_product_performance.sql
psql -h localhost -U postgres -f analysis/05_time_series.sql
psql -h localhost -U postgres -f analysis/06_customer_ltv.sql
```

## Design Notes

The detailed reasoning behind the model is in [`docs/design_decisions.md`](docs/design_decisions.md). The short version:

- `raw` stores messy source rows without pretending they are clean.
- `staging` is the trust boundary.
- `marts` is optimized for analysts and BI tools.
- `analysis` gives reporting tools stable views instead of forcing every dashboard to reimplement business logic.

## Future Improvements

- Port the SQL into dbt models and tests.
- Add incremental loads with watermarks.
- Add a richer late-arriving facts test case.
- Version BI-ready extracts or semantic model documentation alongside the warehouse.

## License

MIT. Take it, fork it, make it yours.
