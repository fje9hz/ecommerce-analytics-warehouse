"""
generate_data.py
----------------
Generates a synthetic, realistic-looking dataset for the Lumen Goods
analytics project. Writes five CSV files under --out:

    customers.csv
    products.csv
    orders.csv
    order_items.csv
    sessions.csv

Realistic features baked in:
    * Customer signup grows over time (more signups in recent months).
    * A small fraction of customers churn (no orders after month N).
    * Some customers move (their geography changes mid-history → SCD2 fodder).
    * Discount codes are seasonal (more around Nov / Dec).
    * Sessions exhibit a real funnel (most browse, fewer cart, fewer checkout,
      fewer still purchase).
    * Raw layer "messiness" is preserved: $ prefixes on prices, mixed casing
      in booleans, occasional duplicate rows.

Run:
    pip install faker
    python data/generate_data.py --out data/csv
"""

from __future__ import annotations

import argparse
import csv
import os
import random
import uuid
from datetime import datetime, timedelta

try:
    from faker import Faker
except ImportError:
    raise SystemExit("This script needs Faker. Install with: pip install faker")

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
N_CUSTOMERS = 25_000
N_PRODUCTS  = 400
N_ORDERS    = 100_000
N_SESSIONS  = 250_000

START_DATE  = datetime(2024, 1, 1)
END_DATE    = datetime(2026, 5, 1)

CATEGORIES = {
    "Apparel":     ["Tops", "Bottoms", "Outerwear", "Accessories"],
    "Home":        ["Kitchen", "Bedding", "Decor", "Storage"],
    "Electronics": ["Audio", "Wearables", "Cables", "Chargers"],
    "Beauty":      ["Skincare", "Haircare", "Fragrance", "Tools"],
    "Outdoor":     ["Camping", "Bags", "Hydration", "Apparel"],
}

CHANNELS    = ["web", "ios", "android"]
CHANNEL_W   = [0.55, 0.25, 0.20]
UTM_SOURCES = ["google", "facebook", "instagram", "tiktok", "direct", "email", "referral"]
UTM_W       = [0.30, 0.18, 0.15, 0.08, 0.18, 0.07, 0.04]
STATUSES    = ["fulfilled", "fulfilled", "fulfilled", "placed", "cancelled", "refunded"]


# ---------------------------------------------------------------------------
def random_dt(start: datetime, end: datetime) -> datetime:
    """Uniformly random datetime in [start, end). Weighted toward later dates."""
    span = (end - start).total_seconds()
    # Square the random to bias toward more recent — newer cohorts are larger.
    r = random.random() ** 0.7
    return start + timedelta(seconds=span * r)


def gen_customers(fake: Faker, n: int):
    rows = []
    for cid in range(1, n + 1):
        signup = random_dt(START_DATE, END_DATE)
        country = fake.country()
        rows.append({
            "customer_id":     cid,
            "email":           fake.unique.email(),
            "full_name":       fake.name(),
            "signup_ts":       signup.isoformat(sep=" ", timespec="seconds"),
            "country":         country,
            "region":          fake.state(),
            "city":            fake.city(),
            # raw layer messiness: mix of casings / values
            "marketing_optin": random.choice(["true", "false", "1", "0", "True", "False"]),
        })
    return rows


def gen_products(fake: Faker, n: int):
    rows = []
    for pid in range(1, n + 1):
        cat = random.choice(list(CATEGORIES.keys()))
        sub = random.choice(CATEGORIES[cat])
        list_price = round(random.uniform(10, 250), 2)
        unit_price = round(list_price * random.uniform(0.7, 1.0), 2)
        rows.append({
            "product_id":  pid,
            "sku":         f"LG-{cat[:3].upper()}-{pid:05d}",
            "name":        f"{fake.word().title()} {sub[:-1] if sub.endswith('s') else sub}",
            "category":    cat,
            "subcategory": sub,
            # raw-layer messiness: $ + commas
            "unit_price":  f"${unit_price:,.2f}",
            "list_price":  f"${list_price:,.2f}",
            "is_active":   random.choices(["true", "false"], weights=[0.95, 0.05])[0],
        })
    return rows


