/* =====================================================================
   RetailMart BD — Inventory Optimization & Dead Stock Detection
   01_schema_creation.sql

   Purpose: Create the database and Star Schema tables
            (1 Fact table + 4 Dimension tables)
   ===================================================================== */

CREATE DATABASE RetailMart_BD;
GO

USE RetailMart_BD;
GO

-- =====================================================================
-- DIMENSION TABLES
-- =====================================================================

CREATE TABLE dim_date (
    date_key        INT          PRIMARY KEY,  -- format: 20230115
    full_date       DATE         NOT NULL,
    day_of_month    TINYINT      NOT NULL,
    day_name        VARCHAR(10)  NOT NULL,
    week_number     TINYINT      NOT NULL,
    month_number    TINYINT      NOT NULL,
    month_name      VARCHAR(10)  NOT NULL,
    quarter         TINYINT      NOT NULL,
    year            SMALLINT     NOT NULL,
    is_weekend      BIT          NOT NULL
);
GO

CREATE TABLE dim_product (
    product_id          VARCHAR(10)     PRIMARY KEY,
    product_name        VARCHAR(100)    NOT NULL,
    category            VARCHAR(50)     NOT NULL,
    sub_category        VARCHAR(50)     NOT NULL,
    unit_cost           DECIMAL(10,2)   NOT NULL,
    unit_price          DECIMAL(10,2)   NOT NULL,
    reorder_level       INT             NOT NULL,
    min_stock_threshold INT             NOT NULL,
    supplier_id         VARCHAR(10)     NOT NULL
);
GO

CREATE TABLE dim_supplier (
    supplier_id       VARCHAR(10)   PRIMARY KEY,
    supplier_name     VARCHAR(100)  NOT NULL,
    country           VARCHAR(50)   NOT NULL,
    lead_time_days    TINYINT       NOT NULL,
    reliability_score TINYINT       NOT NULL
);
GO

CREATE TABLE dim_warehouse (
    warehouse_id            VARCHAR(10)  PRIMARY KEY,
    warehouse_name          VARCHAR(100) NOT NULL,
    city                    VARCHAR(50)  NOT NULL,
    region                  VARCHAR(50)  NOT NULL,
    storage_capacity_sqft   INT          NOT NULL
);
GO

-- =====================================================================
-- FACT TABLE
-- =====================================================================

CREATE TABLE fact_inventory_transactions (
    transaction_id      VARCHAR(15)     PRIMARY KEY,
    transaction_date    DATE            NOT NULL,
    date_key            INT             NOT NULL,
    product_id          VARCHAR(10)     NOT NULL,
    warehouse_id        VARCHAR(10)     NOT NULL,
    supplier_id         VARCHAR(10)     NULL,        -- NULL is valid for Sale/Adjustment
    transaction_type    VARCHAR(20)     NOT NULL,    -- Sale, Purchase, Return, Adjustment
    quantity             INT             NOT NULL,
    unit_price           DECIMAL(10,2)   NOT NULL,
    total_amount         DECIMAL(12,2)   NOT NULL,
    stock_balance        INT             NULL,        -- recalculated via window function
    data_issue            BIT             DEFAULT 0    -- flag for known data quality issues
);
GO

-- =====================================================================
-- FOREIGN KEYS — completes the Star Schema
-- =====================================================================

ALTER TABLE fact_inventory_transactions
    ADD CONSTRAINT fk_date
        FOREIGN KEY (date_key) REFERENCES dim_date(date_key);
GO

ALTER TABLE fact_inventory_transactions
    ADD CONSTRAINT fk_product
        FOREIGN KEY (product_id) REFERENCES dim_product(product_id);
GO

ALTER TABLE fact_inventory_transactions
    ADD CONSTRAINT fk_warehouse
        FOREIGN KEY (warehouse_id) REFERENCES dim_warehouse(warehouse_id);
GO

ALTER TABLE fact_inventory_transactions
    ADD CONSTRAINT fk_supplier
        FOREIGN KEY (supplier_id) REFERENCES dim_supplier(supplier_id);
GO
