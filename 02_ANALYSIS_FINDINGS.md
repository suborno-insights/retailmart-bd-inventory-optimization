# 📊 Analysis Findings

This document summarizes the business insights derived from 9 analytical frameworks applied to RetailMart BD's 24-month inventory transaction data (January 2023 – December 2024, with the last recorded transaction on 2024-12-18). Each section explains what the data showed, why it matters, and what it couldn't answer on its own — leading naturally into the next analysis.

> **Note on this revision:** Three things changed from the original analysis, each verified directly against the SQL views in `04_analysis_views.sql`: (1) the stock-aging reference date was corrected to the data's actual last transaction date, which cleared an artificial "Slow Moving" bucket; (2) inventory turnover is now a revenue-weighted company/category figure instead of a simple average across 35 products, which changes the headline from ~1.3x to ~1.49x; (3) the original claim that "long-lead-time import suppliers caused the dead stock" did not hold up under direct testing and has been replaced with a verified cause — see Frameworks 8 and 9.

---

## 1️⃣ ABC Analysis

### 🔍 Key Findings

- Revenue is heavily concentrated. **15 Category A products drive 69.0% of total revenue** (৳18.41M of ৳26.67M) — a textbook Pareto distribution across a 35-SKU portfolio.
- **Fresh Soybean Oil 2L** is the single largest revenue contributor at **7.81%** of total revenue, making it the most critical product for stock availability.
- **Category C contains 11 products** with low revenue contribution — but not all of them are problematic. Several (Antacid Tablets, Harpic, Vim, Savlon) belong to active, everyday categories like Healthcare and Home Care, where low revenue simply reflects low unit price, not low demand.

### 💡 Business Implication

Category A products deserve the tightest inventory control — a stockout on any of these directly impacts revenue. Category C products should not be treated uniformly; some may still move consistently despite modest revenue numbers.

### ⚠️ Limitation

ABC Analysis measures **revenue contribution only** — it says nothing about demand consistency or how long stock has been sitting. Two products can have identical revenue and completely different inventory health. This is why XYZ Analysis follows.

---

## 2️⃣ XYZ Analysis

### 🔍 Key Findings

| Category | Products | Demand Pattern |
|---|---|---|
| X — Stable | 16 | Low variability, easy to forecast |
| Y — Variable | 14 | Moderate variability, manageable |
| Z — Erratic | 5 | High variability, difficult to forecast |

- **86% of products (30 of 35) fall in X or Y** — most of the portfolio has reasonably predictable demand, which is a healthy signal for a supply chain operation.
- The **5 Z-category products** each recorded **17 zero-sale months out of 24**, with a Coefficient of Variation between 162% and 171% — far beyond the 50% threshold for Z classification.

> 🔑 **The products in Z are not just low-revenue — they are effectively inactive.**

### 💡 Business Implication

An important distinction surfaces here: products like Antacid Tablets and Savlon appeared in ABC's C-category (low revenue) but are X-category in XYZ (stable demand). They belong to a completely different risk tier than the Z-category products, even though ABC grouped them together.

### ⚠️ Limitation

XYZ Analysis measures demand variability but ignores revenue contribution. A product can be X-category (stable) while still generating negligible revenue. For inventory decisions, neither analysis is sufficient alone — which is why they are combined next.

---

## 3️⃣ ABC-XYZ Matrix Analysis

### 🔍 Key Findings

| Segment | Products | Revenue |
|---|---|---|
| AX | 7 | ৳9.48M |
| AY | 8 | ৳8.93M |
| BX | 5 | ৳2.81M |
| BY | 4 | ৳2.52M |
| CX | 4 | ৳1.85M |
| CY | 2 | ৳0.85M |
| CZ | 5 | ৳0.23M |

- **No AZ products exist** — none of the company's highest revenue-generating products suffer from erratic demand. The top of the portfolio is both valuable and forecastable.
- **AX + AY together generate ৳18.41M** — these 15 products are the business's core, and their inventory health directly determines company performance.
- **CX products** (Antacid Tablets, Harpic, Vim, Savlon) confirm an important principle: low revenue does not mean poor performance. These products maintain consistent demand and serve an operational role despite modest revenue figures.
- **CZ products** contribute only ৳0.23M (0.87% of total revenue) while showing an average CV above 160% and 17 zero-sale months — the clearest dead stock signal in the entire portfolio.

### ⚠️ Limitation

The ABC-XYZ Matrix identifies *what* the inventory looks like today in terms of revenue and demand — but it cannot tell you *how long* inventory has been sitting unsold. A CZ product could have been inactive for 30 days or 600 days. To answer that question, Stock Aging Analysis is required.

---

## 4️⃣ Stock Aging Analysis

### 🔍 Key Findings

| Aging Bucket | Product-Warehouse Combinations | Units | Tied-Up Capital |
|---|---|---|---|
| 🟢 Active | 90 | 112,599 | ৳60.08L |
| 🔴 Dead Stock | 15 | 212 | ৳75,980 |

