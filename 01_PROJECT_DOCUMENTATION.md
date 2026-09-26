# Project Documentation

## 1️⃣ Executive Summary

### 📌 Headline Numbers

| Metric | Value |
|---|---|
| Total Inventory Value | ৳6.08M |
| Dead Stock Value | ৳75,980 (1.25%) |
| Dead Stock Products | 5 SKUs across 15 product-warehouse combinations |
| Average Idle Days (Dead Stock) | 525 days |
| Dead Stock Correlated with Import Suppliers | 100% (correlation only — see Finding 4) |
| Reorder Alert Count | 1 of 105 product-warehouse combinations |
| Company-wide Inventory Turnover (weighted) | 1.49x (healthy benchmark: 4–8x) |
| Total Revenue (24 months) | ৳26.67M |

---

RetailMart BD's overall inventory position is broadly healthy — 85.7% of stock (90 of 105 product-warehouse combinations) is actively moving and only 1 combination is anywhere near needing replenishment. But beneath the healthy aggregate sits a clear, traceable problem: **৳75,980 locked in 5 dead products that have not sold in an average of 525 days**, split roughly evenly between stock that was already on hand when sales stopped (49%) and stock ordered *after* sales had already stopped (51%).

The deeper issue is systemic. Even among active products, inventory turnover (1.49x, revenue-weighted) sits well below the 4–8x range typical for healthy FMCG operations — confirming that the dead stock problem is the most visible symptom of a broader, buffer-heavy procurement pattern that applies across the entire portfolio.

The company does not have a stockout problem. It has a **capital efficiency problem**, with one clearly identifiable and directly preventable component: 5 products that continued being reordered for months after demand had already ended. This report identifies exactly where the capital sits, tests (and rules out) the most obvious explanation, and confirms the actual cause.

---

## 2️⃣ Project Background & Objective

RetailMart BD is a mid-sized FMCG retail company operating 3 warehouses (Dhaka Central, Chittagong Port, Sylhet Hub) and managing 35 SKUs sourced from 10 suppliers and distributed nationwide.

Inventory management had been entirely reactive and intuition-driven — with no data-backed system to identify which products were tying up capital, which carried stockout risk, or when and how much to reorder.

### Three Objectives

| # | Objective |
|---|---|
| 1 | **Inventory Segmentation** — classify products by revenue contribution and demand predictability using ABC-XYZ analysis |
| 2 | **Dead & Slow Stock Identification** — determine which products have been inactive, for how long, and how much capital is at risk |
| 3 | **Proactive Reorder Intelligence** — build an early-warning system that flags risk before stockouts occur |

---

## 3️⃣ Methodology

| Phase | Tool | What Was Done |
|---|---|---|
| Data Cleaning | Excel (manual pass) + Python (`clean_transactions.py`) | Fixed date formats, transaction-type inconsistencies, missing values, sign errors; the Python pass caught 2 residual issues the manual pass missed (see Section 7) |
| Data Modeling | SQL Server | Star Schema — 1 fact table, 4 dimension tables, recalculated stock balance via window functions |
| Analysis | SQL Server | 9 analytical views across 9 analytical frameworks |
| Visualization | Power BI | 5-page interactive dashboard with DAX measures and cross-filtering |

### Data Quality Approach

No data was deleted. Every quality issue was root-caused and flagged via a `data_issue` column, then excluded from downstream calculations — preserving a complete audit trail. A total of **139 transactions (1.51%)** were flagged this way: 100 from originally-missing quantities, and 39 more from a negative-balance check described below.

> **Notable issues resolved:** mixed date formats (3 different patterns in one column), quantity sign errors, missing supplier IDs recovered via product-supplier lookup, XYZ calculations rebuilt over a complete 24-month grid after discovering that missing months were being silently excluded (which caused dead-stock products to appear falsely stable), 39 transactions (38 Sale + 1 Purchase, ~0.4% of rows) with impossible negative stock balances traced to an opening-stock timing overlap and flagged rather than deleted, 14 rows with inconsistent product_id casing, and 14 Purchase rows where a missing price had been filled with the selling price instead of unit cost (overstating total Purchase value by ~৳98,000, about 0.4% of total spend).