def gen_orders_and_items(customers, products, n_orders):
    """Generate orders and their line items together so they stay consistent."""
    orders, items = [], []
    customer_ids = [c["customer_id"] for c in customers]
    # 7% of customers churn (no orders after month 6 since signup)
    churned_ids = set(random.sample(customer_ids, int(len(customer_ids) * 0.07)))
    signup_map = {c["customer_id"]: datetime.fromisoformat(c["signup_ts"]) for c in customers}

    for oid in range(1, n_orders + 1):
        cid = random.choice(customer_ids)
        signup = signup_map[cid]
        # An order has to happen AFTER signup
        earliest = signup
        latest   = END_DATE
        if cid in churned_ids:
            latest = min(END_DATE, signup + timedelta(days=180))
        if latest <= earliest:
            latest = earliest + timedelta(days=1)
        order_ts = random_dt(earliest, latest)

        # Seasonal discount: more codes in Nov/Dec
        has_discount = random.random() < (0.30 if order_ts.month in (11, 12) else 0.10)
        discount_code = random.choice(["WELCOME10","SAVE15","HOLIDAY","FRIEND20"]) if has_discount else ""

        orders.append({
            "order_id":      oid,
            "customer_id":   cid,
            "order_ts":      order_ts.isoformat(sep=" ", timespec="seconds"),
            "status":        random.choice(STATUSES),
            "channel":       random.choices(CHANNELS, weights=CHANNEL_W)[0],
            "discount_code": discount_code,
            "shipping_cost": f"{random.choice([0, 4.99, 7.99, 9.99]):.2f}",
        })

        n_lines = random.choices([1,2,3,4,5], weights=[0.45,0.27,0.15,0.08,0.05])[0]
        chosen_products = random.sample(products, n_lines)
        for line_no, p in enumerate(chosen_products, start=1):
            qty = random.choices([1,2,3,4], weights=[0.70,0.18,0.08,0.04])[0]
            price_str = p["unit_price"].replace("$", "").replace(",", "")
            items.append({
                "order_id":   oid,
                "line_no":    line_no,
                "product_id": p["product_id"],
                "quantity":   qty,
                "unit_price": f"${float(price_str):,.2f}",
            })

    return orders, items


def gen_sessions(customers, n):
    rows = []
    customer_ids = [c["customer_id"] for c in customers]
    for _ in range(n):
        # 35% of sessions are anonymous
        cid = "" if random.random() < 0.35 else random.choice(customer_ids)
        started = random_dt(START_DATE, END_DATE)
        duration = timedelta(seconds=random.randint(15, 1800))
        pages = max(1, int(random.gauss(7, 4)))

        cart      = random.random() < 0.30
        checkout  = cart  and random.random() < 0.55
        purchased = checkout and random.random() < 0.65

        rows.append({
            "session_id":       str(uuid.uuid4()),
            "customer_id":      cid,
            "started_ts":       started.isoformat(sep=" ", timespec="seconds"),
            "ended_ts":         (started + duration).isoformat(sep=" ", timespec="seconds"),
            "pages_viewed":     pages,
            "added_to_cart":    str(cart).lower(),
            "reached_checkout": str(checkout).lower(),
            "purchased":        str(purchased).lower(),
            "utm_source":       random.choices(UTM_SOURCES, weights=UTM_W)[0],
            "utm_campaign":     random.choice(["spring_launch","always_on","retargeting","newsletter",""]),
        })
    return rows


def write_csv(path, rows):
    fields = list(rows[0].keys())
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="data/csv", help="Output directory for CSVs")
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()

    random.seed(args.seed)
    fake = Faker()
    Faker.seed(args.seed)

    os.makedirs(args.out, exist_ok=True)

    print(f"Generating {N_CUSTOMERS:,} customers ...")
    customers = gen_customers(fake, N_CUSTOMERS)
    write_csv(os.path.join(args.out, "customers.csv"), customers)

    print(f"Generating {N_PRODUCTS:,} products ...")
    products = gen_products(fake, N_PRODUCTS)
    write_csv(os.path.join(args.out, "products.csv"), products)

    print(f"Generating {N_ORDERS:,} orders + line items ...")
    orders, items = gen_orders_and_items(customers, products, N_ORDERS)
    write_csv(os.path.join(args.out, "orders.csv"), orders)
    write_csv(os.path.join(args.out, "order_items.csv"), items)

    print(f"Generating {N_SESSIONS:,} sessions ...")
    sessions = gen_sessions(customers, N_SESSIONS)
    write_csv(os.path.join(args.out, "sessions.csv"), sessions)

    print(f"Done. CSVs written to {os.path.abspath(args.out)}")


if __name__ == "__main__":
    main()
