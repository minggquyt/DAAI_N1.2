-- ========================================================
-- DATABASE SETUP & CLEANUP
-- ========================================================
CREATE DATABASE DA;
GO
USE DA;
GO


-- Xóa các bảng Fact trước nếu đã tồn tại để tránh xung đột Foreign Key
DROP TABLE IF EXISTS dbo.FACT_SALES;
DROP TABLE IF EXISTS dbo.FACT_INVENTORY_SNAPSHOT;
DROP TABLE IF EXISTS dbo.FACT_WEB_TRAFFIC;

-- Xóa các bảng Dimension
DROP TABLE IF EXISTS dbo.DIM_DATE;
DROP TABLE IF EXISTS dbo.DIM_CUSTOMER;
DROP TABLE IF EXISTS dbo.DIM_PRODUCT;
DROP TABLE IF EXISTS dbo.DIM_SALES_EMPLOYEE;
DROP TABLE IF EXISTS dbo.DIM_SHIPPER;
DROP TABLE IF EXISTS dbo.DIM_PROMOTION;
DROP TABLE IF EXISTS dbo.DIM_GEOGRAPHY;
GO

-- ========================================================
-- 1. DIMENSION TABLES
-- ========================================================

-- 1.1. Bảng Chiều Ngày (Date Dimension)
-- Lưu ý: date_key thường dùng định dạng YYYYMMDD (INT) thay vì IDENTITY
CREATE TABLE dbo.DIM_DATE (
    date_key INT NOT NULL,
    full_date DATE NOT NULL,
    day_of_week TINYINT NOT NULL,
    day_name NVARCHAR(20) NOT NULL,
    day_of_month TINYINT NOT NULL,
    [month] TINYINT NOT NULL,
    month_name NVARCHAR(20) NOT NULL,
    quarter TINYINT NOT NULL,
    [year] INT NOT NULL,
    is_weekend BIT NOT NULL,
    CONSTRAINT PK_DIM_DATE PRIMARY KEY CLUSTERED (date_key)
);
GO

-- 1.2. Bảng Chiều Khách hàng (Đã denormalize địa lý của khách)
CREATE TABLE dbo.DIM_CUSTOMER (
    customer_key INT IDENTITY(1,1) NOT NULL,
    customer_id VARCHAR(50) NOT NULL,
    signup_date DATE NULL,
    gender NVARCHAR(20) NULL,
    age_group NVARCHAR(50) NULL,
    acq_channel NVARCHAR(50) NULL,
    city NVARCHAR(100) NULL,
    region NVARCHAR(100) NULL,
    district NVARCHAR(100) NULL,
    zip VARCHAR(20) NULL,
    CONSTRAINT PK_DIM_CUSTOMER PRIMARY KEY CLUSTERED (customer_key)
);
GO

-- 1.3. Bảng Chiều Sản phẩm
CREATE TABLE dbo.DIM_PRODUCT (
    product_key INT IDENTITY(1,1) NOT NULL,
    product_id VARCHAR(50) NOT NULL,
    product_name NVARCHAR(255) NOT NULL,
    category NVARCHAR(100) NULL,
    segment NVARCHAR(100) NULL,
    size VARCHAR(20) NULL,
    color NVARCHAR(50) NULL,
    current_price DECIMAL(18, 2) NULL,
    current_cogs DECIMAL(18, 2) NULL,
    CONSTRAINT PK_DIM_PRODUCT PRIMARY KEY CLUSTERED (product_key)
);
GO

-- 1.4. Bảng Chiều Nhân viên bán hàng
CREATE TABLE dbo.DIM_SALES_EMPLOYEE (
    sales_employee_key INT IDENTITY(1,1) NOT NULL,
    sales_employee_id VARCHAR(50) NOT NULL,
    employee_name NVARCHAR(150) NOT NULL,
    marital_status NVARCHAR(50) NULL,
    education_level NVARCHAR(100) NULL,
    years_experience INT NULL,
    CONSTRAINT PK_DIM_SALES_EMPLOYEE PRIMARY KEY CLUSTERED (sales_employee_key)
);
GO

