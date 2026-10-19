-- ============================================================
-- Cube 1: Bảng Chi Tiết Sản Phẩm (cube_product_statement2)
-- ============================================================
DROP TABLE IF EXISTS cube_product_statement2;

CREATE TABLE cube_product_statement2 (
    product_id UInt32,
    product_name String,
    category LowCardinality(String),
    current_cogs Decimal(18, 2),
    current_price Decimal(18, 2)
) ENGINE = ReplacingMergeTree()
ORDER BY (product_id);

INSERT INTO cube_product_statement2
SELECT 
    product_id,
    product_name,
    category,
    current_cogs,
    current_price
FROM dim_product
GROUP BY 
    product_id,
    product_name,
    category,
    current_cogs,
    current_price;