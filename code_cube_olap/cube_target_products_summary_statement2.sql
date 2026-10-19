-- ============================================================
-- Cube 5: Cube Tổng Hợp Sản Phẩm Mục Tiêu (cube_target_products_summary_statement2)
-- ============================================================
DROP TABLE IF EXISTS cube_target_products_summary_statement2;

CREATE TABLE cube_target_products_summary_statement2 (
    product_id UInt32,
    product_name String,
    category LowCardinality(String),
    total_net_quantity Int32,
    total_net_revenue Decimal(18, 2),
    overall_gross_margin_pct Decimal(10, 4),
    overall_return_rate Decimal(10, 4),
    p75_demand_threshold Float64,
    is_target_product String,
    avg_discount_rate_pct Decimal(10, 4),
    total_stockout_days Int32
) ENGINE = MergeTree()
ORDER BY (product_id);

INSERT INTO cube_target_products_summary_statement2
WITH base_prod AS (
    SELECT 
        s.product_id, 
        p.product_name, 
        p.category, 
        sum(s.net_quantity) AS net_qty, 
        sum(s.net_revenue) AS net_rev, 
        (sum(s.gross_profit) / nullIf(sum(s.net_revenue), 0)) * 100 AS margin_pct, 
        0.0 AS ret_rate 
    FROM cube_sales_product_statement2 AS s 
    INNER JOIN cube_product_statement2 AS p ON s.product_id = p.product_id 
    GROUP BY s.product_id, p.product_name, p.category
), quantile_calc AS (
    SELECT quantileExact(0.75)(net_qty) AS p75 FROM base_prod
), promo_agg AS (
    SELECT 
        product_id, 
        if(sum(gross_revenue) > 0, (sum(discount_amount) / sum(gross_revenue)) * 100, 0.0) AS disc_rate 
    FROM cube_promo_impact_statement2 
    GROUP BY product_id
), inv_agg AS (
    SELECT 
        product_id, 
        sum(total_stockout_days) AS stockout 
    FROM cube_inventory_demand_statement2 
    GROUP BY product_id
)
SELECT 
    b.product_id, 
    b.product_name, 
    b.category, 
    b.net_qty, 
    b.net_rev, 
    b.margin_pct, 
    b.ret_rate, 
    q.p75, 
    if(b.net_qty >= q.p75 AND b.margin_pct < 20.0, 'High Demand - Low Margin', 'Normal Product'), 
    coalesce(pr.disc_rate, 0.0), 
    coalesce(i.stockout, 0) 
FROM base_prod AS b 
CROSS JOIN quantile_calc AS q 
LEFT JOIN promo_agg AS pr ON b.product_id = pr.product_id 
LEFT JOIN inv_agg AS i ON b.product_id = i.product_id;