---

## 4️⃣ Key Findings

### 🔍 Finding 1 — ABC-XYZ Segmentation Isolates a Specific Risk Pool

ABC-XYZ analysis placed 5 of 35 SKUs in the **CZ segment** — the lowest revenue contribution (0.87% of total) combined with the most erratic demand (CV 162–171%, versus 14–31% for most products). Each of these 5 products recorded **17 zero-sale months out of 24**.

> 🔑 **ABC alone couldn't find them.** The C-category also contained 6 other products (Antacid Tablets, Harpic, Vim, Savlon, Mango Juice, Sensodyne) that are low-revenue but stable (CX/CY). Without XYZ layered on top, all 11 C-category products would have looked the same. Only the combined matrix separated "low-revenue but healthy" from "genuinely dead."

---

### 🔍 Finding 2 — ৳75,980 Tied Up, Idle for an Average of 525 Days

Stock Aging Analysis confirmed 15 dead product-warehouse combinations across 5 SKUs, with idle periods ranging from 510 to 644 days. Herbal Bath Salts at Chittagong Port holds the longest record at **644 days without a single sale**.

> 🔑 **The 1.25% figure understates the real cost.** Warehouse space, holding costs, and the opportunity cost of that capital compound over 500+ idle days. This capital was recoverable — it resulted from ordering that continued after demand ended, not from an inherent market failure (see Finding 4).

---

### 🔍 Finding 3 — Dead Stock Correlates with 2 Import Suppliers (Correlation Only)

| Supplier | Country | Lead Time | Reliability Score | Dead Capital | Dead % of Their Portfolio |
|---|---|---|---|---|---|
| Pacific Imports Ltd | 🇸🇬 Singapore | 28 days | 72 | ৳61,630 | 80% (4 of 5 products) |
| Globe Traders (Import) | 🇮🇳 India | 21 days | 78 | ৳14,350 | 33% (1 of 3 products) |
| All 8 local suppliers | 🇧🇩 Bangladesh | 4–12 days | 80–95 | ৳0 | 0% |

100% of dead stock capital traces to these 2 suppliers, both with the longest lead times in the network and the lowest reliability scores.

> 🔑 **This table cannot, by itself, show that the suppliers caused the outcome.** All 5 dead products are also the company's only niche/Lifestyle SKUs, and every one of them happens to be sourced from these 2 suppliers — supplier identity and product category are confounded here. A correlation this clean deserves a direct test before being treated as an explanation, which Finding 4 provides.

---

### 🔍 Finding 4 — The Real Cause: Ordering Continued After Demand Stopped (NEW)

Two direct tests were run against the "long lead times caused oversized orders" explanation:

**Test 1:** The company's 3 *healthy* import products (same 2 suppliers, same 21–28 day lead times, but still selling normally) have purchase-to-sale ratios of 1.31–1.37 — squarely inside the 1.15–1.45 range for every active product in the portfolio. Long lead times did not produce oversized buffers here.

**Test 2:** Every Purchase transaction for the 5 dead products was checked against that product's own last recorded Sale. **10 Purchase orders, totaling 104 units (৳38,780), were placed between 34 and 282 days *after* the product had already stopped selling.** This accounts for **51% of the total dead-stock capital** — the remaining 49% (৳37,200) was stock still on hand when sales stopped.

> 🔑 **The suppliers did not cause this. Procurement continued reordering 5 specific products for months after demand had already ended.** This is a controllable process gap — the absence of an automatic hold when a product's sales stop — not a supplier-risk issue.

---

### 🔍 Finding 5 — Low Turnover Is a Company-wide Issue, Not Just a Dead Stock Problem

Even active products top out at a turnover ratio of ~2.9–3.1x (Maggi Noodles, Cocola Noodles). The revenue-weighted company-wide turnover is **1.49x**, well below the 4–8x healthy FMCG benchmark. Every category falls short:

