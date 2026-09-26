"""
RetailMart BD — Inventory Optimization & Dead Stock Detection
clean_transactions.py

Purpose
-------
Reproduces the raw-to-clean transformation for the 4 source tables.
Reads the raw Excel workbook (5 sheets, each with a title row above
the header) and writes 4 clean CSV files, applying every fix listed
in the raw workbook's own `data_quality_issues` sheet.

This script exists because an earlier manual Excel-cleaning pass had
left 2 residual errors that a later data-integrity check caught:
  - 14 rows where product_id was lowercase (e.g. "prd018" instead of
    "PRD018") — harmless in SQL Server's case-insensitive collation,
    but breaks in case-sensitive tools.
  - 14 Purchase rows where a missing unit_price had been filled with
    the product's SELLING price instead of its unit_cost (overstating
    total Purchase value by ~৳98,000, about 0.4% of total spend).
This script fixes both, in addition to the 10 issues the original
Excel pass already handled correctly (verified by comparing outputs
row-for-row against the original clean file).

Usage
-----
    pip install pandas openpyxl --break-system-packages
    python clean_transactions.py

Input:  01_datasets/raw/RetailMart_BD_Inventory_Raw_Dataset.xlsx
Output: 01_datasets/cleaned_data/transactions.csv
        01_datasets/cleaned_data/products.csv
        01_datasets/cleaned_data/supplier.csv
        01_datasets/cleaned_data/warehouse.csv
"""

import re
import numpy as np
import pandas as pd

RAW_FILE = "01_datasets/raw/RetailMart_BD_Inventory_Raw_Dataset.xlsx"
OUT_DIR = "01_datasets/cleaned_data/"


def parse_mixed_date(raw_value: str) -> pd.Timestamp:
    """
    The raw transaction_date column mixes 3 formats in one column:
    ISO (YYYY-MM-DD), D/M/YYYY, and M-D-YYYY. DATEVALUE()-style
    guessing can't reliably tell D/M/YYYY apart from M-D-YYYY, so
    each pattern is matched explicitly instead.
    """
    value = raw_value.strip()
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
        return pd.Timestamp(value)
    if re.fullmatch(r"\d{1,2}/\d{1,2}/\d{4}", value):          # D/M/YYYY
        day, month, year = (int(part) for part in value.split("/"))
        return pd.Timestamp(year, month, day)
    match = re.fullmatch(r"(\d{1,2})-(\d{1,2})-(\d{4})", value)  # M-D-YYYY
    month, day, year = (int(part) for part in match.groups())
    return pd.Timestamp(year, month, day)


def main() -> None:
    # ---- Dimension tables: read as-is, just trim whitespace ----
    products = pd.read_excel(RAW_FILE, sheet_name="dim_product", header=1)
    suppliers = pd.read_excel(RAW_FILE, sheet_name="dim_supplier", header=1)
    warehouses = pd.read_excel(RAW_FILE, sheet_name="dim_warehouse", header=1)
    for table in (products, suppliers, warehouses):
        for col in table.select_dtypes(include="object"):
            table[col] = table[col].str.strip()

    # ---- Transactions: apply each fix from data_quality_issues ----
    txns = pd.read_excel(RAW_FILE, sheet_name="transactions", header=1, dtype=str)
    raw_row_count = len(txns)

    # Issue 1: blank rows
    txns = txns.dropna(how="all")

    # Issue 2: duplicate transaction_id (keep first occurrence — the
    # two copies differ only in the unused placeholder stock_balance
    # column, verified during the original cleaning pass)
    txns["transaction_id"] = txns["transaction_id"].str.strip()
    txns = txns.drop_duplicates("transaction_id", keep="first")

    # Issue 3: mixed date formats -> ISO
    txns["transaction_date"] = txns["transaction_date"].apply(parse_mixed_date)

    # Issue 4: inconsistent transaction_type spelling/casing
    type_map = {
        "sale": "Sale", "sales": "Sale", "sell": "Sale",
        "purchase": "Purchase", "po": "Purchase", "buy": "Purchase",
        "return": "Return", "adjustment": "Adjustment",
    }
    txns["transaction_type"] = txns["transaction_type"].str.strip().str.lower().map(type_map)
    assert txns["transaction_type"].notna().all(), "Unmapped transaction_type value found"

    # Issue 9 (product_id casing/spacing): normalize to PRDxxx
    txns["product_id"] = txns["product_id"].str.upper().str.replace(r"[^A-Z0-9]", "", regex=True)
    assert txns["product_id"].isin(products["product_id"]).all(), "product_id not found in master"

    txns["warehouse_id"] = txns["warehouse_id"].str.strip().str.upper()
    assert txns["warehouse_id"].isin(warehouses["warehouse_id"]).all()

    # Issue 5: Purchase rows missing supplier_id — recover from product master
    supplier_lookup = products.set_index("product_id")["supplier_id"]
    txns["supplier_id"] = txns["supplier_id"].str.strip()
    missing_supplier = (txns["transaction_type"] == "Purchase") & txns["supplier_id"].isna()
    txns.loc[missing_supplier, "supplier_id"] = txns.loc[missing_supplier, "product_id"].map(supplier_lookup)

    # Issue 6 + Issue 7: quantity sign correction, and missing
    # quantity -> 0 with a data_issue flag (not deleted)
    quantity = pd.to_numeric(txns["quantity"], errors="coerce")
    txns["data_issue"] = quantity.isna().astype(int)
    quantity = quantity.fillna(0).astype(int)
    quantity = np.where(
        txns["transaction_type"] == "Sale", -np.abs(quantity),
        np.where(txns["transaction_type"].isin(["Purchase", "Return"]), np.abs(quantity), quantity),
    )
    txns["quantity"] = quantity

    # Issue 8: missing/zero unit_price — filled with the SELLING price
    # for Sale rows, and the product's unit_cost for Purchase rows
    # (Return/Adjustment rows never had missing prices in this data)
    price = pd.to_numeric(txns["unit_price"], errors="coerce")
    is_missing_price = price.isna() | (price == 0)
    list_price = products.set_index("product_id")["unit_price"]
    unit_cost = products.set_index("product_id")["unit_cost"]
    fill_value = np.where(
        txns["transaction_type"] == "Sale",
        txns["product_id"].map(list_price),
        txns["product_id"].map(unit_cost),
    )
    assert not (is_missing_price & txns["transaction_type"].isin(["Return", "Adjustment"])).any()
    txns["unit_price"] = price.where(~is_missing_price, fill_value).round(2)

    # Issue 10: the raw stock_balance column is a random placeholder,
    # not real data — dropped entirely; SQL recalculates it from a
    # running total starting at 0 (no opening stock in this dataset)
    txns = txns.sort_values(["transaction_date", "transaction_id"])
    txns["transaction_date"] = txns["transaction_date"].dt.strftime("%Y-%m-%d")
    txns = txns[[
        "transaction_id", "transaction_date", "product_id", "warehouse_id",
        "supplier_id", "transaction_type", "quantity", "unit_price", "data_issue",
    ]]

    # ---- Write outputs ----
    txns.to_csv(OUT_DIR + "transactions.csv", index=False)
    products.to_csv(OUT_DIR + "products.csv", index=False)
    suppliers.to_csv(OUT_DIR + "supplier.csv", index=False)
    warehouses.to_csv(OUT_DIR + "warehouse.csv", index=False)

    print(f"Raw rows: {raw_row_count}  ->  Clean rows: {len(txns)}")
    print(f"Rows flagged (originally missing quantity): {int(txns['data_issue'].sum())}")


if __name__ == "__main__":
    main()
