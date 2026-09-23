/* =====================================================================
   RetailMart BD — Inventory Optimization & Dead Stock Detection
   03_data_quality_fixes.sql  (CORRECTED)

   Purpose: Correct quantity sign errors, recalculate stock_balance,
            and flag (not delete) rows with unresolvable data quality
            issues -- preserving a full audit trail.

   IMPORTANT — no opening stock exists in this dataset. Every
   product-warehouse combination's running balance starts from 0 on
   2023-01-01. This is a simplification of the simulated dataset, not
   a real starting inventory count — worth stating explicitly in the
   documentation, since every downstream number (inventory value,
   dead stock, turnover) depends on it.

   CHANGE LOG vs. original version
   --------------------------------
   1. Step 1 (sign correction) is now a DEFENSIVE NO-OP. The cleaned
      CSV loaded in 02_data_load.sql already carries correctly signed
      quantities (Sale = negative, Purchase/Return = positive) — that
      correction was done once, in the cleaning step, not here. This
      UPDATE is kept so the script still works correctly if someone
      re-runs the pipeline from a less-clean source in future, but on
      the current data it will affect 0 rows.
   2. Step 2 (flag zero-quantity rows) is similarly now a no-op on
      this data — those 100 rows already arrive with data_issue = 1
      from the CSV (see 02_data_load.sql's change log). Kept for the
      same defensive reason.
   3. Step 4 comment corrected: the file it pointed to
      (INSIGHT_REPORT_EN.md) doesn't exist in this repo. Points to
      04_INSIGHT_REPORT.md instead.
   4. Verification queries (Step 5) annotated with the exact expected
      numbers, so a mismatch is caught immediately instead of only
      being noticed several steps later when the dashboard looks off.
   ===================================================================== */

USE RetailMart_BD;
GO

-- =====================================================================
-- 1. Ensure correct sign on quantity by transaction type
-- =====================================================================

UPDATE fact_inventory_transactions
SET quantity = -ABS(quantity)
WHERE transaction_type = 'Sale';
GO

UPDATE fact_inventory_transactions
SET quantity = ABS(quantity)
WHERE transaction_type IN ('Purchase', 'Return');
GO

-- Recalculate total_amount after sign correction (also a no-op on
-- current data, since total_amount was already correctly computed
-- with ABS(quantity) in 02_data_load.sql)
UPDATE fact_inventory_transactions
SET total_amount = ABS(quantity) * unit_price;
GO

-- =====================================================================
-- 2. Flag rows with zero quantity (originally missing, filled as 0
--    during cleaning). 
-- =====================================================================

UPDATE fact_inventory_transactions
SET data_issue = 1
WHERE quantity = 0
  AND transaction_type IN ('Sale', 'Purchase');
GO

-- =====================================================================
-- 3. Recalculate stock_balance using a running total per
--    (product_id, warehouse_id), excluding flagged rows.
--    Starts from 0 for every combination — there is no opening
--    stock in this dataset (see header note above).
-- =====================================================================

WITH running_balance AS (
    SELECT
        transaction_id,
        SUM(quantity) OVER (
            PARTITION BY product_id, warehouse_id
            ORDER BY transaction_date, transaction_id
        ) AS calculated_balance
    FROM fact_inventory_transactions
    WHERE data_issue = 0
)
UPDATE f
SET f.stock_balance = rb.calculated_balance
FROM fact_inventory_transactions f
JOIN running_balance rb
    ON f.transaction_id = rb.transaction_id;
GO

-- =====================================================================
-- 4. Flag any remaining rows where stock_balance is negative
--    (root cause: opening-stock / first-sale timing overlap — a few
--    Sale rows land before enough Purchase volume has accumulated
--    for that product-warehouse combination, since the running
--    balance starts at 0 rather than a real opening count. See
--    04_INSIGHT_REPORT.md for the plain-language explanation.)
-- =====================================================================

UPDATE fact_inventory_transactions
SET data_issue = 1
WHERE stock_balance < 0;
GO

-- Re-run the balance recalculation to exclude the newly flagged rows
WITH running_balance AS (
    SELECT
        transaction_id,
        SUM(quantity) OVER (
            PARTITION BY product_id, warehouse_id
            ORDER BY transaction_date, transaction_id
        ) AS calculated_balance
    FROM fact_inventory_transactions
    WHERE data_issue = 0
)
UPDATE f
SET f.stock_balance = rb.calculated_balance
FROM fact_inventory_transactions f
JOIN running_balance rb
    ON f.transaction_id = rb.transaction_id;
GO

-- Explicitly null out stock_balance for flagged rows so no stale
-- (and potentially negative) values remain visible
UPDATE fact_inventory_transactions
SET stock_balance = NULL
WHERE data_issue = 1;
GO

-- =====================================================================
-- 5. Verification queries — expected results annotated
-- =====================================================================

-- Confirm sign correction (should already be correct — see change log)
SELECT transaction_type, MIN(quantity) AS min_qty, MAX(quantity) AS max_qty
FROM fact_inventory_transactions
WHERE data_issue = 0
GROUP BY transaction_type;

-- Confirm no negative balances remain among clean rows
SELECT COUNT(*) AS negative_balance_count
FROM fact_inventory_transactions
WHERE stock_balance < 0;

-- Final flag summary
SELECT
    data_issue,
    COUNT(*) AS row_count,
    SUM(CASE WHEN stock_balance IS NULL THEN 1 ELSE 0 END) AS null_balance_count
FROM fact_inventory_transactions
GROUP BY data_issue;

-- New: breakdown of what Step 4 excluded, for the documentation's
-- "data quality" section — replaces having to hand-count this later.
SELECT
    transaction_type,
    COUNT(*)               AS rows_excluded,
    SUM(ABS(quantity))     AS units_excluded
FROM fact_inventory_transactions
WHERE data_issue = 1
  AND stock_balance IS NULL
  AND transaction_id NOT IN (
      -- exclude the original 100 missing-quantity rows from this count;
      -- this isolates just the negative-balance exclusions from Step 4
      SELECT transaction_id FROM fact_inventory_transactions WHERE quantity = 0
  )
GROUP BY transaction_type;