-- 1.5. Bảng Chiều Đối tác giao hàng (Shipper)
CREATE TABLE dbo.DIM_SHIPPER (
    shipper_key INT IDENTITY(1,1) NOT NULL,
    shipper_id VARCHAR(50) NOT NULL,
    shipper_name NVARCHAR(150) NOT NULL,
    shipper_phone VARCHAR(30) NULL,
    shipper_gender NVARCHAR(20) NULL,
    company NVARCHAR(100) NULL,
    vehicle NVARCHAR(50) NULL,
    working_shift NVARCHAR(50) NULL,
    CONSTRAINT PK_DIM_SHIPPER PRIMARY KEY CLUSTERED (shipper_key)
);
GO

-- 1.6. Bảng Chiều Chương trình khuyến mãi
CREATE TABLE dbo.DIM_PROMOTION (
    promo_key INT IDENTITY(1,1) NOT NULL,
    promo_id VARCHAR(50) NOT NULL,
    promo_name NVARCHAR(255) NOT NULL,
    promo_type NVARCHAR(100) NULL,
    discount_value DECIMAL(18, 2) NULL,
    promo_channel NVARCHAR(50) NULL,
    app_category NVARCHAR(100) NULL,
    stackable_flag BIT NULL,
    CONSTRAINT PK_DIM_PROMOTION PRIMARY KEY CLUSTERED (promo_key)
);
GO

-- 1.7. Bảng Chiều Địa lý giao hàng (Shipping Destination)
CREATE TABLE dbo.DIM_GEOGRAPHY (
    geography_key INT IDENTITY(1,1) NOT NULL,
    zip VARCHAR(20) NOT NULL,
    city NVARCHAR(100) NULL,
    region NVARCHAR(100) NULL,
    district NVARCHAR(100) NULL,
    CONSTRAINT PK_DIM_GEOGRAPHY PRIMARY KEY CLUSTERED (geography_key)
);
GO

-- ========================================================
-- 2. FACT TABLES & RELATIONSHIPS
-- ========================================================

-- 2.1. Fact Bán hàng (Grain: từng dòng chi tiết đơn hàng - Line Item)
CREATE TABLE dbo.FACT_SALES (
    sales_fact_id BIGINT IDENTITY(1,1) NOT NULL,
    
    -- Khóa ngoại tham chiếu Dimension
    order_date_key INT NOT NULL,
    ship_date_key INT NULL,
    delivery_date_key INT NULL,
    customer_key INT NOT NULL,
    product_key INT NOT NULL,
    order_geo_key INT NOT NULL,
    sales_employee_key INT NULL,
    shipper_key INT NULL,
    promo_key_1 INT NULL,
    promo_key_2 INT NULL,
    
    -- Degenerate Dimensions (Thuộc tính không gom vào bảng Dim)
    order_id VARCHAR(50) NOT NULL,
    order_status VARCHAR(50) NULL,
    device_type VARCHAR(50) NULL,
    order_source VARCHAR(50) NULL,
    payment_method VARCHAR(50) NULL,
    
    -- Measures (Chỉ số đo lường)
    quantity INT NOT NULL,
    unit_price DECIMAL(18, 2) NOT NULL,
    cogs DECIMAL(18, 2) NOT NULL,
    discount_amount DECIMAL(18, 2) DEFAULT 0.00,
    gross_sales_amount DECIMAL(18, 2) NOT NULL,
    net_sales_amount DECIMAL(18, 2) NOT NULL,
    shipping_fee DECIMAL(18, 2) DEFAULT 0.00,
    payment_value DECIMAL(18, 2) NULL,
    installments INT DEFAULT 1,
    delivery_duration_days DECIMAL(5, 2) NULL,

    -- Ràng buộc Primary Key & Foreign Keys
    CONSTRAINT PK_FACT_SALES PRIMARY KEY CLUSTERED (sales_fact_id),
    CONSTRAINT FK_FACT_SALES_ORDER_DATE FOREIGN KEY (order_date_key) REFERENCES dbo.DIM_DATE(date_key),
    CONSTRAINT FK_FACT_SALES_SHIP_DATE FOREIGN KEY (ship_date_key) REFERENCES dbo.DIM_DATE(date_key),
    CONSTRAINT FK_FACT_SALES_DELIVERY_DATE FOREIGN KEY (delivery_date_key) REFERENCES dbo.DIM_DATE(date_key),
    CONSTRAINT FK_FACT_SALES_CUSTOMER FOREIGN KEY (customer_key) REFERENCES dbo.DIM_CUSTOMER(customer_key),
    CONSTRAINT FK_FACT_SALES_PRODUCT FOREIGN KEY (product_key) REFERENCES dbo.DIM_PRODUCT(product_key),
    CONSTRAINT FK_FACT_SALES_GEOGRAPHY FOREIGN KEY (order_geo_key) REFERENCES dbo.DIM_GEOGRAPHY(geography_key),
    CONSTRAINT FK_FACT_SALES_EMPLOYEE FOREIGN KEY (sales_employee_key) REFERENCES dbo.DIM_SALES_EMPLOYEE(sales_employee_key),
    CONSTRAINT FK_FACT_SALES_SHIPPER FOREIGN KEY (shipper_key) REFERENCES dbo.DIM_SHIPPER(shipper_key),
    CONSTRAINT FK_FACT_SALES_PROMO_1 FOREIGN KEY (promo_key_1) REFERENCES dbo.DIM_PROMOTION(promo_key),
    CONSTRAINT FK_FACT_SALES_PROMO_2 FOREIGN KEY (promo_key_2) REFERENCES dbo.DIM_PROMOTION(promo_key)
);
GO

