-- ============================================================
-- Cube 6: Hệ Số Tương Quan Pearson r & Ngưỡng P75 (cube_correlation_demand_statement2)
-- Đã ép kiểu toFloat64()
-- ============================================================
DROP TABLE IF EXISTS cube_correlation_demand_statement2;

CREATE TABLE cube_correlation_demand_statement2 (
    metric_name String,
    pearson_correlation_r Float64,
    p75_demand_threshold Float64,
    total_products_analyzed UInt32
) ENGINE = MergeTree()
ORDER BY (metric_name);

INSERT INTO cube_correlation_demand_statement2
WITH product_totals AS (
    SELECT 
        product_id, 
        sum(net_quantity) AS x, 
        sum(net_revenue) AS y 
    FROM cube_sales_product_statement2 
    GROUP BY product_id
), stats AS (
    SELECT 
        count() AS n, 
        sum(x) AS sum_x, 
        sum(y) AS sum_y, 
        sum(x * x) AS sum_x2, 
        sum(y * y) AS sum_y2, 
        sum(x * y) AS sum_xy 
    FROM product_totals
), pearson_calc AS (
    SELECT 
        if((n * sum_x2 - sum_x * sum_x) * (n * sum_y2 - sum_y * sum_y) > 0, 
           toFloat64(n * sum_xy - sum_x * sum_y) / sqrt(toFloat64((n * sum_x2 - sum_x * sum_x) * (n * sum_y2 - sum_y * sum_y))), 0.0) AS r 
    FROM stats
), percentile_calc AS (
    SELECT quantileExact(0.75)(x) AS p75 FROM product_totals
), total_p AS (
    SELECT count() AS cnt FROM product_totals
)
SELECT 
    'Overall Metrics', 
    pearson_calc.r, 
    percentile_calc.p75, 
    total_p.cnt 
FROM pearson_calc 
CROSS JOIN percentile_calc 
CROSS JOIN total_p;