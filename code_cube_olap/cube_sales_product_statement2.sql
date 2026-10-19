-- ============================================================
-- Cube 2: Cube Doanh Thu & Lợi Nhuận Gộp (cube_sales_product_statement2)
-- ============================================================
DROP TABLE IF EXISTS cube_sales_product_statement2;

CREATE TABLE cube_sales_product_statement2 (
    product_id String,
    year UInt16,
    month UInt8,
    gross_quantity Int32,
    return_quantity Int32,
    net_quantity Int32,
    gross_revenue Decimal(18, 2),
    discount_amount Decimal(18, 2),
    refund_amount Decimal(18, 2),
    net_revenue Decimal(18, 2),
    total_cogs Decimal(18, 2),
    gross_profit Decimal(18, 2),
    gross_margin_pct Decimal(10, 4),
    return_rate Decimal(10, 4),
    avg_net_price_per_unit Decimal(10, 4)
) ENGINE = SummingMergeTree()
ORDER BY (product_id, year, month);

INSERT INTO cube_sales_product_statement2
SELECT 
    p.product_id,
    d.year,
    d.month,
    sum(f.quantity) AS gross_quantity,
    0 AS return_quantity,
    sum(f.quantity) AS net_quantity,
    sum(f.gross_sales_amount) AS gross_revenue,
    sum(f.discount_amount) AS discount_amount,
    0.00 AS refund_amount,
    sum(f.net_sales_amount) AS net_revenue,
    sum(f.quantity * f.cogs) AS total_cogs,
    (sum(f.net_sales_amount) - sum(f.quantity * f.cogs)) AS gross_profit,
    if(sum(f.net_sales_amount) > 0, ((sum(f.net_sales_amount) - sum(f.quantity * f.cogs)) / sum(f.net_sales_amount)) * 100, 0) AS gross_margin_pct,
    0.00 AS return_rate,
    if(sum(f.quantity) > 0, sum(f.net_sales_amount) / sum(f.quantity), 0) AS avg_net_price_per_unit
FROM fact_sales AS f
INNER JOIN cube_product_statement2 AS p ON f.product_key = p.product_id
INNER JOIN dim_date AS d ON f.order_date_key = d.date_key
WHERE f.order_status != 'Cancelled'
GROUP BY p.product_id, d.year, d.month;