- **90 of 105 product-warehouse combinations are Active** — the large majority of inventory is moving regularly.
- **15 Dead Stock combinations** involve only 5 unique products, with idle periods ranging from **510 to 644 days**. Herbal Bath Salts (Chittagong Port) holds the longest idle record at **644 days**.
- **"Slow Moving" and "At Risk" are both genuinely empty** once the reference date is corrected to the data's actual last transaction date (2024-12-18). An earlier pass using 2024-12-31 — 13 days past the real end of the data — had artificially aged 6 combinations into a "Slow Moving" bucket that does not actually exist; that gap has been removed.

### ⚠️ Limitation

Stock Aging Analysis reveals how old inventory is, but not whether current stock levels are proportionate to expected demand. A product can be Active while still carrying excess stock. To measure inventory utilization efficiency, Reorder Point and Inventory Turnover analyses follow.

---

## 5️⃣ Dead Stock Financial Impact Analysis

### 🔍 Key Findings

**By Category:**
| Category | Dead Stock Capital | Share |
|---|---|---|
| 🏮 Lifestyle | ৳41,950 | 55.2% |
| 🫒 Food & Beverage | ৳19,680 | 25.9% |
| 🧴 Personal Care | ৳14,350 | 18.9% |

**By Warehouse:**
| Warehouse | Dead Stock Capital | Share |
|---|---|---|
| Dhaka Central | ৳37,860 | 49.8% |
| Sylhet Hub | ৳22,460 | 29.6% |
| Chittagong Port | ৳15,660 | 20.6% |

- Nearly half of the dead-stock capital (49.8%) is concentrated in a single warehouse (Dhaka Central), which is worth factoring into any liquidation or consolidation decision.
- All 5 dead products are supplied by 2 of the company's 10 suppliers, both import suppliers — but as Framework 8 shows, this overlaps with those products being the company's only niche/Lifestyle SKUs, and does not by itself establish that the supplier relationship caused the outcome.

### ⚠️ Limitation

This analysis identifies where dead stock exists — but not why it happened. That requires testing specific causal hypotheses, which Frameworks 8 and 9 address directly.

---

## 6️⃣ Reorder Point Analysis

### 🔍 Key Findings

- Reorder points are now calculated **per product-warehouse combination** (105 combinations), not per product company-wide. The original company-level approach could mask a specific warehouse running critically low behind healthy stock elsewhere.
- **1 genuine reorder alert exists**: Aromatherapy Diffuser at Sylhet Hub (current stock 3 units, reorder point 3 units). This is not a demand-recovery signal — the product's average daily sales are near-zero, so its reorder point is trivially low; the alert is a coincidence of a dead product's stock happening to sit at its own near-zero threshold.
- Products with the **highest reorder points** are those with the highest daily demand and/or the longest supplier lead times — e.g., Maggi Noodles and Paracetamol 500mg require the largest buffers.
- The 5 dead-stock products show reorder points of just 2–3 units per warehouse — far below their current stock (3–60 units per warehouse), confirming that replenishment is unnecessary and existing stock will remain idle without demand recovery.

> 🔑 **1 alert out of 105 combinations is still a signal, not an anomaly.** The company maintains high buffers across nearly the entire portfolio — this connects directly to the low inventory turnover found next.

### ⚠️ Limitation

Reorder Point Analysis identifies *when* to reorder — but not *how efficiently* inventory is being used between restocking events. Inventory Turnover Analysis addresses this directly.

---

## 7️⃣ Inventory Turnover Analysis

### 🔍 Key Findings

> **Methodology note:** Turnover uses a 182-day recent window ending at the data's actual last transaction date (2024-12-18), annualized by exactly 365/182. Company- and category-level figures are **revenue-weighted** (total annualized COGS ÷ total inventory value) rather than a simple average of 35 per-product ratios — averaging unweighted ratios treats a small SKU and a large SKU as equally important, which understates the true company-wide figure.

| Level | Turnover | Note |
|---|---|---|
| Simple average (35 products, unweighted) | 1.38x | Misleading — kept only for comparison |
| **Weighted company turnover** | **1.49x** | Correct company-wide figure |

**By Category (weighted):**
| Category | Turnover | Days Inventory Outstanding |
|---|---|---|
| Healthcare | 1.59x | 230 days |
| Food & Beverage | 1.57x | 232 days |
| Personal Care | 1.39x | 263 days |
| Home Care | 1.39x | 264 days |
| Lifestyle | 0.00x | Not meaningful (no sales in the recent window) |

- Even the best-performing active products top out at **~3x turnover** (Maggi Noodles, Cocola Noodles) — well below the 4–8x range typical for healthy FMCG operations. This is a company-wide pattern, not an isolated issue.
- **High revenue ≠ fast inventory movement.** Fresh Soybean Oil generates the most revenue in the portfolio but doesn't rank among the highest-turnover products — capital efficiency and revenue contribution are not the same metric.