-- 2.2. Fact Tồn kho định kỳ (Periodic Snapshot Fact Table)
CREATE TABLE dbo.FACT_INVENTORY_SNAPSHOT (
    inventory_snapshot_id BIGINT IDENTITY(1,1) NOT NULL,
    
    -- Khóa ngoại tham chiếu Dimension
    snapshot_date_key INT NOT NULL,
    product_key INT NOT NULL,
    
    -- Measures
    stock_on_hand INT NOT NULL,
    units_received INT NOT NULL DEFAULT 0,
    units_sold INT NOT NULL DEFAULT 0,
    stockout_days INT DEFAULT 0,
    days_of_supply DECIMAL(8, 2) NULL,
    fill_rate DECIMAL(5, 4) NULL,
    sell_through_rate DECIMAL(5, 4) NULL,
    stockout_flag BIT DEFAULT 0,
    overstock_flag BIT DEFAULT 0,
    reorder_flag BIT DEFAULT 0,

    -- Ràng buộc Primary Key & Foreign Keys
    CONSTRAINT PK_FACT_INVENTORY_SNAPSHOT PRIMARY KEY CLUSTERED (inventory_snapshot_id),
    CONSTRAINT FK_FACT_INVENTORY_DATE FOREIGN KEY (snapshot_date_key) REFERENCES dbo.DIM_DATE(date_key),
    CONSTRAINT FK_FACT_INVENTORY_PRODUCT FOREIGN KEY (product_key) REFERENCES dbo.DIM_PRODUCT(product_key)
);
GO

-- 2.3. Fact Lưu lượng truy cập Web
CREATE TABLE dbo.FACT_WEB_TRAFFIC (
    web_traffic_id BIGINT IDENTITY(1,1) NOT NULL,
    
    -- Khóa ngoại tham chiếu Dimension
    date_key INT NOT NULL,
    
    -- Degenerate Dimension
    traffic_source VARCHAR(100) NOT NULL,
    
    -- Measures
    sessions INT NOT NULL DEFAULT 0,
    unique_visitors INT NOT NULL DEFAULT 0,
    page_views INT NOT NULL DEFAULT 0,
    bounce_rate DECIMAL(5, 4) NULL,
    avg_session_duration DECIMAL(10, 2) NULL,

    -- Ràng buộc Primary Key & Foreign Keys
    CONSTRAINT PK_FACT_WEB_TRAFFIC PRIMARY KEY CLUSTERED (web_traffic_id),
    CONSTRAINT FK_FACT_WEB_TRAFFIC_DATE FOREIGN KEY (date_key) REFERENCES dbo.DIM_DATE(date_key)
);
GO

-- ========================================================
-- 3. INDEX TỐI ƯU HÓA HIỆU NĂNG QUERY TRÊN FACT
-- ========================================================
-- Tạo Non-Clustered Index trên các trường Foreign Key hay dùng để JOIN hoặc FILTER
CREATE NONCLUSTERED INDEX IX_FACT_SALES_ORDER_DATE ON dbo.FACT_SALES (order_date_key);
CREATE NONCLUSTERED INDEX IX_FACT_SALES_CUSTOMER ON dbo.FACT_SALES (customer_key);
CREATE NONCLUSTERED INDEX IX_FACT_SALES_PRODUCT ON dbo.FACT_SALES (product_key);

CREATE NONCLUSTERED INDEX IX_FACT_INVENTORY_DATE_PROD ON dbo.FACT_INVENTORY_SNAPSHOT (snapshot_date_key, product_key);
GO