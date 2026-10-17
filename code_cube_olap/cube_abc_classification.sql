CREATE OR REPLACE VIEW OLAP_CUBE_ABC_CLASSIFICATION AS
WITH Product_Revenue AS (
    -- 1. Tính tổng doanh thu thực (Net Revenue) cho từng Sản phẩm
    SELECT 
        p.product_key,
        p.product_id,
        p.product_name,
        p.category,
        SUM(f.net_sales_amount) AS net_revenue,
        SUM(f.quantity) AS total_quantity_sold
    FROM FACT_SALES f
    JOIN DIM_PRODUCT p ON f.product_key = p.product_key
    WHERE f.order_status = 'delivered' -- Chỉ tính đơn hàng giao thành công
      AND p.product_id != 'UNKNOWN'    -- Bỏ qua dòng Dummy (-1)
    GROUP BY p.product_key, p.product_id, p.product_name, p.category
    HAVING SUM(f.net_sales_amount) > 0 -- Chỉ xếp hạng các sản phẩm có phát sinh doanh thu
),
Cumulative_Calculations AS (
    -- 2. Sắp xếp giảm dần và tính toán Tích lũy (Cumulative) bằng Window Functions
    SELECT 
        *,
        -- Tổng doanh thu toàn hệ thống
        SUM(net_revenue) OVER () AS grand_total_revenue,
        
        -- Tổng số lượng SKU toàn hệ thống
        COUNT(product_id) OVER () AS total_sku_count,
        
        -- Doanh thu tích lũy (Cộng dồn từ sản phẩm bán chạy nhất đến hiện tại)
        SUM(net_revenue) OVER (
            ORDER BY net_revenue DESC 
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS cumulative_revenue,
        
        -- Số thứ tự của SKU (để tính % SKU tích lũy)
        ROW_NUMBER() OVER (ORDER BY net_revenue DESC) AS sku_rank
    FROM Product_Revenue
),
ABC_Tagging AS (
    -- 3. Gắn nhãn phân loại A, B, C dựa trên tỷ lệ phần trăm tích lũy
    SELECT 
        *,
        -- Tính % Doanh thu tích lũy
        (cumulative_revenue / grand_total_revenue) * 100 AS cumulative_revenue_pct,
        
        -- Tính % SKU tích lũy
        (CAST(sku_rank AS DOUBLE) / total_sku_count) * 100 AS cumulative_sku_pct,
        
        -- Phân loại ABC: A (<= 80%), B (80% - 95%), C (> 95%)
        CASE 
            WHEN (cumulative_revenue / grand_total_revenue) <= 0.80 THEN 'Nhóm A (Ngôi sao)'
            WHEN (cumulative_revenue / grand_total_revenue) <= 0.95 THEN 'Nhóm B (Trung bình)'
            ELSE 'Nhóm C (Đuôi dài)'
        END AS abc_class
    FROM Cumulative_Calculations
),
Inventory_Metrics AS (
    -- 4. Lấy dữ liệu tồn kho để đối chiếu với nhóm phân loại
    SELECT 
        product_key,
        AVG(stock_on_hand) AS avg_stock_on_hand,
        AVG(days_of_supply) AS avg_days_of_supply,
        SUM(CASE WHEN stockout_flag THEN 1 ELSE 0 END) AS total_stockout_events
    FROM FACT_INVENTORY_SNAPSHOT
    GROUP BY product_key
)
-- 5. Xuất kết quả cuối cùng kèm Đề xuất chính sách tự động
SELECT 
    a.product_id,
    a.product_name,
    a.category,
    
    -- Metrics Doanh thu
    a.net_revenue,
    a.total_quantity_sold,
    ROUND((a.net_revenue / a.grand_total_revenue) * 100, 4) AS revenue_share_pct,
    ROUND(a.cumulative_revenue_pct, 2) AS cumulative_revenue_pct,
    ROUND(a.cumulative_sku_pct, 2) AS cumulative_sku_pct,
    
    -- Phân loại ABC
    a.abc_class,
    
    -- Metrics Tồn kho
    COALESCE(ROUND(i.avg_stock_on_hand, 0), 0) AS avg_stock_on_hand,
    COALESCE(ROUND(i.avg_days_of_supply, 1), 0) AS avg_days_of_supply,
    COALESCE(i.total_stockout_events, 0) AS total_stockout_events,
    
    -- Đề xuất Chính sách Vận hành (Dựa trên Problem Statement)
    CASE 
        WHEN a.abc_class = 'Nhóm A (Ngôi sao)' 
            THEN 'Kiểm soát CHẶT (JIT): Nhập lô nhỏ thường xuyên, kiểm kê hàng tuần. Service Level >= 98%.'
        WHEN a.abc_class = 'Nhóm B (Trung bình)' 
            THEN 'Kiểm soát BÌNH THƯỜNG: Đặt hàng theo Reorder Point, kiểm kê hàng tháng. Service Level 90-95%.'
        WHEN a.abc_class = 'Nhóm C (Đuôi dài)' 
            THEN 'Kiểm soát ĐƠN GIẢN: Nhập lô lớn (Bulk), kiểm kê quý/năm. Service Level 80-85% (Ưu tiên xả hàng).'
    END AS operation_policy_recommendation

FROM ABC_Tagging a
LEFT JOIN Inventory_Metrics i ON a.product_key = i.product_key
ORDER BY a.net_revenue DESC;
