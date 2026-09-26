# DAX Measures Reference

This document lists every DAX measure used across the 5-page Power BI dashboard, grouped by the page where it's primarily used. All measures live in a dedicated `_Measures` table inside the `.pbix` file (a common Power BI best practice for keeping measures organized and easy to find).

## Change log vs. original version

1. **Avg Turnover Ratio** (Page 5) — was a plain `AVERAGE()` of 35 per-product ratios, which is what produced the misleading "~1.3x" headline (it treats every product as equally important regardless of how much inventory it holds). Replaced with a weighted calculation: total annualized COGS ÷ total inventory value. Correct value is ~1.49x. The measure **name is kept the same** so existing visuals don't break — only the formula changed.
2. **Avg DIO** (Page 5) — was `AVERAGE()` of per-product DIO (which also silently ignored the 5 dead products' now-`NULL` DIO, per the corrected view). Redefined as `365 / [Avg Turnover Ratio]` so it stays mathematically consistent with the corrected turnover figure above, rather than being a second, differently-biased average.
3. **Reorder Alert Count** (Page 1, reused on Page 4) — `vw_reorder_analysis` is now at product-**warehouse** grain (105 rows) instead of product grain (35 rows). Changed `DISTINCTCOUNT(product_id)` to `COUNTROWS()`, so the count reflects actual reorder actions needed (one per product-warehouse combination), not just how many distinct products are affected. Currently both give the same number (1), but they won't always agree once more than one warehouse for the same product needs reordering.
4. **Import Supplier Dead Stock %** (Page 1) — formula unchanged (it's still an accurate calculation), but its note is corrected. This number shows *where* dead stock capital sits, not *why* it happened — the original documentation over-claimed the second part. See the two NEW measures below, which test the actual cause.
5. **Two NEW measures added** (Page 1) — `Avg Buy-to-Sell Ratio (Active Products)` and `Late Purchases % of Dead Stock`, supporting `vw_buy_to_sell` and `vw_purchases_after_last_sale`. These are what actually test (and disprove) the "long lead times caused it" claim, and identify the real cause (ordering continued after demand stopped).
6. All other measures — Total Inventory Value, Dead Stock Value/%, Active Stock Value, ABC/XYZ/Segment measures, Dead Stock Capital/Item Count/Average Idle Days, Avg Lead Time, Total Products Monitored, Reorder Sort Priority, Monthly Sales/Purchase Value — are **unchanged**. They read correctly from the corrected views/tables automatically; no formula edits were needed. (Monthly Purchase Value will show slightly different historical numbers purely because the underlying transactions.csv now has 14 corrected purchase prices — not because this measure's DAX changed.)

---

## Page 1 — Executive Overview

**Total Inventory Value**
```dax
Total Inventory Value = SUM(vw_stock_aging[tied_up_capital])
```

**Total Inventory Units**
```dax
Total Inventory Units = SUM(vw_stock_aging[current_stock])
```

**Dead Stock Value**
```dax
Dead Stock Value =
CALCULATE(
    SUM(vw_stock_aging[tied_up_capital]),
    vw_stock_aging[aging_bucket] = "Dead Stock"
)
```

**Dead Stock %**
```dax
Dead Stock % =
DIVIDE([Dead Stock Value], [Total Inventory Value], 0)
```

**Active Stock Value**
```dax
Active Stock Value =
CALCULATE(
    SUM(vw_stock_aging[tied_up_capital]),
    vw_stock_aging[aging_bucket] = "Active"
)
```

**Reorder Alert Count**

> FIXED: now counts product-warehouse combinations (COUNTROWS),
> not distinct products (DISTINCTCOUNT) — see change log item 3.
> Still returns BLANK() when nothing matches, so COALESCE is kept.

```dax
Reorder Alert Count =
VAR AlertCount =
    CALCULATE(
        COUNTROWS(vw_reorder_analysis),
        vw_reorder_analysis[reorder_status] = "Reorder Now"
    )
RETURN
    COALESCE(AlertCount, 0)
```

**A Category Count**
```dax
A Category Count =
CALCULATE(
    DISTINCTCOUNT(vw_abc_analysis[product_id]),
    vw_abc_analysis[abc_category] = "A"
)
```

**CZ Segment Count**
```dax
CZ Segment Count =
CALCULATE(
    DISTINCTCOUNT(vw_abc_xyz_matrix[product_id]),
    vw_abc_xyz_matrix[combined_segment] = "CZ"
)
```

**CZ Segment Revenue**
```dax
CZ Segment Revenue =
CALCULATE(
    SUM(vw_abc_xyz_matrix[total_revenue]),
    vw_abc_xyz_matrix[combined_segment] = "CZ"
)
```

**Total Revenue**
```dax
Total Revenue = SUM(vw_abc_analysis[total_revenue])
```

**Import Supplier Dead Stock %**

> NOTE (corrected): this shows what share of dead-stock capital sits
> with non-local suppliers — a WHERE, not a WHY. It does not by
> itself show that import suppliers caused the dead stock (the two
> measures below test that claim directly, and don't support it).

```dax
Import Supplier Dead Stock % =
DIVIDE(
    CALCULATE(
        SUM(vw_supplier_performance[dead_stock_capital]),
        vw_supplier_performance[country] <> "Bangladesh"
    ),
    SUM(vw_supplier_performance[dead_stock_capital]),
    0
)
```

**Avg Buy-to-Sell Ratio (Active Products)** *(NEW)*

> Average purchase-to-sale ratio across all products EXCEPT the 5
> dead-stock ones. Compare this against the same ratio filtered to
> just the 3 healthy import products (PRD027, PRD029, PRD030) in a
> table visual — they fall inside this range, not above it, which is
> what shows long lead times did NOT cause oversized orders.

```dax
Avg Buy-to-Sell Ratio (Active Products) =
CALCULATE(
    AVERAGE(vw_buy_to_sell[buy_to_sell_ratio]),
    FILTER(
        vw_buy_to_sell,
        NOT(vw_buy_to_sell[product_id] IN {"PRD031","PRD032","PRD033","PRD034","PRD035"})
    )
)
```

**Late Purchases % of Dead Stock** *(NEW)*

> Share of total dead-stock capital that came specifically from
> Purchase transactions made after the product had already stopped
> selling. This is the direct, demonstrable cause (~51%), as opposed
> to the supplier-reliability coincidence the original report relied on.

```dax
Capital From Late Purchases =
SUM(vw_purchases_after_last_sale[purchase_value])

Late Purchases % of Dead Stock =
DIVIDE([Capital From Late Purchases], [Dead Stock Value], 0)
```

---

## Page 2 — ABC-XYZ Segmentation

**Segment Product Count**
```dax
Segment Product Count = DISTINCTCOUNT(vw_abc_xyz_matrix[product_id])
```

**Segment Revenue**
```dax
Segment Revenue = SUM(vw_abc_xyz_matrix[total_revenue])
```

*(Used as the matrix heatmap's color-by value — driving the conditional background-color gradient across the 9-segment grid.)*

---

## Page 3 — Dead & Slow Stock Report

**Dead Stock Capital**
```dax
Dead Stock Capital =
CALCULATE(
    SUM(vw_stock_aging[tied_up_capital]),
    vw_stock_aging[aging_bucket] = "Dead Stock"
)
```

**Dead Stock Item Count**

> Counts product-warehouse *combinations*, not unique products — this
> intentionally matches the granularity of the "Top Dead Stock Items"
> table (15 rows), not the unique product count (5).

```dax
Dead Stock Item Count =
CALCULATE(
    COUNTROWS(vw_stock_aging),
    vw_stock_aging[aging_bucket] = "Dead Stock"
)
```

**Average Idle Days**
```dax
Average Idle Days =
CALCULATE(
    AVERAGE(vw_stock_aging[days_since_last_sale]),
    vw_stock_aging[aging_bucket] = "Dead Stock"
)
```

> Note: this now averages ~525 days (was ~538) purely because the
> underlying view's reference date was corrected to the data's actual
> last transaction date — no change needed here, it flows through
> automatically.

---

## Page 4 — Reorder Alert Panel

**Average Supplier Lead Time**
```dax
Avg Lead Time = AVERAGE(dim_supplier[lead_time_days])
```

**Total Products Monitored**
```dax
Total Products Monitored = DISTINCTCOUNT(vw_reorder_analysis[product_id])
```

> Unchanged — still correctly returns 35 distinct products even
> though the underlying view now has 105 rows (product-warehouse
> grain). Kept as DISTINCTCOUNT deliberately, since this card is
> meant to answer "how many products are we tracking", not "how many
> combinations".

**Reorder Sort Priority** *(Calculated Column, not a measure)*

> Used purely to force "Reorder Now" rows to sort above "Sufficient
> Stock" rows in the status table — DAX measures can't be used for
> row-level custom sort, so this is a calculated column instead.
> Note: this table visual now shows up to 105 rows (one per
> product-warehouse combination) instead of 35 — a report-layout
> consideration, not a DAX issue. Add the warehouse_name column to
> the table visual so rows are distinguishable.

```dax
Reorder Sort Priority =
IF(vw_reorder_analysis[reorder_status] = "Reorder Now", 1, 2)
```

*(`Reorder Alert Count`, defined under Page 1, is reused here — see change log item 3 for what changed.)*

---

## Page 5 — Trend Analysis

**Monthly Sales Value**
```dax
Monthly Sales Value =
CALCULATE(
    SUMX(fact_inventory_transactions, ABS(fact_inventory_transactions[quantity]) * fact_inventory_transactions[unit_price]),
    fact_inventory_transactions[transaction_type] = "Sale",
    fact_inventory_transactions[data_issue] = 0
)
```

**Monthly Purchase Value**
```dax
Monthly Purchase Value =
CALCULATE(
    SUMX(fact_inventory_transactions, fact_inventory_transactions[quantity] * fact_inventory_transactions[unit_price]),
    fact_inventory_transactions[transaction_type] = "Purchase",
    fact_inventory_transactions[data_issue] = 0
)
```

**Avg Turnover Ratio**

> FIXED: was `AVERAGE()` of 35 per-product ratios (the misleading
> "~1.3x"). Now a weighted calculation — total annualized COGS
> divided by total inventory value. Correct value is ~1.49x. See
> change log item 1. Formula name kept the same so existing visuals
> referencing it don't need to be rewired.

```dax
Avg Turnover Ratio =
DIVIDE(
    SUMX(vw_inventory_turnover, vw_inventory_turnover[recent_annualized_cogs]),
    SUM(vw_inventory_turnover[current_inventory_value]),
    0
)
```

**Avg DIO**

> FIXED: derived from the corrected [Avg Turnover Ratio] above
> instead of averaging per-product DIO values directly. See change
> log item 2.

```dax
Avg DIO =
DIVIDE(365, [Avg Turnover Ratio], BLANK())
```

**Category Weighted Turnover** *(NEW — optional, for a category breakdown table/chart)*

```dax
Category Weighted Turnover =
DIVIDE(
    SUMX(vw_inventory_turnover, vw_inventory_turnover[recent_annualized_cogs]),
    SUM(vw_inventory_turnover[current_inventory_value]),
    0
)
```
*(Same formula as `Avg Turnover Ratio` — works correctly when sliced by `category` in a table/matrix visual, since it recomputes the weighted ratio within whatever filter context the visual applies. A separate measure name is provided only for clarity in report visuals; either measure name can be used.)*

---

## Design Notes

- **`DIVIDE()` instead of `/`** is used everywhere a ratio is calculated, since it returns a safe fallback value (usually `0`) instead of throwing a division-by-zero error.
- **`CALCULATE()`** is the backbone of almost every conditional measure here — it temporarily applies a filter (e.g., "only Dead Stock rows") before aggregating.
- **`COALESCE()`** is used specifically where a `CALCULATE` filter can return zero matching rows, which DAX treats as `BLANK()` rather than `0` — and `BLANK()` renders as a confusing `--` on card visuals.
- All measures referencing `data_issue = 0` are intentionally filtering out the rows flagged during the SQL data-quality fixes (see `03_data_quality_fixes.sql`), so the dashboard never includes excluded/unreliable data.
- **Weighted vs. simple average**, as a general rule for this dashboard: whenever a ratio measure (turnover, buy-to-sell, etc.) is aggregated across products, prefer `SUM(numerator)/SUM(denominator)` over `AVERAGE(per-row ratio)`. The latter treats a small SKU and a large SKU as equally important, which is what caused the original turnover headline to be misleading.
