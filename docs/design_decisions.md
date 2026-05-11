# Design Decisions

This doc explains *why* the warehouse is shaped the way it is. If you walked into a data team tomorrow and someone asked "defend your modeling choices," these are the answers.

## 1. Four-schema layering (raw → staging → marts → analysis)

The single most important architectural choice. Each layer has one job:

- **`raw`** absorbs whatever upstream sends, including malformed rows. Everything is `TEXT`. This means a bad CSV never breaks the pipeline at ingestion — failures surface at the *staging* boundary where we have context to debug.
- **`staging`** is the first place data is trusted. It's typed, deduplicated, and constrained. Downstream consumers can treat it as authoritative.
- **`marts`** is the dimensional model. It's denormalized, indexed for analytics, and stable enough to expose to BI tools.
- **`analysis`** is the saved-query layer (views over the marts). Analysts and reports query here.

This pattern matches the standard medallion / bronze-silver-gold architecture used in production warehouses and makes role-based permissioning trivial.

## 2. Star schema over snowflake

Two reasons. First, analyst queries against a star schema are simpler to write and easier for BI tools to optimize. Second, the cost of denormalization is low when dimensions are small (millions of rows max).

The exception is `dim_geography`, which is referenced from `dim_customer` rather than copied into it. That keeps `dim_customer` slim and prevents geography drift from creating artificial customer versions.

## 3. SCD Type 2 on `dim_customer`

Customers move. If a customer in Toronto buys a coat in 2024 and then moves to Miami in 2026, the analytical question "what % of cold-weather coat sales went to cold-weather customers?" needs the *historical* state, not today's. SCD2 captures this with `effective_from` / `effective_to` / `is_current`.

The fact-build joins are explicit about it:

```sql
JOIN marts.dim_customer dc
  ON dc.customer_id    = o.customer_id
 AND o.order_ts       >= dc.effective_from
 AND o.order_ts        < dc.effective_to
```

Crucially, **most candidates have never built this**. Walking through this join in an interview is a strong signal.

## 4. SCD Type 1 on `dim_product`

Products don't really change identity. A price change is interesting, but we typically capture it in the *fact* (the `unit_price` field on `fact_orders` is the price at time of sale, not the current price). Tracking product attribute history adds complexity for little analytical payoff in most ecommerce shops.

## 5. Surrogate keys on dimensions

Every dimension has a `BIGSERIAL` surrogate key (`customer_key`, `product_key`, etc.) plus the natural key (`customer_id`, `sku`). This matters because:

- Natural keys can change (a vendor renumbers SKUs).
- SCD2 requires a key that's unique per *version*, not per *entity*.
- Smaller integer joins are faster than text joins.

`dim_date` is the exception: its key is the calendar-meaningful `YYYYMMDD` integer because it never changes and that format makes filtering easier.

## 6. Pre-populated `dim_date`

Computing date attributes on the fly is wasteful and error-prone. The table is filled once and shared across every fact. It also opens the door to attributes you can't derive from the date itself (fiscal calendars, holiday flags, retail weeks).

## 7. Two fact tables, not one

`fact_orders` is at the line-item grain. `fact_sessions` is at the session grain. Mixing them into one wide fact would force grain compromises. Keeping them separate lets each table answer a coherent set of questions while still being join-able through the conformed dimensions (`dim_customer`, `dim_date`).

## 8. Inline pipeline-level data quality tests

`etl/07_data_quality.sql` runs six assertion-style checks at the end of every ETL run. If any fail, the script raises and halts. This is much cheaper than catching the same issues from a confused stakeholder three days later.

The checks themselves are deliberately analytical: orphan keys, SCD2 window overlaps, math consistency. They mirror what you'd write in a dbt test file.

## 9. Idempotent ETL

Every transform either truncates-and-reloads (facts) or uses `ON CONFLICT` upserts (dimensions). Running the pipeline twice in a row produces an identical database state — important both for confidence and for cheap re-runs after fixes.

## 10. Discount model: deliberately simple

`fact_orders.discount_amount` is computed as a flat 10% off when `discount_code IS NOT NULL`. In a real shop you'd carry the actual line-item discount through from the source system. The toy model keeps the schema demo-friendly without burying the warehouse mechanics under coupon logic.

## What I'd add next, in priority order

1. **dbt port.** Re-implement these SQL files as dbt models. The structure is already dbt-shaped.
2. **Incremental loads.** Replace TRUNCATE-and-reload with `last_loaded_at` watermarks. Critical at any meaningful data volume.
3. **Late-arriving facts.** Add a small "out-of-order orders" test case that lands an order with `order_ts` from last month after we've already built last month's marts.
4. **A real BI surface.** A Metabase or Lightdash dashboard wired to the `analysis` schema closes the loop visually.
5. **Streaming sessions.** Sessions are the most volume-sensitive table. A CDC-fed pipeline using Debezium → Kafka → Postgres would be a natural next iteration.
