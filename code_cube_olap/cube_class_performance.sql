CREATE OR REPLACE VIEW OLAP_CUBE_CLASS_PERFORMANCE AS
WITH Granular_Sales AS (
    -- 1. Lấy dữ liệu bán hàng ở độ mịn: Product x Order Month
    SELECT 
        f.product_key,
        d.year,
        d.month,
        CONCAT(d.year, '-', LPAD(CAST(d.month AS VARCHAR), 2, '0')) AS order_month,
        SUM(f.quantity) AS gross_quantity,
        -- Giả định CSDL hiện tại chưa nạp bảng RETURNS, ta gán tạm 0. 
        -- Nếu đã có, bạn thay bằng: SUM(r.return_quantity)
        0 AS returned_quantity, 
        SUM(f.net_sales_amount) AS net_revenue
    FROM FACT_SALES f
    JOIN DIM_DATE d ON f.order_date_key = d.date_key
    -- Áp dụng ngay bài học sửa lỗi từ trước: dùng chữ thường
    WHERE f.order_status = 'delivered' 
    GROUP BY f.product_key, d.year, d.month, CONCAT(d.year, '-', LPAD(CAST(d.month AS VARCHAR), 2, '0'))
),
Granular_Inventory AS (
    -- 2. Lấy dữ liệu tồn kho trung bình của từng sản phẩm
    SELECT 
        product_key,
        AVG(stock_on_hand) AS stock_on_hand,
        AVG(sell_through_rate) AS sell_through_rate
    FROM FACT_INVENTORY_SNAPSHOT
    GROUP BY product_key
),
Base_Cube AS (
    -- 3. Nối thành bảng phẳng (Flat Table) chi tiết cấp Product x Month
    SELECT 
        p.product_key,
        p.product_id,
        p.product_name,
        p.category,
        p.segment AS class_name,
        s.order_month,
        COALESCE(s.gross_quantity, 0) AS gross_quantity,
        COALESCE(s.returned_quantity, 0) AS returned_quantity,
        (COALESCE(s.gross_quantity, 0) - COALESCE(s.returned_quantity, 0)) AS net_quantity_sold,
        COALESCE(s.net_revenue, 0) AS net_revenue,
        COALESCE(i.stock_on_hand, 0) AS stock_on_hand,
        COALESCE(i.sell_through_rate, 0) AS sell_through_rate
    FROM DIM_PRODUCT p
    LEFT JOIN Granular_Sales s ON p.product_key = s.product_key
    LEFT JOIN Granular_Inventory i ON p.product_key = i.product_key
    WHERE p.product_id != 'UNKNOWN'
),
Class_KPIs AS (
    -- 4. Vượt cấp độ mịn: Tính tổng các chỉ số vĩ mô cho riêng từng Class
    SELECT 
        class_name,
        COUNT(DISTINCT product_id) AS class_total_skus,
        COUNT(DISTINCT CASE WHEN net_quantity_sold > 0 THEN product_id END) AS class_active_skus,
        SUM(net_quantity_sold) AS class_net_qty,
        SUM(returned_quantity) AS class_returned_qty,
        SUM(gross_quantity) AS class_gross_qty
    FROM Base_Cube
    GROUP BY class_name
),
System_KPIs AS (
    -- 5. Tính tổng các chỉ số vĩ mô của TOÀN HỆ THỐNG
    SELECT 
        COUNT(DISTINCT product_id) AS system_total_skus,
        SUM(net_quantity_sold) AS system_net_qty
    FROM Base_Cube
),
Class_Evaluated AS (
    -- 6. Tính CPI, Tỷ trọng đóng góp và tự động phân loại Ma trận 4 góc
    SELECT 
        c.class_name,
        c.class_total_skus,
        (CAST(c.class_active_skus AS DOUBLE) / NULLIF(c.class_total_skus, 0)) * 100 AS active_sku_coverage_pct,
        (CAST(c.class_returned_qty AS DOUBLE) / NULLIF(c.class_gross_qty, 0)) * 100 AS class_return_rate_pct,
        
        -- Quantity Contribution (%)
        (CAST(c.class_net_qty AS DOUBLE) / NULLIF(s.system_net_qty, 0)) * 100 AS quantity_contribution_pct,
        
        -- Consumption Performance Index (CPI) = (Năng suất Class) / (Năng suất Hệ thống)
        ( (CAST(c.class_net_qty AS DOUBLE) / NULLIF(c.class_total_skus, 0)) / 
          NULLIF((CAST(s.system_net_qty AS DOUBLE) / NULLIF(s.system_total_skus, 0)), 0) ) * 100 AS cpi_index,
          
        -- Chấm điểm Ma Trận dựa trên Mức TB hệ thống (1.0 / Số lượng Class) và CPI (100%)
        CASE 
            WHEN (CAST(c.class_net_qty AS DOUBLE) / NULLIF(s.system_net_qty, 0)) >= (1.0 / (SELECT COUNT(*) FROM Class_KPIs))
                 AND 
                 ( (CAST(c.class_net_qty AS DOUBLE) / NULLIF(c.class_total_skus, 0)) / NULLIF((CAST(s.system_net_qty AS DOUBLE) / NULLIF(s.system_total_skus, 0)), 0) ) >= 1.0
            THEN 'Nhóm Đầu tàu (Star Class)'
            
            WHEN (CAST(c.class_net_qty AS DOUBLE) / NULLIF(s.system_net_qty, 0)) >= (1.0 / (SELECT COUNT(*) FROM Class_KPIs))
                 AND 
                 ( (CAST(c.class_net_qty AS DOUBLE) / NULLIF(c.class_total_skus, 0)) / NULLIF((CAST(s.system_net_qty AS DOUBLE) / NULLIF(s.system_total_skus, 0)), 0) ) < 1.0
            THEN 'Nhóm Quy mô rộng nhưng phân tán (Volume Driver)'
            
            WHEN (CAST(c.class_net_qty AS DOUBLE) / NULLIF(s.system_net_qty, 0)) < (1.0 / (SELECT COUNT(*) FROM Class_KPIs))
                 AND 
                 ( (CAST(c.class_net_qty AS DOUBLE) / NULLIF(c.class_total_skus, 0)) / NULLIF((CAST(s.system_net_qty AS DOUBLE) / NULLIF(s.system_total_skus, 0)), 0) ) >= 1.0
            THEN 'Nhóm Tiềm năng (High Potential / Niche)'
            
            ELSE 'Nhóm Kém hiệu quả (Underperforming)'
        END AS class_performance_matrix
        
    FROM Class_KPIs c
    CROSS JOIN System_KPIs s
)
-- 7. Nối dữ liệu vi mô (Base_Cube) với đánh giá vĩ mô (Class_Evaluated) để xuất Parquet
SELECT 
    b.product_id,
    b.product_name,
    b.category,
    b.class_name,
    b.order_month,
    
    -- Khối 1: Các Measure nguyên thủy cho Product x Month
    b.gross_quantity,
    b.returned_quantity,
    b.net_quantity_sold,
    b.net_revenue,
    ROUND(b.stock_on_hand, 0) AS stock_on_hand,
    ROUND(b.sell_through_rate, 2) AS sell_through_rate,
    
    -- Khối 2: Các KPI vĩ mô gắn theo Class (để Power BI vẽ Scatter Plot trực tiếp)
    ROUND(c.active_sku_coverage_pct, 2) AS active_sku_coverage_pct,
    ROUND(c.class_return_rate_pct, 2) AS class_return_rate_pct,
    ROUND(c.quantity_contribution_pct, 2) AS quantity_contribution_pct,
    ROUND(c.cpi_index, 2) AS cpi_index,
    c.class_performance_matrix
    
FROM Base_Cube b
LEFT JOIN Class_Evaluated c ON b.class_name = c.class_name;
