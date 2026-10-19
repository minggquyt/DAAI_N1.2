-- ============================================================
-- Cube 4: Tồn Kho & Kiểm Chứng Nhu Cầu (cube_inventory_demand_statement2)
-- ============================================================
DROP TABLE IF EXISTS cube_inventory_demand_statement2;

CREATE TABLE cube_inventory_demand_statement2 (
    product_id UInt32,
    year UInt16,
    month UInt8,
    total_stockout_days Int32,
    avg_sell_through_rate Decimal(18, 2)
) ENGINE = SummingMergeTree()
ORDER BY (product_id, year, month);

INSERT INTO cube_inventory_demand_statement2
SELECT 
    p.product_id,
    d.year,
    d.month,
    sum(inv.stockout_days),
    avg(inv.sell_through_rate)
FROM fact_inventory_snapshot AS inv
INNER JOIN cube_product_statement2 AS p ON inv.product_key = p.product_id
INNER JOIN dim_date AS d ON inv.snapshot_date_key = d.date_key
GROUP BY p.product_id, d.year, d.month;