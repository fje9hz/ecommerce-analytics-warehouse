# E-Commerce Analytics Platform

A full PostgreSQL analytics project that takes raw, messy transactional data from a fictional online retailer ("Lumen Goods") and turns it into a Kimball-style dimensional warehouse with a portfolio of analyst-grade queries on top.

This isn't a "load CSV, write SELECT \*" project. It models the full path real analytics teams take:

```
 raw (landing)  →  staging (cleaned, deduped)  →  marts (star schema)  →  analysis
```

## Why this project stands out

Most SQL portfolio projects stop at "I queried a Kaggle dataset." This one demonstrates the things actually used in a data analyst's work:

- **Dimensional modeling.** A real star schema with conformed dimensions, surrogate keys, and a Type 2 slowly-changing customer dimension.
- **Data quality engineering.** Idempotent ETL, deduplication, soft-delete handling, late-arriving facts, and explicit data-quality checks baked into the pipeline.
- **Window functions and CTEs.** Every analytical query leans on them — `LAG`, `LEAD`, `ROW_NUMBER`, `NTILE`, `PERCENT_RANK`, rolling aggregates.
- **Business problems, not toy ones.** Cohort retention, RFM segmentation, funnel conversion, product affinity, and time-series decomposition.
- **Reproducibility.** A Python generator produces a fresh, realistic dataset on demand so anyone can run the project end-to-end in under five minutes.

## Architecture

```
┌─────────────┐    ┌─────────────┐    ┌──────────────┐    ┌──────────────┐
│   raw_*     │ →  │  staging_*  │ →  │  dim_* /     │ →  │  analysis    │
│  (landing)  │    │  (cleaned)  │    │  fact_*      │    │  (queries)   │
└─────────────┘    └─────────────┘    └──────────────┘    └──────────────┘
   schema: raw      schema: staging    schema: marts       schema: analysis
```

### Schemas

| Schema     | Purpose                                                                   |
| ---------- | ------------------------------------------------------------------------- |
| `raw`      | Append-only landing zone. Types are loose (text), dupes allowed.          |
| `staging`  | Cleaned, typed, deduped. One row per real-world event.                    |
| `marts`    | Dimensional model. Star schema with facts and dimensions.                 |
| `analysis` | Views and saved queries for recurring business questions.                 |

### Star schema

```
                ┌─────────────────┐
                │   dim_date      │
                └────────┬────────┘
                         │
┌──────────────┐    ┌────┴────────┐    ┌──────────────┐
│ dim_customer │────│ fact_orders │────│ dim_product  │
│  (SCD Type 2)│    └────┬────────┘    └──────────────┘
└──────────────┘         │
                ┌────────┴────────┐
                │ dim_geography   │
                └─────────────────┘

                ┌─────────────────┐
                │ fact_sessions   │ (web sessions, joined to dim_customer + dim_date)
                └─────────────────┘
```

## Repo layout

```
ecommerce-analytics-platform/
├── README.md                       # you are here
├── data/
│   └── generate_data.py            # synthetic dataset generator
├── schema/
│   ├── 01_create_schemas.sql       # raw / staging / marts / analysis
│   ├── 02_raw.sql                  # landing tables
│   ├── 03_staging.sql              # cleaned tables
│   └── 04_marts.sql                # dims + facts
├── etl/
│   ├── 01_load_raw.sql             # COPY into raw_*
│   ├── 02_staging.sql              # raw → staging transformations
│   ├── 03_build_dim_customer.sql   # SCD Type 2 logic
│   ├── 04_build_dims.sql           # product, geography, date
│   ├── 05_build_fact_orders.sql    # fact build with surrogate-key lookups
│   ├── 06_build_fact_sessions.sql  # web behavior fact
│   └── 07_data_quality.sql         # pipeline tests
├── analysis/
│   ├── 01_cohort_retention.sql     # monthly cohorts with retention curves
│   ├── 02_rfm_segmentation.sql     # RFM scoring + named segments
│   ├── 03_funnel.sql               # browse → cart → checkout → purchase
│   ├── 04_product_performance.sql  # window-function product rankings
│   ├── 05_time_series.sql          # moving avg, WoW / YoY
│   └── 06_customer_ltv.sql         # predicted LTV by cohort
└── docs/
    └── design_decisions.md         # why I made each modeling choice
```

## Quick start

```bash
# 1. Spin up PostgreSQL (any 14+ instance works; this uses Docker for portability)
docker run --name lumen-pg -e POSTGRES_PASSWORD=lumen -p 5432:5432 -d postgres:16

# 2. Generate the synthetic dataset (about 100k orders, 25k customers, 2 years)
pip install faker
python data/generate_data.py --out data/csv

# 3. Build the database
export PGPASSWORD=lumen
psql -h localhost -U postgres -f schema/01_create_schemas.sql
psql -h localhost -U postgres -f schema/02_raw.sql
psql -h localhost -U postgres -f schema/03_staging.sql
psql -h localhost -U postgres -f schema/04_marts.sql

# 4. Run the pipeline
psql -h localhost -U postgres -v csv_dir="'$(pwd)/data/csv'" -f etl/01_load_raw.sql
psql -h localhost -U postgres -f etl/02_staging.sql
psql -h localhost -U postgres -f etl/03_build_dim_customer.sql
psql -h localhost -U postgres -f etl/04_build_dims.sql
psql -h localhost -U postgres -f etl/05_build_fact_orders.sql
psql -h localhost -U postgres -f etl/06_build_fact_sessions.sql
psql -h localhost -U postgres -f etl/07_data_quality.sql

# 5. Run the analyses
psql -h localhost -U postgres -f analysis/01_cohort_retention.sql
# ... and so on
```

## Highlights for interviews

If you only have five minutes to demo this, walk through these in order:

1. **`docs/design_decisions.md`** — the "why" behind the schema. Shows you can defend choices.
2. **`etl/03_build_dim_customer.sql`** — SCD Type 2 with `effective_from` / `effective_to` and `is_current`. Most candidates have never built one.
3. **`analysis/01_cohort_retention.sql`** — cohort retention curve in one query using `GENERATE_SERIES` and a self-join on the customer dim.
4. **`analysis/02_rfm_segmentation.sql`** — RFM with `NTILE(5)` and a CASE expression that names segments ("Champions," "At Risk," "Hibernating," etc.).
5. **`etl/07_data_quality.sql`** — pipeline tests that fail loudly if a dimension loses rows or a fact has orphan foreign keys.

## What's intentionally out of scope

- Orchestration (Airflow, dbt, Dagster). The SQL is written so it could drop into dbt models with minimal change, but I wanted the focus on the SQL itself.
- BI tool (Metabase / Looker). Add one as a follow-on if you want a visual layer.
- Streaming / CDC. Everything is batch-oriented daily ETL.

## License

MIT. Take it, fork it, make it yours.
