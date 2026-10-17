CREATE OR REPLACE VIEW OLAP_CUBE_INVENTORY_TURNOVER AS
WITH Sales_Aggregates AS (
    -- 1. Thống kê sản lượng bán và quy mô đơn hàng theo Category và Class (Segment)
    SELECT 
        p.category,
        p.segment AS class_name,
        SUM(f.quantity) AS total_units_sold,
        COUNT(DISTINCT f.order_id) AS total_successful_orders
    FROM FACT_SALES f
    JOIN DIM_PRODUCT p ON f.product_key = p.product_key
    WHERE p.category != 'Không xác định'
    GROUP BY p.category, p.segment
),
Inventory_Aggregates AS (
    -- 2. Thống kê số liệu tồn kho, tốc độ và các cờ cảnh báo
    SELECT 
        p.category,
        p.segment AS class_name,
        AVG(i.stock_on_hand) AS avg_stock_on_hand,
        SUM(i.units_sold) AS inv_units_sold,
        AVG(i.days_of_supply) AS avg_days_of_supply,
        AVG(i.sell_through_rate) AS avg_sell_through_rate,
        
        -- Đếm số lần xuất hiện của các cờ cảnh báo
        SUM(CASE WHEN i.stockout_flag THEN 1 ELSE 0 END) AS stockout_count,
        SUM(CASE WHEN i.overstock_flag THEN 1 ELSE 0 END) AS overstock_count,
        SUM(CASE WHEN i.reorder_flag THEN 1 ELSE 0 END) AS reorder_count,
        COUNT(*) AS total_inventory_records
    FROM FACT_INVENTORY_SNAPSHOT i
    JOIN DIM_PRODUCT p ON i.product_key = p.product_key
    WHERE p.category != 'Không xác định'
    GROUP BY p.category, p.segment
),
Combined_Metrics AS (
    -- 3. Ghép nối Sales và Inventory, tính toán Metrics và Tỷ trọng (Window Functions)
    SELECT 
        s.category,
        s.class_name,
        
        -- Sales Metrics
        COALESCE(s.total_units_sold, 0) AS total_units_sold,
        COALESCE(s.total_successful_orders, 0) AS total_successful_orders,
        (CAST(s.total_units_sold AS DOUBLE) / NULLIF(s.total_successful_orders, 0)) AS avg_units_per_order,
        
        -- Tính tổng hệ thống và tổng danh mục để chia tỷ trọng
        SUM(s.total_units_sold) OVER () AS system_total_units,
        SUM(s.total_units_sold) OVER (PARTITION BY s.category) AS category_total_units,
        
        -- Inventory Metrics
        COALESCE(i.avg_stock_on_hand, 0) AS avg_stock_on_hand,
        COALESCE(i.avg_days_of_supply, 0) AS avg_days_of_supply,
        COALESCE(i.avg_sell_through_rate, 0) AS avg_sell_through_rate,
        
        -- Tính ITR (Inventory Turnover Rate)
        (CAST(i.inv_units_sold AS DOUBLE) / NULLIF(i.avg_stock_on_hand, 0)) AS inventory_turnover_rate,
        
        -- Tính Risk Rates (%)
        (CAST(i.stockout_count AS DOUBLE) / NULLIF(i.total_inventory_records, 0)) * 100 AS stockout_risk_rate_pct,
        (CAST(i.overstock_count AS DOUBLE) / NULLIF(i.total_inventory_records, 0)) * 100 AS overstock_ratio_pct,
        (CAST(i.reorder_count AS DOUBLE) / NULLIF(i.total_inventory_records, 0)) * 100 AS reorder_signal_rate_pct
        
    FROM Sales_Aggregates s
    LEFT JOIN Inventory_Aggregates i 
           ON s.category = i.category AND s.class_name = i.class_name
)
-- 4. Định dạng đầu ra, phân tầng Velocity và đưa ra Đề xuất hành động
SELECT 
    category,
    class_name,
    
    -- Khối 1: Sales & Contribution
    total_units_sold,
    ROUND(avg_units_per_order, 2) AS avg_units_per_order,
    ROUND((total_units_sold / NULLIF(system_total_units, 0)) * 100, 2) AS category_volume_contribution_pct,
    ROUND((total_units_sold / NULLIF(category_total_units, 0)) * 100, 2) AS class_volume_contribution_pct,
    
    -- Khối 2: Turnover & Speed
    ROUND(inventory_turnover_rate, 2) AS inventory_turnover_rate,
    ROUND(avg_days_of_supply, 1) AS avg_days_of_supply,
    ROUND(avg_sell_through_rate, 2) AS avg_sell_through_rate,
    
    -- Metric: Phân loại Tốc độ luân chuyển (Velocity Classification)
    CASE 
        WHEN avg_days_of_supply <= 60 THEN 'Cao (Fast-moving)'
        WHEN avg_days_of_supply > 60 AND avg_days_of_supply <= 180 THEN 'Trung bình (Medium-moving)'
        WHEN avg_days_of_supply > 180 THEN 'Thấp (Slow-moving)'
        ELSE 'Chưa xác định'
    END AS velocity_classification,
    
    -- Khối 3: Cảnh báo & Đề xuất hành động
    ROUND(stockout_risk_rate_pct, 2) AS stockout_risk_rate_pct,
    ROUND(overstock_ratio_pct, 2) AS overstock_ratio_pct,
    
    -- KPI: Ma trận điều phối hành động (Action Recommendation Matrix)
    CASE 
        WHEN avg_days_of_supply <= 60 AND stockout_risk_rate_pct > 3 
            THEN 'CẢNH BÁO ĐỨT HÀNG: Ưu tiên nguồn vốn nhập gấp'
        WHEN avg_days_of_supply <= 60 AND reorder_signal_rate_pct > 0 
            THEN 'Kích hoạt đặt hàng bổ sung (Reorder)'
        WHEN avg_days_of_supply > 180 AND overstock_ratio_pct > 5 
            THEN 'Ứ ĐỌNG NGHIÊM TRỌNG: Cắt giảm nhập, xả hàng ngay'
        WHEN avg_days_of_supply > 180 
            THEN 'Theo dõi chặt: Chậm luân chuyển'
        ELSE 'Ổn định: Duy trì định mức lưu kho'
    END AS action_recommendation

FROM Combined_Metrics;
