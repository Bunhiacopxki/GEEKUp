USE cv;

-- Thủ tục tạo đơn hàng
DROP PROCEDURE IF EXISTS b;
DELIMITER //
CREATE PROCEDURE b(
	IN o_MaNguoiMua INT,
    IN o_ProductList JSON,
    IN o_PTThanhToan CHAR(20),
    IN h_PhiGiaoHang DECIMAL(18, 2),
    IN h_GiamGiaKhiGiaoHang DECIMAL(18, 2),
    IN h_XuatHoaDon tinyint(1),
    IN m_MaKM INT
)
BEGIN
    DECLARE done INT DEFAULT 0;
    DECLARE v_MaSanPham INT;
    DECLARE v_SoLuong INT;
    DECLARE v_KichThuoc CHAR(12);
    DECLARE v_MauSac VARCHAR(100);
    
    DECLARE v_gia DECIMAL(18, 2);
    DECLARE v_tyle FLOAT;
    DECLARE v_MaDonHang INT;
    DECLARE v_KhuyenMai INT DEFAULT 0;
    DECLARE v_TienGiam DECIMAL(18, 2);
    DECLARE v_end TIMESTAMP;
    DECLARE v_start TIMESTAMP;
    
    -- Cursor to loop through JSON array
    DECLARE cur CURSOR FOR 
        SELECT 
            JSON_UNQUOTE(JSON_EXTRACT(t.value, '$.MaSanPham')),
            JSON_UNQUOTE(JSON_EXTRACT(t.value, '$.SoLuong')),
            JSON_UNQUOTE(JSON_EXTRACT(t.value, '$.KichThuoc')),
            JSON_UNQUOTE(JSON_EXTRACT(t.value, '$.MauSac'))
        FROM JSON_TABLE(o_ProductList, '$[*]' COLUMNS (
            value JSON PATH '$'
        )) AS t;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;
    IF o_PTThanhToan IS NULL OR o_PTThanhToan = '' OR o_PTThanhToan != 'Đã thanh toán' OR o_PTThanhToan != 'Chưa thanh toán' THEN
		INSERT INTO DonHang (NgayDat, MaNguoiMua) 
		VALUES (CURDATE(), o_MaNguoiMua);
	ELSE
		INSERT INTO DonHang (NgayDat, MaNguoiMua, PTThanhToan) 
		VALUES (CURDATE(), o_MaNguoiMua, o_PTThanhToan);
    END IF;
    
    SET v_MaDonHang = LAST_INSERT_ID();
    
    INSERT INTO HoaDon(ThoiGianTao, TongTien, MaDonHang, PhiGiaoHang, GiamGiaKhiGiaoHang, XuatHoaDon)
	VALUES (NOW(), 0, v_MaDonHang, h_PhiGiaoHang, h_GiamGiaKhiGiaoHang, h_XuatHoaDon);

    OPEN cur;
    read_loop: LOOP
        FETCH cur INTO v_MaSanPham, v_SoLuong, v_KichThuoc, v_MauSac;
        
        SELECT Gia, TyLeGiamGia INTO v_gia, v_tyle
		FROM SanPham WHERE MaSanPham = v_MaSanPham;
        
        IF done THEN
            LEAVE read_loop;
        END IF;

        IF v_SoLuong < 0 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Số lượng sản phẩm không được nhỏ hơn 0.';
        END IF;

        IF v_KichThuoc IS NULL OR v_KichThuoc = '' THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Kích thước không được để trống.';
        END IF;

        IF NOT EXISTS (SELECT 1 FROM KichThuoc WHERE MaSanPham = v_MaSanPham AND KichThuoc = v_KichThuoc) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Sản phẩm đã hết hàng.';
        END IF;

        IF NOT EXISTS (SELECT 1 FROM HinhAnhSanPham WHERE MaSanPham = v_MaSanPham AND MauSac = v_MauSac) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Sản phẩm không có màu này.';
        END IF;

        IF NOT EXISTS (SELECT 1 FROM SanPham WHERE MaSanPham = v_MaSanPham) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Sản phẩm không tồn tại.';
        END IF;

        INSERT INTO Co (MaDonHang, MaSanPham, SoLuong, KichThuoc, MauSac)
        VALUES (v_MaDonHang, v_MaSanPham, v_SoLuong, v_KichThuoc, v_MauSac);

        UPDATE KichThuoc SET SoLuong = SoLuong - v_SoLuong
        WHERE MaSanPham = v_MaSanPham AND KichThuoc = v_KichThuoc;
        
        UPDATE HoaDon SET TongTien = TongTien + v_SoLuong * v_gia * (1 - v_tyle)
        WHERE MaDonHang = v_MaDonHang;
    END LOOP;
    CLOSE cur;
    
    SELECT SoLuong, GiamGia, ThoiGianKT, ThoiGianBD INTO v_KhuyenMai, v_TienGiam, v_end, v_start FROM ChuongTrinhKhuyenMai WHERE MaKM = m_MaKM;
    
    IF v_KhuyenMai > 0 AND NOW() < v_end AND NOW() > v_start THEN
		INSERT INTO SuDung (MaKM, MaNguoiMua) VALUES (m_MaKM, o_MaNguoiMua);
		INSERT INTO GiamGia (MaKM, MaDonHang) VALUES (m_MaKM, v_MaDonHang);
        UPDATE ChuongTrinhKhuyenMai SET SoLuong = SoLuong - 1 WHERE MaKM = m_MaKM;
        UPDATE HoaDon SET TongTien = TongTien + h_PhiGiaoHang - h_GiamGiaKhiGiaoHang - v_TienGiam
		WHERE MaDonHang = v_MaDonHang;
	ELSE 
		UPDATE HoaDon SET TongTien = TongTien + h_PhiGiaoHang - h_GiamGiaKhiGiaoHang
		WHERE MaDonHang = v_MaDonHang;
    END IF;
