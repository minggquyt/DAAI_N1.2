CREATE OR REPLACE VIEW OLAP_CUBE_CLASS_PERFORMANCE AS
WITH Product_Class_Sales AS (
    -- 1. Tổng hợp số lượng bán ở cấp độ Sản phẩm, gắn kèm thuộc tính Class (Segment)
    SELECT 
        p.segment AS class_name,
        p.product_id,
        SUM(f.quantity) AS gross_quantity,
        -- Chú ý: Thay số 0 dưới đây bằng cột return_quantity nếu DB của bạn đã bổ sung bảng RETURNS
        0 AS returned_quantity 
    FROM FACT_SALES f
    JOIN DIM_PRODUCT p ON f.product_key = p.product_key
    -- ĐÃ SỬA: Lọc chuẩn xác trạng thái bằng chữ thường theo đúng DB của bạn
    WHERE f.order_status = 'delivered' 
      AND p.segment != 'N/A' -- Bỏ qua dòng Dummy
    GROUP BY p.segment, p.product_id
),
Class_Aggregates AS (
    -- 2. Gom nhóm các Measure theo từng Class
    SELECT 
        class_name,
        COUNT(DISTINCT product_id) AS product_count,
        SUM(gross_quantity) AS class_total_qty,
        SUM(returned_quantity) AS class_returned_qty,
        (SUM(gross_quantity) - SUM(returned_quantity)) AS class_net_qty
    FROM Product_Class_Sales
    GROUP BY class_name
),
System_Totals AS (
    -- 3. Tính toán các chỉ số Trung bình Toàn hệ thống (Dùng Window Function OVER() để gán cho mọi dòng)
    SELECT 
        class_name,
        product_count,
        class_total_qty,
        class_returned_qty,
        class_net_qty,
        
        -- Số lượng trung bình trên mỗi sản phẩm CỦA CLASS
        CAST(class_net_qty AS DOUBLE) / NULLIF(product_count, 0) AS class_avg_qty_per_product,
        
        -- Tổng toàn hệ thống
        SUM(class_net_qty) OVER() AS system_total_net_qty,
        SUM(product_count) OVER() AS system_total_product_count
    FROM Class_Aggregates
)
-- 4. Tính Metrics, KPI và xuất kết quả cuối cùng
SELECT 
    class_name,
    product_count,
    class_net_qty AS net_quantity_sold,
    
    -- Metric 1: Average Quantity per Product (Class)
    ROUND(class_avg_qty_per_product, 2) AS avg_qty_per_product,
    
    -- Metric 2: Quantity Contribution (%)
    ROUND((class_net_qty / NULLIF(system_total_net_qty, 0)) * 100, 2) AS quantity_contribution_pct,
    
    -- Metric 3: Class Return Rate (%)
    ROUND((class_returned_qty / NULLIF(class_total_qty, 0)) * 100, 2) AS class_return_rate_pct,
    
    -- Tham chiếu: Average Quantity per Product (Toàn hệ thống)
    ROUND(system_total_net_qty / NULLIF(system_total_product_count, 0), 2) AS system_avg_qty_per_product,
    
    -- KPI: Consumption Performance Index (CPI) (%)
    ROUND(
        (class_avg_qty_per_product / NULLIF((system_total_net_qty / NULLIF(system_total_product_count, 0)), 0)) * 100, 
    2) AS consumption_performance_index_pct,
    
    -- Đánh giá tự động theo Ma trận KPI
    CASE 
        -- Đóng góp > Mức chia đều toàn hệ thống VÀ Hiệu suất > 100%
        WHEN (class_net_qty / NULLIF(system_total_net_qty, 0)) >= (1.0 / NULLIF(COUNT(*) OVER(), 0)) 
             AND (class_avg_qty_per_product / NULLIF((system_total_net_qty / NULLIF(system_total_product_count, 0)), 0)) >= 1
        THEN 'Đóng góp LỚN - Hiệu suất TỐT'
        
        WHEN (class_net_qty / NULLIF(system_total_net_qty, 0)) >= (1.0 / NULLIF(COUNT(*) OVER(), 0)) 
             AND (class_avg_qty_per_product / NULLIF((system_total_net_qty / NULLIF(system_total_product_count, 0)), 0)) < 1
        THEN 'Đóng góp LỚN - Hiệu suất KÉM'
        
        WHEN (class_net_qty / NULLIF(system_total_net_qty, 0)) < (1.0 / NULLIF(COUNT(*) OVER(), 0)) 
             AND (class_avg_qty_per_product / NULLIF((system_total_net_qty / NULLIF(system_total_product_count, 0)), 0)) >= 1
        THEN 'Đóng góp NHỎ - Hiệu suất TỐT'
        
        ELSE 'Đóng góp NHỎ - Hiệu suất KÉM'
    END AS evaluation_matrix

FROM System_Totals;
