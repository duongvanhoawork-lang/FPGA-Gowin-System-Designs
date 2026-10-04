module Serial_7Segment_Driver (
    input wire i_Clk,
    input wire [3:0] i_Binary_Num,
    output reg o_DIO,
    output reg o_SCLK,
    output reg o_RCLK
);

    // ==========================================
    // KHU VỰC CẤU HÌNH PHẦN CỨNG (SỬA Ở ĐÂY ĐỂ FIX LỖI)
    // ==========================================
    // 1. Cấu hình mức logic chọn ô: 
    //    Nếu mạch dùng mức 1 để chọn ô -> Set thành 8'b0000_0001
    //    Nếu mạch dùng mức 0 để chọn ô -> Set thành 8'b1111_1110
    localparam DIGIT_SELECT_BYTE = 8'b0000_0001; 

    // 2. Cấu hình mức logic sáng LED (Segment):
    //    Nếu LED Anode chung (0 là sáng) -> Gán thẳng bảng mã
    //    Nếu LED Cathode chung (1 là sáng) -> Dùng phép đảo bit (~) ở dòng gán r_Shift_Reg
    // ==========================================

    reg [7:0]  r_Hex_Seg;
    reg [15:0] r_Shift_Reg = 16'hFFFF; 
    reg [4:0]  r_Bit_Index = 0;
    reg [7:0]  r_Clk_Div = 0;

    // Bảng mã 7 đoạn (Mặc định: 0 là sáng)
    always @(*) begin
        case (i_Binary_Num)
            4'h0: r_Hex_Seg = 8'b1100_0000;
            4'h1: r_Hex_Seg = 8'b1111_1001;
            4'h2: r_Hex_Seg = 8'b1010_0100;
            4'h3: r_Hex_Seg = 8'b1011_0000;
            4'h4: r_Hex_Seg = 8'b1001_1001;
            4'h5: r_Hex_Seg = 8'b1001_0010;
            4'h6: r_Hex_Seg = 8'b1000_0010;
            4'h7: r_Hex_Seg = 8'b1111_1000;
            4'h8: r_Hex_Seg = 8'b1000_0000;
            4'h9: r_Hex_Seg = 8'b1001_0000;
            default: r_Hex_Seg = 8'b1111_1111;
        endcase
    end

    // Logic điều khiển dịch 16 bit
    always @(posedge i_Clk) begin
        r_Clk_Div <= r_Clk_Div + 1;

        if (r_Clk_Div == 8'd0) begin
            if (r_Bit_Index < 16) begin
                o_SCLK <= 0;
                o_RCLK <= 0;
                o_DIO  <= r_Shift_Reg[15]; // Dịch bit MSB ra trước
                r_Bit_Index <= r_Bit_Index + 1;
            end 
            else if (r_Bit_Index == 16) begin
                // Đã dịch đủ 16 bit, bật RCLK để chốt hiển thị
                o_RCLK <= 1;   
                r_Bit_Index <= r_Bit_Index + 1;
            end 
            else begin
                o_RCLK <= 0;
                r_Bit_Index <= 0;
                
                // NẠP DỮ LIỆU VÀO THANH GHI:
                // Nếu bị rác chữ hoặc sai vị trí, hãy đảo vị trí của r_Hex_Seg và DIGIT_SELECT_BYTE
                r_Shift_Reg <= {r_Hex_Seg, DIGIT_SELECT_BYTE}; 
            end
        end 
        else if (r_Clk_Div == 8'd128) begin
            if (r_Bit_Index > 0 && r_Bit_Index <= 16) begin
                o_SCLK <= 1;
                // Dịch trái để chuẩn bị bit tiếp theo
                r_Shift_Reg <= {r_Shift_Reg[14:0], 1'b0};
            end
        end
    end

endmodule