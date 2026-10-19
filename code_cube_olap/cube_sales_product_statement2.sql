-- ============================================================
-- Cube 2: Bán Hàng Theo Sản Phẩm (cube_sales_product_statement2)
-- ============================================================
DROP TABLE IF EXISTS cube_sales_product_statement2;

CREATE TABLE cube_sales_product_statement2 (
    product_id UInt32,
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
    sum(if(f.order_status = 'returned', f.quantity, 0)) AS return_quantity,
    sum(if(f.order_status != 'returned', f.quantity, 0)) AS net_quantity,
    sum(f.gross_sales_amount) AS gross_revenue,
    sum(f.discount_amount) AS discount_amount,
    sum(if(f.order_status = 'returned', f.net_sales_amount, cast(0.00 as Decimal(18, 2)))) AS refund_amount,
    sum(if(f.order_status != 'returned', f.net_sales_amount, cast(0.00 as Decimal(18, 2)))) AS net_revenue,
    sum(if(f.order_status != 'returned', f.quantity * p.current_cogs, cast(0.00 as Decimal(18, 2)))) AS total_cogs,
    (sum(if(f.order_status != 'returned', f.net_sales_amount, cast(0.00 as Decimal(18, 2)))) - sum(if(f.order_status != 'returned', f.quantity * p.current_cogs, cast(0.00 as Decimal(18, 2))))) AS gross_profit,
    cast(if(sum(if(f.order_status != 'returned', f.net_sales_amount, cast(0.00 as Decimal(18, 2)))) > 0, ((sum(if(f.order_status != 'returned', f.net_sales_amount, cast(0.00 as Decimal(18, 2)))) - sum(if(f.order_status != 'returned', f.quantity * p.current_cogs, cast(0.00 as Decimal(18, 2))))) / sum(if(f.order_status != 'returned', f.net_sales_amount, cast(0.00 as Decimal(18, 2))))), 0), 'Decimal(10, 4)') AS gross_margin_pct,
    cast(if(sum(f.quantity) > 0, (sum(if(f.order_status = 'returned', f.quantity, 0)) / sum(f.quantity)), 0), 'Decimal(10, 4)') AS return_rate,
    cast(if(sum(if(f.order_status != 'returned', f.quantity, 0)) > 0, sum(if(f.order_status != 'returned', f.net_sales_amount, cast(0.00 as Decimal(18, 2)))) / sum(if(f.order_status != 'returned', f.quantity, 0)), 0), 'Decimal(10, 4)') AS avg_net_price_per_unit
FROM fact_sales AS f
INNER JOIN cube_product_statement2 AS p ON f.product_key = p.product_id
INNER JOIN dim_date AS d ON f.order_date_key = d.date_key
WHERE f.order_status != 'cancelled'
GROUP BY p.product_id, d.year, d.month;