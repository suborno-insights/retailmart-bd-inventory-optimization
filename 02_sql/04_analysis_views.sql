/* =====================================================================
   RetailMart BD — Inventory Optimization & Dead Stock Detection
   04_analysis_views.sql  (CORRECTED)

   Purpose: Create the analytical views that power the Power BI
            dashboard. All views exclude flagged rows (data_issue = 0)
            unless otherwise noted.

   CHANGE LOG vs. original version
   --------------------------------
   1. vw_stock_aging — reference date fixed from '2024-12-31' to
      '2024-12-18', the dataset's actual last transaction date. The
      old date was 13 days past the real end of the data, which
      inflated every "days since last sale" figure and created an
      entire "Slow Moving" bucket (6 combos, ~৳0.53M) that doesn't
      actually exist — a pure artifact of that 13-day gap. With the
      fix, Slow Moving and At Risk are both genuinely empty: the
      aging split is a clean 90 Active / 15 Dead Stock. Dead stock
      capital and product/combo counts are unchanged (৳75,980 / 5
      products / 15 combos) — only the "days idle" figures shift
      down by ~13 days each.

   2. vw_abc_analysis — the running-total window now uses an explicit
      ROWS frame instead of the default RANGE, so the cumulative %
      is deterministic even if two products ever land on the same
      revenue value (no ties currently exist in this data).

   3. vw_xyz_analysis, vw_abc_xyz_matrix — unchanged; verified they
      don't depend on the aging reference date (XYZ uses complete
      calendar months, not a "days since" calculation).

   4. vw_reorder_analysis — grain changed from product-level to
      product-warehouse-level. The original compared one company-
      wide reorder point against total stock summed across all 3
      warehouses, which could mask a specific warehouse running low.
      Also, the averaging window changed from a 730-day calendar
      grid ('2023-01-01' to '2024-12-31') to 718 days (ending at the
      data's actual last date), since the old window padded in 13
      days of activity that never happened. Net effect: 1 genuine
      reorder alert now surfaces (Aromatherapy Diffuser at WH002)
      that the old company-level view had masked to zero.

   5. vw_inventory_turnover — the "recent window" no longer starts on
      a hardcoded '2024-07-01'. It's now the 182 days ending at
      MAX(transaction_date), computed dynamically. The old version's
      effective window was only 171 days (since data ends 12-18) but
      was still multiplied by a flat x2 (which assumes 182.5 days),
      understating annualized COGS for every product by ~6%. The
      annualization factor is now exactly 365/182. DIO's divide-by-
      zero case now returns NULL instead of the placeholder 999,
      since 999 was silently distorting any AVG() taken over it. Both
      recent_annualized_cogs and current_inventory_value are kept as
      separate columns so a correct COMPANY- or CATEGORY-level
      weighted turnover can be computed as SUM(cogs)/SUM(inventory)
      — averaging the 35 per-product ratios (the original approach)
      is what produced the misleading "~1.3x" headline; the correct
      weighted company turnover is ~1.49x.

   6. vw_supplier_performance — unchanged; logic was already correct.

   7. Two NEW views added — vw_buy_to_sell and
      vw_purchases_after_last_sale — to directly test the original
      documentation's claim that "long lead times forced oversized
      buffer orders, causing the dead stock." That claim rested only
      on a coincidence (the two dead-stock suppliers also happen to
      have the lowest reliability scores), and doesn't survive a
      direct test: the 3 HEALTHY import products (same suppliers,
      same lead times) have buy-to-sell ratios well inside the normal
      range for all active products. The real, demonstrable cause is
      that purchasing continued for months after each of the 5 dead
      products had already stopped selling — accounting for 51% of
      the total dead-stock capital.
   ===================================================================== */

USE RetailMart_BD;
GO

-- =====================================================================
-- VIEW 1: ABC Analysis — classifies products by revenue contribution
-- (A = top 70%, B = next 20%, C = bottom 10%)
-- =====================================================================