| Category | Weighted Turnover | Days Inventory Outstanding |
|---|---|---|
| Healthcare | 1.59x | 230 days |
| Food & Beverage | 1.57x | 232 days |
| Personal Care | 1.39x | 263 days |
| Home Care | 1.39x | 264 days |
| Lifestyle | 0.00x | Not meaningful (dead) |

Only 1 of 105 product-warehouse combinations currently triggers a reorder alert (Aromatherapy Diffuser, Sylhet Hub — and even that is a near-zero-demand product whose reorder point happens to sit at 3 units, the same as its current stock, not a genuine restocking signal).

> 🔑 **A reorder alert count of 1 out of 105 confirms the same pattern found in the turnover figures.** The company maintains such large buffers across almost the entire portfolio that stock almost never approaches a genuine reorder trigger — the same buffer-heavy behavior that, combined with the process gap in Finding 4, created the dead stock in the first place.

---

## 5️⃣ Recommendations

### 🔴 Immediate (0–30 days)

**R1 — Liquidate the 5 CZ Products**
Launch a clearance campaign (30–50% discount, or bundling with fast-moving products) to recover at least partial capital from the ৳75,980 currently locked in Premium Candle Set, Ceramic Mug Set, Aromatherapy Diffuser, Herbal Bath Salts, and Imported Olive Oil.
*(Findings 1, 2)*

**R2 — Place a Hold on Future Reordering for These 5 Products**
Add a manual procurement hold in the system until genuine demand is validated. Current stock (3–60 units per warehouse) far exceeds any calculated reorder point (2–3 units).
*(Finding 2)*

---

### 🟡 Short-term (1–3 months)

**R3 — Implement an Automatic Zero-Sales Procurement Hold** *(revised)*
Add a system rule: if a product records zero sales for a defined number of consecutive months (e.g., 2–3), automatically suspend reordering until a manual review confirms genuine demand. This directly targets the mechanism identified in Finding 4 — it would have prevented roughly half of the current dead-stock capital (the 51% from purchases made after sales had already stopped), and applies portfolio-wide rather than singling out specific suppliers.
*(Finding 4)*

**R4 — Introduce a Demand-Validation Step for Niche Categories**
Before committing to a full purchase order on any Lifestyle or specialty SKU, run a small pilot batch (10–20% of the intended order) to validate actual demand. Only proceed with the full order once the pilot confirms take-up.
*(Findings 1, 4)*

---

### 🟢 Long-term (3–6+ months)

**R5 — Build a Demand-Volatility-Based Procurement Policy**
Formally incorporate XYZ classification into procurement decisions — large buffer orders for X-category products (stable demand), small and conservative orders for Z-category products (erratic demand). Document this as a Standard Operating Procedure so it becomes a repeatable system, not an ad hoc decision.
*(Findings 1, 5)*

**R6 — Rebalance Dead-Stock-Prone SKUs Across Warehouses** *(revised)*
Dead stock capital is not evenly spread — Dhaka Central alone holds 49.8% of it (৳37,860 of ৳75,980). For any niche/Lifestyle SKU that survives the R3 hold review, consider concentrating initial stock in a single warehouse rather than distributing evenly across all 3, until demand is confirmed at each location.
*(Finding 2, warehouse breakdown)*

**R7 — Establish a Quarterly Inventory Health Review**
Treat this dashboard as a living tool, not a one-time analysis. A quarterly review cycle — combined with the automated R3 hold rule — would catch emerging CZ products before they accumulate 500+ idle days, and would flag whether the hold rule itself needs tuning.
*(Findings 4, 5)*

---

## 6️⃣ Expected Impact

| Timeframe | Expected Outcome |
|---|---|
| **Immediate** | Liquidation of CZ products could recover an estimated 40–60% of tied-up capital (~৳30,000–45,000) through clearance pricing |
| **Medium-term** | The automatic zero-sales hold rule (R3) should prevent a recurrence of the pattern that caused 51% of current dead stock, without needing to change supplier terms |
| **Long-term** | A demand-volatility-based procurement policy could move company-wide inventory turnover from 1.49x toward a more moderate 2.0x, freeing an estimated ৳1.5M–1.6M in tied-up capital |