END //
DELIMITER ;

-- Thủ tục tính trung bình giá trị đơn hàng
DROP PROCEDURE if exists c;
DELIMITER //
CREATE PROCEDURE c()
BEGIN
	SELECT
		YEAR(DH.NgayDat) AS Year,
		MONTH(DH.NgayDat) AS Month,
		AVG(HD.TongTien) AS AverageOrderValue -- average order value
	FROM
		DonHang DH
	JOIN
		HoaDon HD ON DH.MaDonHang = HD.MaDonHang
	WHERE
		YEAR(DH.NgayDat) = YEAR(CURDATE()) -- Trong năm nay
	GROUP BY
		YEAR(DH.NgayDat),
		MONTH(DH.NgayDat)
	ORDER BY
		Month desc;
END //
DELIMITER ;

DELIMITER //
DROP FUNCTION IF EXISTS d;
CREATE FUNCTION d() 
RETURNS DECIMAL(10,2)
DETERMINISTIC
BEGIN
    DECLARE Previous INT DEFAULT 0;
    DECLARE Churned INT DEFAULT 0;

    -- Tính Previous: số lượng khách hàng đã mua đơn hàng trong 6 tháng trước
    SELECT COUNT(DISTINCT MaNguoiMua)
    INTO Previous
    FROM DonHang
    WHERE NgayDat >= CURDATE() - INTERVAL 12 MONTH
      AND NgayDat < CURDATE() - INTERVAL 6 MONTH;

    -- Tính Churned: khách hàng đã mua 6 tháng trước nhưng không mua trong 6 tháng gần đây
    SELECT COUNT(DISTINCT p.MaNguoiMua)
    INTO Churned
    FROM (
        SELECT DISTINCT MaNguoiMua
        FROM DonHang
        WHERE NgayDat >= CURDATE() - INTERVAL 12 MONTH
          AND NgayDat < CURDATE() - INTERVAL 6 MONTH
    ) p
    LEFT JOIN (
        SELECT DISTINCT MaNguoiMua
        FROM DonHang
        WHERE NgayDat >= CURDATE() - INTERVAL 6 MONTH
    ) l ON p.MaNguoiMua = l.MaNguoiMua
    WHERE l.MaNguoiMua IS NULL;

    -- Tính tỷ lệ Churn Rate
    IF Previous = 0 THEN 
        RETURN 0.00;
    ELSE 
        RETURN (Churned / Previous) * 100;
    END IF;
END //
DELIMITER ;