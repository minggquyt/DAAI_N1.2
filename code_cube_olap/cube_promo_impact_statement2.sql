-- ============================================================
-- Cube 3: Tác Động Khuyến Mãi (cube_promo_impact_statement2)
-- ============================================================
DROP TABLE IF EXISTS cube_promo_impact_statement2;

CREATE TABLE cube_promo_impact_statement2 (
    product_id UInt32,
    promo_id String,
    promo_name String,
    year UInt16,
    month UInt8,
    discount_amount Decimal(18, 2),
    gross_revenue Decimal(18, 2),
    discount_rate Decimal(10, 4)
) ENGINE = SummingMergeTree()
ORDER BY (product_id, promo_id, year, month);

INSERT INTO cube_promo_impact_statement2
SELECT 
    p.product_id,
    pr.promo_id,
    pr.promo_name,
    d.year,
    d.month,
    sum(f.discount_amount),
    sum(f.gross_sales_amount),
    cast(if(sum(f.gross_sales_amount) > 0, sum(f.discount_amount) / sum(f.gross_sales_amount), 0), 'Decimal(10, 4)')
FROM fact_sales AS f
INNER JOIN cube_product_statement2 AS p ON f.product_key = p.product_id
INNER JOIN dim_promotion AS pr ON f.promo_key_1 = pr.promo_key
INNER JOIN dim_date AS d ON f.order_date_key = d.date_key
WHERE f.order_status != 'cancelled'
GROUP BY p.product_id, pr.promo_id, pr.promo_name, d.year, d.month;