> **Caveat:** These are reasoned estimates based on dataset patterns, not the result of a financial audit. A small-scale pilot is recommended before full implementation to validate actual impact.

---

## 7️⃣ Data Quality & Limitations

| Issue | How It Was Handled |
|---|---|
| Mixed date formats (3 patterns in one column) | Parsed explicitly by pattern (ISO / D-M-Y / M-D-Y) rather than relying on automatic date-guessing, which couldn't reliably distinguish D/M/YYYY from M-D-YYYY |
| Quantity sign errors | Corrected by transaction type (Sale = negative, Purchase/Return = positive); stock balance recalculated from scratch |
| NULL quantities silently converted to 0 during load | Flagged via `data_issue = 1`; excluded from all calculations |
| XYZ CV calculated only over active-selling months | Rebuilt over a complete 24-month grid — missing months = 0, not excluded |
| Reorder point calculated over a fixed 730-day window ending past the data's actual end date | Corrected to the data's actual last transaction date (2024-12-18); 1 genuine reorder alert now surfaces where the original company-level, mis-dated calculation showed 0 |
| Stock-aging reference date | Corrected from an assumed 2024-12-31 to the data's actual last transaction date (2024-12-18). The earlier date had artificially created a "Slow Moving" bucket (~৳0.53M across 6 combinations) that does not actually exist — a pure artifact of a 13-day gap, not a real finding |
| Inventory turnover's "recent window" | Corrected from a fixed calendar start date (which produced an effectively shorter, under-annualized window) to a dynamic 182-day window ending at the data's actual last date, annualized by exactly 365/182 |
| Inventory turnover, company/category level | Corrected from a simple average of 35 per-product ratios (which understated the true figure) to a revenue-weighted calculation (total annualized COGS ÷ total inventory value) |
| 39 transactions (38 Sale + 1 Purchase, ~0.4% of rows) with impossible negative stock balances | Traced to an opening-stock timing overlap (this dataset has no opening stock — every product-warehouse combination starts from 0 on 2023-01-01); flagged and excluded, not deleted |
| Inventory Turnover uses period-end inventory as a proxy for average inventory | A simplification — noted here; a full financial audit would use monthly average inventory |
| Import-supplier correlation with dead stock | Tested directly rather than assumed (see Finding 4) — the correlation does not hold up as causation; supplier identity and product category (niche/Lifestyle) were confounded in the original analysis |
| Buy-to-sell ratio and the 51% late-purchase figure | Specific to this dataset — the exact ratios and day-gaps illustrate a pattern (ordering continued after demand ended) rather than a universal benchmark that would hold at a different company |

**Total flagged transactions:** 139 (1.51%) — excluded from analysis, retained in database with full audit trail.

---

## 8️⃣ Appendix — Dashboard Structure

| Page | Focus |
|---|---|
| **1 — Executive Overview** | Company-wide KPIs, aging distribution, revenue by category, dead-stock cause breakdown (late purchases vs. pre-existing stock), buy-to-sell ratio comparison |
| **2 — ABC-XYZ Segmentation** | 9-segment heatmap matrix, segment-wise revenue, product-level drill-down |
| **3 — Dead & Slow Stock Report** | Aging analysis, financial impact by category and warehouse, top dead-stock items by idle days, estimated liquidation recovery |
| **4 — Reorder Alert Panel** | Warehouse-level reorder status by product, supplier lead-time comparison |
| **5 — Trend Analysis** | Monthly sales vs. purchase trend, seasonal patterns, weighted turnover by category |

📸 Dashboard screenshots → [`/03_powerbi/dashboard_snapshots`](03_powerbi/dashboard_snapshots)

📊 Full analysis findings → [`02_ANALYSIS_FINDINGS.md`](./02_ANALYSIS_FINDINGS.md)

📈 Dashboard page insights → [`03_DASHBOARD_INSIGHTS.md`](./03_DASHBOARD_INSIGHTS.md)
