const db = require('../config/db'); // Import cấu hình kết nối cơ sở dữ liệu
const nodemailer = require("nodemailer"); // Import thư viện gửi email
const PayOS = require('@payos/node'); // Import SDK PayOS để xử lý thanh toán

// Khởi tạo đối tượng PayOS với các khóa API
const payos = new PayOS(
    '6efedd32-ab81-4896-998b-8cf32fcbc48c', 
    '0b9e71d1-0ac5-4f61-adaf-0dfbe23566ec',
    '9c53b383a1af1274a489b4b2f051a2afded703482e06f1c98c52d492086c8a7a'
);

class OrderService {
    /**
     * Phương thức Order: Xử lý việc tạo đơn hàng và gửi email xác nhận đơn hàng
     * @param {Object} data - Dữ liệu chứa mã người mua và danh sách sản phẩm
     */
    Order = async (data) => {
        const { MaNguoiMua, DanhSachSanPham, PTThanhToan, PhiGiaoHang, GiamGiaKhiGiaoHang, XuatHoaDon, MaKM } = data; // Lấy dữ liệu đầu vào
        return new Promise (async (resolve, reject) => {
            try {
                // Gọi stored procedure 'b' để thêm đơn hàng vào cơ sở dữ liệu
                const [result] = await db.query('CALL b(?, ?, ?, ?, ?, ?, ?)', [MaNguoiMua, JSON.stringify(DanhSachSanPham), PTThanhToan, PhiGiaoHang, GiamGiaKhiGiaoHang, XuatHoaDon, MaKM]);
                
                // Thiết lập cấu hình cho Nodemailer để gửi email qua Gmail
                const transporter = nodemailer.createTransport({
                    service: 'gmail', // Sử dụng dịch vụ Gmail
                    auth: {
                        user: 'thinh.nguyen04@hcmut.edu.vn', // Địa chỉ email gửi đi
                        pass: 'gfwg onwp qvin jcyn' // Mật khẩu ứng dụng Gmail
                    }
                });

                // Truy vấn email của người mua từ bảng NguoiDung
                const receiver = await db.query('SELECT Email FROM NguoiDung WHERE MaNguoiMua = ?', [MaNguoiMua]);
                
                // Cấu hình nội dung email
                const mailOptions = {
                    from: 'thinh.nguyen04@hcmut.edu.vn', // Địa chỉ email gửi đi
                    to: receiver[0][0].Email, // Địa chỉ email người nhận
                    subject: 'Xác nhận đặt hàng', // Tiêu đề email
                    text: 'Đơn hàng của bạn đã được đặt thành công!' // Nội dung email
                };

                // Gửi email bằng Nodemailer
                transporter.sendMail(mailOptions, function(error, info){
                    if (error) {
                        // Trả về lỗi nếu gửi email thất bại
                        reject({ status: false, error: error.message });
                    } else {
                        // Trả về thành công khi hoàn tất việc thêm đơn hàng và gửi email
                        resolve({ status: true, message: 'Thêm đơn hàng thành công'});
                    }
                })       
            }
            catch (error) {
                // Trả về lỗi nếu có vấn đề xảy ra trong quá trình xử lý
                reject({ status: false, error: error.message });
            }
        })
    }

    /**
     * Phương thức Value: Gọi stored procedure 'c' và trả về kết quả
     */
    Value = async (data) => {
        return new Promise (async (resolve, reject) => {
            try {
                // Gọi stored procedure 'c' từ cơ sở dữ liệu
                const [result] = await db.query('CALL c()');
                
                // Trả về kết quả từ stored procedure
                resolve({ status: true, message: result[0]});
            }
            catch (error) {
                // Trả về lỗi nếu có vấn đề trong quá trình gọi stored procedure
                reject({ status: false, error: error.message });
            }
        })
    }

    /**
     * Phương thức Payment: Xử lý thanh toán bằng PayOS và cập nhật trạng thái thanh toán đơn hàng
     * @param {Object} data - Dữ liệu chứa thông tin thanh toán
     */
    Payment = async (data) => {
        const { 
            MaDonHang, orderCode, amount, description, 
            buyerName, buyerEmail, cancelUrl, returnUrl
        } = data; // Lấy dữ liệu đầu vào từ yêu cầu thanh toán

        return new Promise (async (resolve, reject) => {
            try {
                // Lấy tổng tiền từ bảng HoaDon dựa trên MaDonHang
                const [money] = await db.query('SELECT TongTien FROM HoaDon WHERE MaDonHang = ?', [MaDonHang]);

                // Tạo link thanh toán với PayOS
                await payos.createPaymentLink(
                    orderCode, 
                    amount * money[0].TongTien, // Tổng tiền cần thanh toán
                    description, // Mô tả thanh toán
                    buyerName, // Tên người mua
                    buyerEmail, // Email người mua
                    cancelUrl, // URL khi thanh toán bị hủy
                    returnUrl // URL khi thanh toán thành công
                );

                // Cập nhật trạng thái thanh toán trong bảng DonHang
                await db.query('UPDATE DonHang SET TTThanhToan = ? WHERE MaDonHang = ?', [ 'Đã thanh toán', MaDonHang]);
                
                // Trả về thành công khi thanh toán hoàn tất
                resolve({ status: true, message: 'Thanh toán thành công'});
            }
            catch (error) {
                // Trả về lỗi nếu có vấn đề trong quá trình thanh toán
                reject({ status: false, error: error.message });
            }
        })
    }
}

// Xuất lớp OrderService để sử dụng trong các phần khác của ứng dụng
module.exports = new OrderService;