CREATE OR ALTER VIEW vw_abc_analysis AS
WITH product_revenue AS (
    SELECT
        f.product_id,
        p.product_name,
        p.category,
        SUM(ABS(f.quantity) * f.unit_price) AS total_revenue
    FROM fact_inventory_transactions f
    JOIN dim_product p ON f.product_id = p.product_id
    WHERE f.transaction_type = 'Sale'
      AND f.data_issue = 0
    GROUP BY f.product_id, p.product_name, p.category
),
ranked_revenue AS (
    SELECT
        *,
        SUM(total_revenue) OVER () AS grand_total_revenue,
        SUM(total_revenue) OVER (
            ORDER BY total_revenue DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS running_total,
        ROW_NUMBER() OVER (ORDER BY total_revenue DESC) AS revenue_rank
    FROM product_revenue
)
SELECT
    revenue_rank,
    product_id,
    product_name,
    category,
    total_revenue,
    ROUND(total_revenue * 100.0 / grand_total_revenue, 2) AS revenue_pct,
    ROUND(running_total * 100.0 / grand_total_revenue, 2) AS cumulative_pct,
    CASE
        WHEN running_total * 100.0 / grand_total_revenue <= 70 THEN 'A'
        WHEN running_total * 100.0 / grand_total_revenue <= 90 THEN 'B'
        ELSE 'C'
    END AS abc_category
FROM ranked_revenue;
GO

-- =====================================================================
-- VIEW 2: XYZ Analysis — classifies products by demand volatility
-- (Coefficient of Variation over a complete 24-month grid)
-- =====================================================================

CREATE OR ALTER VIEW vw_xyz_analysis AS
WITH all_months AS (
    SELECT DISTINCT year, month_number
    FROM dim_date
    WHERE full_date BETWEEN '2023-01-01' AND '2024-12-31'
),
all_product_months AS (
    SELECT
        p.product_id,
        m.year,
        m.month_number
    FROM dim_product p
    CROSS JOIN all_months m
),
actual_monthly_sales AS (
    SELECT
        f.product_id,
        YEAR(f.transaction_date)  AS sale_year,
        MONTH(f.transaction_date) AS sale_month,
        SUM(ABS(f.quantity))      AS monthly_qty
    FROM fact_inventory_transactions f
    WHERE f.transaction_type = 'Sale'
      AND f.data_issue = 0
    GROUP BY f.product_id, YEAR(f.transaction_date), MONTH(f.transaction_date)
),
complete_monthly_sales AS (
    SELECT
        apm.product_id,
        apm.year,
        apm.month_number,
        COALESCE(ams.monthly_qty, 0) AS monthly_qty
    FROM all_product_months apm
    LEFT JOIN actual_monthly_sales ams
        ON apm.product_id = ams.product_id
       AND apm.year = ams.sale_year
       AND apm.month_number = ams.sale_month
),
product_stats AS (
    SELECT
        product_id,
        AVG(monthly_qty * 1.0)   AS avg_monthly_sales,
        STDEV(monthly_qty * 1.0) AS stdev_monthly_sales,
        COUNT(*)                 AS total_months,
        SUM(CASE WHEN monthly_qty = 0 THEN 1 ELSE 0 END) AS zero_sale_months
    FROM complete_monthly_sales
    GROUP BY product_id
)
SELECT
    p.product_id,
    pr.product_name,
    p.avg_monthly_sales,
    p.stdev_monthly_sales,
    p.total_months,
    p.zero_sale_months,
    ROUND(
        CASE WHEN p.avg_monthly_sales = 0 THEN 999
             ELSE (p.stdev_monthly_sales / p.avg_monthly_sales) * 100
        END, 2
    ) AS coefficient_of_variation,
    CASE
        WHEN p.avg_monthly_sales = 0 THEN 'Z'
        WHEN (p.stdev_monthly_sales / p.avg_monthly_sales) * 100 <= 20 THEN 'X'
        WHEN (p.stdev_monthly_sales / p.avg_monthly_sales) * 100 <= 50 THEN 'Y'
        ELSE 'Z'
    END AS xyz_category
FROM product_stats p
JOIN dim_product pr ON p.product_id = pr.product_id;
GO

-- =====================================================================
-- VIEW 3: ABC-XYZ Combined Matrix — joins Views 1 and 2
-- =====================================================================

CREATE OR ALTER VIEW vw_abc_xyz_matrix AS
SELECT
    a.product_id,
    a.product_name,
    a.category,
    a.total_revenue,
    a.revenue_pct,
    a.abc_category,
    x.avg_monthly_sales,
    x.coefficient_of_variation,
    x.zero_sale_months,
    x.xyz_category,
    a.abc_category + x.xyz_category AS combined_segment
FROM vw_abc_analysis a
JOIN vw_xyz_analysis x ON a.product_id = x.product_id;
GO

-- =====================================================================
-- VIEW 4: Stock Aging Analysis — days since last sale and tied-up
-- capital, per product-warehouse combination
-- =====================================================================

CREATE OR ALTER VIEW vw_stock_aging AS
WITH last_sale AS (
    SELECT
        product_id,
        warehouse_id,
        MAX(transaction_date) AS last_sale_date
    FROM fact_inventory_transactions
    WHERE transaction_type = 'Sale'
      AND data_issue = 0
    GROUP BY product_id, warehouse_id
),
current_stock AS (
    SELECT
        product_id,
        warehouse_id,
        stock_balance,
        ROW_NUMBER() OVER (
            PARTITION BY product_id, warehouse_id
            ORDER BY transaction_date DESC, transaction_id DESC
        ) AS rn
    FROM fact_inventory_transactions
    WHERE data_issue = 0
)
SELECT
    cs.product_id,
    p.product_name,
    p.category,
    cs.warehouse_id,
    w.warehouse_name,
    cs.stock_balance AS current_stock,
    p.unit_cost,
    ROUND(cs.stock_balance * p.unit_cost, 2) AS tied_up_capital,
    ls.last_sale_date,
    DATEDIFF(DAY, ls.last_sale_date, '2024-12-18') AS days_since_last_sale,
    CASE
        WHEN ls.last_sale_date IS NULL THEN 'Never Sold'
        WHEN DATEDIFF(DAY, ls.last_sale_date, '2024-12-18') <= 30 THEN 'Active'
        WHEN DATEDIFF(DAY, ls.last_sale_date, '2024-12-18') <= 60 THEN 'Slow Moving'
        WHEN DATEDIFF(DAY, ls.last_sale_date, '2024-12-18') <= 90 THEN 'At Risk'
        ELSE 'Dead Stock'
    END AS aging_bucket
FROM current_stock cs
JOIN dim_product p ON cs.product_id = p.product_id
JOIN dim_warehouse w ON cs.warehouse_id = w.warehouse_id
LEFT JOIN last_sale ls
    ON cs.product_id = ls.product_id
   AND cs.warehouse_id = ls.warehouse_id
WHERE cs.rn = 1;
GO

-- =====================================================================
-- VIEW 5: Reorder Point Analysis (product-warehouse level)
-- =====================================================================

CREATE OR ALTER VIEW vw_reorder_analysis AS
WITH daily_variability AS (
    SELECT
        f.product_id,
        f.warehouse_id,
        f.transaction_date,
        SUM(ABS(f.quantity)) AS daily_qty
    FROM fact_inventory_transactions f
    WHERE f.transaction_type = 'Sale'
      AND f.data_issue = 0
    GROUP BY f.product_id, f.warehouse_id, f.transaction_date
),
all_days AS (
    SELECT full_date FROM dim_date WHERE full_date BETWEEN '2023-01-01' AND '2024-12-18'
),
complete_daily AS (
    SELECT
        p.product_id,
        wh.warehouse_id,
        d.full_date,
        COALESCE(dv.daily_qty, 0) AS daily_qty
    FROM dim_product p
    CROSS JOIN dim_warehouse wh
    CROSS JOIN all_days d
    LEFT JOIN daily_variability dv
        ON p.product_id = dv.product_id
       AND wh.warehouse_id = dv.warehouse_id
       AND d.full_date = dv.transaction_date
),
daily_sales_stats AS (
    SELECT
        product_id,
        warehouse_id,
        AVG(daily_qty * 1.0)   AS avg_daily_sales,
        STDEV(daily_qty * 1.0) AS stdev_daily_sales
    FROM complete_daily
    GROUP BY product_id, warehouse_id
)
SELECT
    d.product_id,
    p.product_name,
    p.category,
    d.warehouse_id,
    w.warehouse_name,
    s.supplier_name,
    s.lead_time_days,
    ROUND(d.avg_daily_sales, 3)   AS avg_daily_sales,
    ROUND(d.stdev_daily_sales, 3) AS stdev_daily_sales,
    ROUND(d.avg_daily_sales * s.lead_time_days, 1) AS lead_time_demand,
    -- Safety stock uses a Z-score of 1.65 (95% service level)
    ROUND(1.65 * d.stdev_daily_sales * SQRT(s.lead_time_days), 1) AS safety_stock,
    ROUND(
        (d.avg_daily_sales * s.lead_time_days) +
        (1.65 * d.stdev_daily_sales * SQRT(s.lead_time_days))
    , 0) AS reorder_point,
    sa.current_stock,
    p.reorder_level AS existing_reorder_level_in_master,
    CASE
        WHEN sa.current_stock <= ROUND(
            (d.avg_daily_sales * s.lead_time_days) +
            (1.65 * d.stdev_daily_sales * SQRT(s.lead_time_days))
        , 0) THEN 'Reorder Now'
        ELSE 'Sufficient Stock'
    END AS reorder_status
FROM daily_sales_stats d
JOIN dim_product p ON d.product_id = p.product_id
JOIN dim_warehouse w ON d.warehouse_id = w.warehouse_id
JOIN dim_supplier s ON p.supplier_id = s.supplier_id
JOIN vw_stock_aging sa
    ON d.product_id = sa.product_id AND d.warehouse_id = sa.warehouse_id;
GO

-- =====================================================================
-- VIEW 6: Inventory Turnover Ratio (product-level)
-- =====================================================================

CREATE OR ALTER VIEW vw_inventory_turnover AS
WITH ref AS (
    SELECT MAX(transaction_date) AS max_date
    FROM fact_inventory_transactions
    WHERE data_issue = 0
),
window_bounds AS (
    SELECT
        max_date                          AS window_end,
        DATEADD(DAY, -181, max_date)      AS window_start   -- 182-day window
    FROM ref
),
cogs_recent AS (
    SELECT
        f.product_id,
        SUM(ABS(f.quantity) * p.unit_cost) AS recent_cogs
    FROM fact_inventory_transactions f
    JOIN dim_product p ON f.product_id = p.product_id
    CROSS JOIN window_bounds wb
    WHERE f.transaction_type = 'Sale'
      AND f.data_issue = 0
      AND f.transaction_date BETWEEN wb.window_start AND wb.window_end
    GROUP BY f.product_id
),
cogs_full AS (
    SELECT
        f.product_id,
        SUM(ABS(f.quantity) * p.unit_cost) AS total_cogs_24mo
    FROM fact_inventory_transactions f
    JOIN dim_product p ON f.product_id = p.product_id
    WHERE f.transaction_type = 'Sale'
      AND f.data_issue = 0
    GROUP BY f.product_id
),
avg_inventory AS (
    SELECT
        product_id,
        SUM(current_stock)   AS total_current_stock,
        SUM(tied_up_capital) AS current_inventory_value
    FROM vw_stock_aging
    GROUP BY product_id
)
SELECT
    p.product_id,
    p.product_name,
    p.category,
    COALESCE(cr.recent_cogs, 0)                        AS recent_window_cogs,
    ROUND(COALESCE(cr.recent_cogs, 0) * 365.0 / 182, 2) AS recent_annualized_cogs,
    cf.total_cogs_24mo,
    a.current_inventory_value,
    ROUND(
        CASE WHEN a.current_inventory_value = 0 THEN 0
             ELSE (COALESCE(cr.recent_cogs, 0) * 365.0 / 182) / a.current_inventory_value
        END
    , 2) AS annualized_turnover_ratio,
    CASE
        WHEN COALESCE(cr.recent_cogs, 0) = 0 THEN NULL   -- no sales in the window: DIO not meaningful
        WHEN a.current_inventory_value = 0 THEN 0
        ELSE ROUND(365.0 / ((cr.recent_cogs * 365.0 / 182) / a.current_inventory_value), 0)
    END AS days_inventory_outstanding
FROM cogs_full cf
JOIN dim_product p ON cf.product_id = p.product_id
JOIN avg_inventory a ON cf.product_id = a.product_id
LEFT JOIN cogs_recent cr ON cf.product_id = cr.product_id;
GO

-- =====================================================================
-- VIEW 7: Supplier Performance (unchanged from original)
-- =====================================================================

CREATE OR ALTER VIEW vw_supplier_performance AS
WITH supplier_cogs AS (
    SELECT
        p.supplier_id,
        SUM(ABS(f.quantity) * p.unit_cost) AS total_cogs
    FROM fact_inventory_transactions f
    JOIN dim_product p ON f.product_id = p.product_id
    WHERE f.transaction_type = 'Sale'
      AND f.data_issue = 0
    GROUP BY p.supplier_id
),
supplier_dead_stock AS (
    SELECT
        p.supplier_id,
        COUNT(DISTINCT a.product_id) AS dead_product_count,
        SUM(a.tied_up_capital) AS dead_stock_capital
    FROM vw_stock_aging a
    JOIN dim_product p ON a.product_id = p.product_id
    WHERE a.aging_bucket = 'Dead Stock'
    GROUP BY p.supplier_id
),
supplier_product_count AS (
    SELECT
        supplier_id,
        COUNT(*) AS total_products_supplied
    FROM dim_product
    GROUP BY supplier_id
)
SELECT
    s.supplier_id,
    s.supplier_name,
    s.country,
    s.lead_time_days,
    s.reliability_score,
    spc.total_products_supplied,
    COALESCE(sc.total_cogs, 0)              AS total_cogs_contribution,
    COALESCE(sds.dead_product_count, 0)     AS dead_product_count,
    COALESCE(sds.dead_stock_capital, 0)     AS dead_stock_capital,
    ROUND(
        COALESCE(sds.dead_product_count, 0) * 100.0 / spc.total_products_supplied
    , 1) AS pct_products_dead
FROM dim_supplier s
JOIN supplier_product_count spc ON s.supplier_id = spc.supplier_id
LEFT JOIN supplier_cogs sc ON s.supplier_id = sc.supplier_id
LEFT JOIN supplier_dead_stock sds ON s.supplier_id = sds.supplier_id;
GO

-- =====================================================================
-- VIEW 8 (NEW): Buy-to-Sell Ratio — total units purchased ÷ total
-- units sold, per product. Tests whether long-lead-time suppliers
-- actually caused oversized orders.
-- =====================================================================

CREATE OR ALTER VIEW vw_buy_to_sell AS
WITH purchases AS (
    SELECT product_id, SUM(quantity) AS total_purchase_units
    FROM fact_inventory_transactions
    WHERE transaction_type = 'Purchase' AND data_issue = 0
    GROUP BY product_id
),
sales AS (
    SELECT product_id, SUM(ABS(quantity)) AS total_sale_units
    FROM fact_inventory_transactions
    WHERE transaction_type = 'Sale' AND data_issue = 0
    GROUP BY product_id
)
SELECT
    p.product_id,
    p.product_name,
    p.category,
    s.supplier_name,
    s.country,
    s.lead_time_days,
    COALESCE(pu.total_purchase_units, 0) AS total_purchase_units,
    COALESCE(sa.total_sale_units, 0)     AS total_sale_units,
    CASE WHEN COALESCE(sa.total_sale_units, 0) = 0 THEN NULL
         ELSE ROUND(pu.total_purchase_units * 1.0 / sa.total_sale_units, 3)
    END AS buy_to_sell_ratio
FROM dim_product p
JOIN dim_supplier s ON p.supplier_id = s.supplier_id
LEFT JOIN purchases pu ON p.product_id = pu.product_id
LEFT JOIN sales sa ON p.product_id = sa.product_id;
GO

-- =====================================================================
-- VIEW 9 (NEW): Purchases After Last Sale — every Purchase that
-- happened after that product's own most recent Sale. Rows here
-- represent ordering that continued after demand had already ended.
-- =====================================================================

CREATE OR ALTER VIEW vw_purchases_after_last_sale AS
WITH last_sale AS (
    SELECT product_id, MAX(transaction_date) AS last_sale_date
    FROM fact_inventory_transactions
    WHERE transaction_type = 'Sale' AND data_issue = 0
    GROUP BY product_id
)
SELECT
    f.product_id,
    p.product_name,
    p.category,
    s.supplier_name,
    f.transaction_id,
    f.transaction_date  AS purchase_date,
    ls.last_sale_date,
    DATEDIFF(DAY, ls.last_sale_date, f.transaction_date) AS days_after_last_sale,
    f.warehouse_id,
    f.quantity           AS units_purchased,
    ROUND(f.quantity * p.unit_cost, 2) AS purchase_value
FROM fact_inventory_transactions f
JOIN dim_product p ON f.product_id = p.product_id
JOIN dim_supplier s ON p.supplier_id = s.supplier_id
JOIN last_sale ls ON f.product_id = ls.product_id
WHERE f.transaction_type = 'Purchase'
  AND f.data_issue = 0
  AND f.transaction_date > ls.last_sale_date;
GO

-- =====================================================================
-- VERIFICATION — run after all 9 views are created
-- =====================================================================

-- View 1: ABC category-wise product count
SELECT abc_category, COUNT(*) AS n FROM vw_abc_analysis GROUP BY abc_category;

-- View 1: total revenue across all products
SELECT SUM(total_revenue) AS grand_total FROM vw_abc_analysis;

-- View 2: XYZ category-wise product count
SELECT xyz_category, COUNT(*) AS n FROM vw_xyz_analysis GROUP BY xyz_category;

-- View 3: segment-wise product count and revenue
SELECT combined_segment, COUNT(*) AS n, SUM(total_revenue) AS revenue
FROM vw_abc_xyz_matrix GROUP BY combined_segment ORDER BY combined_segment;

-- View 4: aging bucket summary
SELECT aging_bucket, COUNT(*) AS combos, SUM(current_stock) AS units,
       SUM(tied_up_capital) AS capital
FROM vw_stock_aging GROUP BY aging_bucket;

-- View 4: dead stock detail
SELECT COUNT(DISTINCT product_id) AS dead_products, COUNT(*) AS dead_combos,
       SUM(tied_up_capital) AS dead_capital, AVG(days_since_last_sale*1.0) AS avg_days,
       MIN(days_since_last_sale) AS min_days, MAX(days_since_last_sale) AS max_days
FROM vw_stock_aging WHERE aging_bucket = 'Dead Stock';

-- View 5: total product-warehouse combinations covered (should be 105)
SELECT COUNT(*) AS total_combos FROM vw_reorder_analysis;

-- View 5: how many combos currently need reordering, and which ones
SELECT reorder_status, COUNT(*) AS n FROM vw_reorder_analysis GROUP BY reorder_status;
SELECT product_id, product_name, warehouse_id, reorder_point, current_stock
FROM vw_reorder_analysis WHERE reorder_status = 'Reorder Now';

-- View 5: reorder point details for the 5 dead-stock products, all warehouses
SELECT product_id, warehouse_id, avg_daily_sales, reorder_point, current_stock, reorder_status
FROM vw_reorder_analysis
WHERE product_id IN ('PRD031','PRD032','PRD033','PRD034','PRD035')
ORDER BY product_id, warehouse_id;

-- View 6: simple average turnover (the original, misleading "~1.3x" headline)
SELECT AVG(annualized_turnover_ratio) AS simple_avg_turnover
FROM vw_inventory_turnover;

-- View 6: correct COMPANY-level weighted turnover
SELECT
    SUM(recent_annualized_cogs) AS total_annualized_cogs,
    SUM(current_inventory_value) AS total_inventory_value,
    ROUND(SUM(recent_annualized_cogs) / SUM(current_inventory_value), 3) AS weighted_company_turnover
FROM vw_inventory_turnover;

-- View 6: correct CATEGORY-level weighted turnover
SELECT
    category,
    SUM(recent_annualized_cogs) AS total_annualized_cogs,
    SUM(current_inventory_value) AS total_inventory_value,
    ROUND(SUM(recent_annualized_cogs) / SUM(current_inventory_value), 3) AS weighted_turnover,
    ROUND(365.0 / NULLIF(SUM(recent_annualized_cogs) / SUM(current_inventory_value), 0), 1) AS dio_from_weighted
FROM vw_inventory_turnover
GROUP BY category
ORDER BY weighted_turnover DESC;

-- View 6: top 5 products by turnover
SELECT TOP 5 product_id, product_name, annualized_turnover_ratio, current_inventory_value
FROM vw_inventory_turnover
ORDER BY annualized_turnover_ratio DESC;

-- View 6: the 5 dead-stock products (should show 0 turnover / NULL DIO)
SELECT product_id, product_name, recent_annualized_cogs, current_inventory_value,
       annualized_turnover_ratio, days_inventory_outstanding
FROM vw_inventory_turnover
WHERE product_id IN ('PRD031','PRD032','PRD033','PRD034','PRD035');

-- View 8: buy-to-sell ratio range among active (non-dead) products
SELECT MIN(buy_to_sell_ratio) AS min_ratio, MAX(buy_to_sell_ratio) AS max_ratio
FROM vw_buy_to_sell
WHERE product_id NOT IN ('PRD031','PRD032','PRD033','PRD034','PRD035');

-- View 8: buy-to-sell ratio for the 3 healthy import products —
-- compare against the active range above
SELECT product_id, product_name, country, lead_time_days, buy_to_sell_ratio
FROM vw_buy_to_sell
WHERE product_id IN ('PRD027','PRD029','PRD030');

-- View 9: all purchases made after the product had already stopped selling
SELECT product_id, product_name, purchase_date, days_after_last_sale,
       warehouse_id, units_purchased, purchase_value
FROM vw_purchases_after_last_sale
ORDER BY product_id, purchase_date;

-- View 9: total capital tied up by late purchases, and share of dead stock
SELECT
    SUM(purchase_value) AS capital_from_late_purchases,
    (SELECT SUM(tied_up_capital) FROM vw_stock_aging WHERE aging_bucket = 'Dead Stock') AS total_dead_stock_capital,
    ROUND(
        SUM(purchase_value) * 100.0 /
        (SELECT SUM(tied_up_capital) FROM vw_stock_aging WHERE aging_bucket = 'Dead Stock')
    , 1) AS pct_of_dead_stock
FROM vw_purchases_after_last_sale;