> 🔑 **The low turnover across active products — not just dead stock — confirms that the company's procurement approach is systematically buffer-heavy.** Stock levels are consistently higher than what demand patterns require. Moving company-wide turnover from 1.49x toward a more moderate 2.0x target would free an estimated **৳1.5M–1.6M** in tied-up capital (illustrative — annualized COGS held constant, current inventory levels used; not a financial audit).

### ⚠️ Limitation

Inventory Turnover measures how efficiently inventory converts to sales — but it doesn't explain *why* specific products went dead. Frameworks 8 and 9 test that directly.

---

## 8️⃣ Supplier Performance Analysis

### 🔍 Key Findings

**Dead Stock by Supplier:**
| Supplier | Country | Products Supplied | Dead Products | Dead % | Dead Capital |
|---|---|---|---|---|---|
| Pacific Imports Ltd | 🇸🇬 Singapore | 5 | 4 | 80% | ৳61,630 |
| Globe Traders (Import) | 🇮🇳 India | 3 | 1 | 33.3% | ৳14,350 |
| All 8 local suppliers | 🇧🇩 Bangladesh | 27 | 0 | 0% | ৳0 |

- 100% of dead stock capital traces to 2 of 10 suppliers, both import suppliers with the longest lead times in the network (21–28 days vs. 4–12 days locally). Both also carry the lowest reliability scores (72 and 78).
- **This pattern does not, on its own, establish that the suppliers caused the outcome.** All 5 dead products are also the company's only niche/Lifestyle SKUs, and every one of them happens to be sourced from these 2 suppliers — supplier identity and product category are confounded, so this table cannot separate "bad supplier" from "unpopular product."

### ⚠️ Limitation

This is an inventory-focused supplier assessment (lead time, reliability score, dead stock exposure only) — it does not test causation. Framework 9 tests the actual mechanism directly.

---

## 9️⃣ Buy-to-Sell Ratio & Purchase Timing Analysis *(NEW — replaces the unverified supplier-causation claim)*

### 🔍 Key Findings

**Test 1 — Did long lead times force oversized orders?**

If long lead times genuinely forced larger buffer orders, the company's 3 *healthy* import products (same suppliers, same lead times, but still selling) should show unusually high purchase-to-sale ratios too.

| Product | Supplier | Lead Time | Buy-to-Sell Ratio |
|---|---|---|---|
| Pringles Original 110g | Pacific Imports Ltd | 28 days | 1.31 |
| Taaza Tea 200g | Globe Traders | 21 days | 1.37 |
| Brooke Bond Red Label 250g | Globe Traders | 21 days | 1.33 |
| *All active products (range)* | — | — | 1.15 – 1.45 |

> 🔑 **They don't.** All three healthy import products sit comfortably inside the normal range for every active product in the portfolio. Long lead times did not produce oversized orders here — the "supplier caused it" explanation does not survive this test.

**Test 2 — What actually happened?**

For the 5 dead products, every Purchase transaction was checked against that product's own last recorded Sale.

- **10 Purchase orders, totaling 104 units (৳38,780), were placed *after* the product had already stopped selling** — ranging from 34 to 282 days after the last sale.
- This accounts for **51% of the total dead-stock capital (৳38,780 of ৳75,980)**. The remaining 49% (৳37,200) was stock still on hand at the time sales stopped.
- Dead products also show a modestly higher average buy-to-sell ratio (1.66) than active products (1.33), consistent with ordering having continued past the point it was needed.

> 🔑 **The real, demonstrable cause is that procurement continued ordering for these 5 products for months after demand had already ended — not that the supplying countries or lead times were unusual.** This is a controllable process gap (no automatic hold on reordering when sales stop), not a supplier risk.

### 💡 Business Implication

A rule such as "N consecutive months with zero sales triggers an automatic procurement hold" would have prevented roughly half of the current dead-stock capital. This replaces the original recommendation to renegotiate with import suppliers, which this analysis does not support.

### ⚠️ Limitation

This analysis is based on 24 months of transaction history for a synthetic dataset; the specific 34–282 day gaps and the 51% figure are exact for this dataset but illustrate a pattern (continued ordering after demand ends) rather than a universal ratio that would hold at a different company.

---

## 🔗 How the Analyses Connect

```
ABC Analysis          → Which products matter most by revenue?
      ↓
XYZ Analysis          → Which products have predictable demand?
      ↓
ABC-XYZ Matrix        → Which products are truly problematic vs. just low-revenue?
      ↓
Stock Aging           → How long has that problematic inventory been sitting?
      ↓
Dead Stock Impact     → Where is the capital locked — by category and warehouse?
      ↓
Reorder Point         → Does any location need replenishment right now?
      ↓
Inventory Turnover    → How efficiently is inventory being converted to sales, company-wide?
      ↓
Supplier Performance  → Where dead stock capital sits by supplier (a WHERE, not a WHY)
      ↓
Buy-to-Sell & Timing  → What actually caused it — tested directly, not assumed
```

No single analysis tells the full story. The value comes from layering them — and, in this case, from testing a plausible-looking explanation (Framework 8) against direct evidence (Framework 9) rather than accepting it on correlation alone.
