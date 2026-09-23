/* =====================================================================
   RetailMart BD — Inventory Optimization & Dead Stock Detection
   02_data_load.sql  (CORRECTED)

   Purpose: Load cleaned data from staging tables (imported via Excel/
            Python) into the final Star Schema tables with correct
            data types.

   Prerequisite: The 4 cleaned CSVs imported into staging tables via
   SSMS Import Wizard:
     transactions.csv -> raw_transactions
     products.csv      -> dim_product_stage
     supplier.csv       -> dim_supplier_stage
     warehouse.csv       -> dim_warehouse_stage

   CHANGE LOG vs. original version
   --------------------------------
   1. CRITICAL FIX — data_issue was being re-derived in SQL as
      "CASE WHEN quantity IS NULL THEN 1 ELSE 0 END". In the cleaned
      CSV, the 100 originally-missing-quantity rows are NOT NULL —
      they were already filled with 0 during Excel/Python cleaning,
      and the correct flag lives in the CSV's own data_issue column.
      The old CASE expression therefore never fired, and every row
      was silently loaded with data_issue = 0 regardless of what the
      CSV said. Fixed by reading data_issue straight from staging.
   2. The final WHERE clause used to silently drop any row that
      failed TRY_CAST on date/quantity, with no record of how many
      or which ones. Added an explicit pre-load count check (Step 0)
      so a silent drop would be caught immediately instead of just
      quietly reducing the row count.
   3. No change needed to sign handling or price filling here — the
      cleaned CSV already carries signed quantities and filled
      prices; 03_data_quality_fixes.sql now treats sign correction
      as a defensive no-op re-assertion rather than a real fix (see
      that file's change log).
   ===================================================================== */

USE RetailMart_BD;
GO

-- =====================================================================
-- 1. Populate dim_date (Jan 2023 - Dec 2024)
--    Unchanged — covers the full calendar even though the data itself
--    ends 2024-12-18; unused trailing dates in dim_date are harmless.
-- =====================================================================

WITH date_range AS (
    SELECT CAST('2023-01-01' AS DATE) AS dt
    UNION ALL
    SELECT DATEADD(DAY, 1, dt)
    FROM date_range
    WHERE dt < '2024-12-31'
)
INSERT INTO dim_date
SELECT
    CAST(FORMAT(dt, 'yyyyMMdd') AS INT)    AS date_key,
    dt                                      AS full_date,
    DAY(dt)                                 AS day_of_month,
    DATENAME(WEEKDAY, dt)                   AS day_name,
    DATEPART(WEEK, dt)                      AS week_number,
    MONTH(dt)                               AS month_number,
    DATENAME(MONTH, dt)                     AS month_name,
    DATEPART(QUARTER, dt)                   AS quarter,
    YEAR(dt)                                AS year,
    CASE WHEN DATEPART(WEEKDAY, dt) IN (1,7) THEN 1 ELSE 0 END AS is_weekend
FROM date_range
OPTION (MAXRECURSION 1000);
GO

-- =====================================================================
-- 2. Populate dim_product / dim_supplier / dim_warehouse
--    Unchanged — these 3 files are byte-for-byte identical to the
--    original clean files, already verified against the raw sheets.
-- =====================================================================

INSERT INTO dim_product
SELECT
    TRIM(product_id),
    TRIM(product_name),
    TRIM(category),
    TRIM(sub_category),
    TRY_CAST(unit_cost AS DECIMAL(10,2)),
    TRY_CAST(unit_price AS DECIMAL(10,2)),
    TRY_CAST(reorder_level AS INT),
    TRY_CAST(min_stock_threshold AS INT),
    TRIM(supplier_id)
FROM dim_product_stage
WHERE product_id IS NOT NULL;
GO

INSERT INTO dim_supplier
SELECT
    TRIM(supplier_id),
    TRIM(supplier_name),
    TRIM(country),
    TRY_CAST(lead_time_days AS TINYINT),
    TRY_CAST(reliability_score AS TINYINT)
FROM dim_supplier_stage
WHERE supplier_id IS NOT NULL;
GO

INSERT INTO dim_warehouse
SELECT
    TRIM(warehouse_id),
    TRIM(warehouse_name),
    TRIM(city),
    TRIM(region),
    TRY_CAST(storage_capacity_sqft AS INT)
FROM dim_warehouse_stage
WHERE warehouse_id IS NOT NULL;
GO

-- =====================================================================
-- 0. Pre-load check — staging row count must equal 9,211.
--    Run this BEFORE the insert below. If it doesn't say 9211/9211/0,
--    STOP and investigate before loading — something in the CSV or
--    the SSMS import doesn't match what this script expects.
-- =====================================================================

SELECT
    COUNT(*)                                                        AS staging_rows,
    SUM(CASE WHEN TRY_CAST(transaction_date AS DATE) IS NULL THEN 1 ELSE 0 END) AS unparseable_dates,
    SUM(CASE WHEN TRY_CAST(quantity AS INT) IS NULL THEN 1 ELSE 0 END)          AS unparseable_quantity,
    SUM(CASE WHEN transaction_id IS NULL THEN 1 ELSE 0 END)                     AS null_ids
FROM raw_transactions;
-- Expected: staging_rows = 9211, the other three = 0.

-- =====================================================================
-- 3. Populate fact_inventory_transactions
--    (Source: raw_transactions, cleaned prior to import — quantity is
--     already signed by transaction type, unit_price already filled,
--     data_issue already correctly flagged in the CSV.)
-- =====================================================================

INSERT INTO fact_inventory_transactions
    (transaction_id, transaction_date, date_key, product_id, warehouse_id,
     supplier_id, transaction_type, quantity, unit_price, total_amount, data_issue)
SELECT
    TRIM(transaction_id),
    TRY_CAST(transaction_date AS DATE),
    CAST(FORMAT(TRY_CAST(transaction_date AS DATE), 'yyyyMMdd') AS INT),
    TRIM(product_id),
    TRIM(warehouse_id),
    NULLIF(TRIM(supplier_id), ''),
    TRIM(transaction_type),
    TRY_CAST(quantity AS INT),
    TRY_CAST(unit_price AS DECIMAL(10,2)),
    ABS(TRY_CAST(quantity AS INT)) * TRY_CAST(unit_price AS DECIMAL(10,2)),
    TRY_CAST(data_issue AS BIT)              -- FIX: trust the CSV's own flag
FROM raw_transactions
WHERE transaction_id IS NOT NULL
  AND TRY_CAST(transaction_date AS DATE) IS NOT NULL
  AND TRY_CAST(quantity AS INT) IS NOT NULL;
GO

-- =====================================================================
-- 4. Post-load check — fact table row count must also equal 9,211,
--    and must equal the staging_rows number from Step 0. If it's
--    lower, the WHERE clause above silently dropped rows — go back
--    to Step 0's breakdown to see which condition caught them.
-- =====================================================================

SELECT COUNT(*) AS fact_rows FROM fact_inventory_transactions;
-- Expected: 9211 (must match staging_rows from Step 0).

SELECT data_issue, COUNT(*) AS row_count
FROM fact_inventory_transactions
GROUP BY data_issue;
-- Expected: data_issue = 0 -> 9111 rows, data_issue = 1 -> 100 rows.
-- (100 rows = the originally-missing-quantity rows flagged during
--  cleaning. If this shows data_issue = 1 -> 0, the old bug is back.)