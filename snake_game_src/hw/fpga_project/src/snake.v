module snake(
    input clk,
    input rst_n,
    input en,
    input [1:0] keys,            // keys[0]: Rẽ Left (90° CCW), keys[1]: Rẽ Right (90° CW)
    input restart_cmd,           // Lệnh khởi động lại game
    input [7:0] pixel_addr,
    output reg [3:0] pixel_color,
    output reg [3:0] score,      // Score: 0 đến 10
    output reg [1:0] game_state, // 0: Đang chơi, 1: Game Over, 2: Win
    output reg [7:0] peri_trigger
);

    reg [3:0] grid_mem [0:255]; // Bộ nhớ màn hình 16x16 pixel (4-bit color)
    reg [7:0] snake_pos [0:255]; // Coordinates từng đốt của rắn
    reg [7:0] head_ptr;
    reg [7:0] tail_ptr;
    reg [7:0] apple_pos;
    reg [1:0] dir; // 0: Up, 1: Down, 2: Left, 3: Right
    
    // Tốc độ game ~5Hz (ở 50MHz: 10_000_000 chu kỳ = 0.2s mỗi bước)
    reg [23:0] tick_cnt;
    wire tick = (tick_cnt >= 10000000);
    
    // Bộ đếm thời gian hiển thị màn hình WIN (~2.5 giây ở 50MHz: 125,000,000 chu kỳ)
    reg [26:0] win_timer;
    
    // Bộ sinh số ngẫu nhiên cho vị trí táo
    reg [7:0] lfsr;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) 
            lfsr <= 8'hA5; 
        else 
            lfsr <= {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};
    end
    
    integer i;
    
    // 0: Initialization, 1: Đang chơi, 2: Game Over, 3: Win
    reg [1:0] state;
    
    // Ánh xạ trạng thái xuất ra ngoài
    always @(*) begin
        case(state)
            2'd2: game_state = 2'b01; // Game Over
            2'd3: game_state = 2'b10; // Win
            default: game_state = 2'b00; // Playing
        endcase
    end
    
    // --- HÀNG ĐỢI LỆNH RẼ (TURN QUEUE FIFO - ĐỘ SÂU 8) ---
    // 1: Rẽ Left (ngược chiều kim đồng hồ)
    // 2: Rẽ Right (thuận chiều kim đồng hồ)
    reg [1:0] fifo_mem [0:7];
    reg [2:0] wr_ptr;
    reg [2:0] rd_ptr;
    wire [2:0] fifo_count = wr_ptr - rd_ptr;
    
    reg [1:0] keys_prev;
    wire key_left_pulse  = keys[0] & ~keys_prev[0];
    wire key_right_pulse = keys[1] & ~keys_prev[1];
    
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state <= 0;
            score <= 0;
            peri_trigger <= 0;
            head_ptr <= 0;
            tail_ptr <= 0;
            tick_cnt <= 0;
            win_timer <= 0;
            dir <= 3; // Mặc định hướng sang Right
            apple_pos <= 8'h88;
            wr_ptr <= 0;
            rd_ptr <= 0;
            keys_prev <= 0;
        end else if(en) begin
            peri_trigger <= 0;
            keys_prev <= keys;
            
            // Nhận xung phím đưa vào hàng đợi FIFO khi đang chơi
            if(state == 1) begin
                if(key_left_pulse && fifo_count < 3'd7) begin
                    fifo_mem[wr_ptr] <= 2'd1; // 1 = Rẽ Left
                    wr_ptr <= wr_ptr + 1;
                end else if(key_right_pulse && fifo_count < 3'd7) begin
                    fifo_mem[wr_ptr] <= 2'd2; // 2 = Rẽ Right
                    wr_ptr <= wr_ptr + 1;
                end
            end
            
            if(state == 0) begin
                // Initialization Rắn (3 đốt ban đầu) và reset điểm số
                for(i=0; i<256; i=i+1) grid_mem[i] <= 0;
                grid_mem[8'h55] <= 3; snake_pos[2] <= 8'h55; // Đầu (Color xanh lá sáng)
                grid_mem[8'h54] <= 12; snake_pos[1] <= 8'h54; // Thân (Color xanh lục)
                grid_mem[8'h53] <= 12; snake_pos[0] <= 8'h53; // Đuôi
                grid_mem[apple_pos] <= 2; // Apple (Color đỏ)
                
                head_ptr <= 2;
                tail_ptr <= 0;
                dir <= 3; // Hướng ban đầu: Sang phải
                wr_ptr <= 0;
                rd_ptr <= 0;
                tick_cnt <= 0;
                win_timer <= 0;
                score <= 0; // Reset điểm về 0
                state <= 1;
            end
            else if(state == 1) begin
                if(tick) begin
                    tick_cnt <= 0;
                    
                    // Tính hướng mới và tọa độ bước đi tiếp theo
                    begin: move_logic
                        reg [1:0] next_dir;
                        reg [3:0] nx, ny;
                        reg [7:0] next_pos;
                        
                        next_dir = dir;
                        if(fifo_count > 0) begin
                            rd_ptr <= rd_ptr + 1;
                            if(fifo_mem[rd_ptr] == 2'd1) begin
                                // RẼ TRÁI (90° ngược chiều kim đồng hồ)
                                case(dir)
                                    2'd0: next_dir = 2'd2; // Up -> Left
                                    2'd2: next_dir = 2'd1; // Left -> Down
                                    2'd1: next_dir = 2'd3; // Down -> Right
                                    2'd3: next_dir = 2'd0; // Right -> Up
                                endcase
                            end else if(fifo_mem[rd_ptr] == 2'd2) begin
                                // RẼ PHẢI (90° thuận chiều kim đồng hồ)
                                case(dir)
                                    2'd0: next_dir = 2'd3; // Up -> Right
                                    2'd3: next_dir = 2'd1; // Right -> Down
                                    2'd1: next_dir = 2'd2; // Down -> Left
                                    2'd2: next_dir = 2'd0; // Left -> Up
                                endcase
                            end
                        end
                        dir <= next_dir;
                        
                        nx = snake_pos[head_ptr][3:0];
                        ny = snake_pos[head_ptr][7:4];
                        
                        case(next_dir)
                            2'd0: ny = ny - 1; // Up
                            2'd1: ny = ny + 1; // Down
                            2'd2: nx = nx - 1; // Left
                            2'd3: nx = nx + 1; // Right
                        endcase
                        
                        next_pos = {ny, nx};
                        
                        // CHỐNG TỰ SÁT: Nếu lệnh rẽ khiến đầu đâm ngược 180° vào đốt cổ ngay sau nó,
                        // bỏ qua lệnh rẽ này và giữ nguyên hướng đi thẳng an toàn!
                        if((head_ptr != tail_ptr) && (next_pos == snake_pos[head_ptr - 8'd1])) begin
                            next_dir = dir;
                            nx = snake_pos[head_ptr][3:0];
                            ny = snake_pos[head_ptr][7:4];
                            case(dir)
                                2'd0: ny = ny - 1;
                                2'd1: ny = ny + 1;
                                2'd2: nx = nx - 1;
                                2'd3: nx = nx + 1;
                            endcase
                            next_pos = {ny, nx};
                        end
                        
                        dir <= next_dir;
                        
                        // Kiểm tra va chạm thân (Game Over)
                        if(grid_mem[next_pos] == 12 || grid_mem[next_pos] == 3) begin
                            state <= 2; // Game Over
                            win_timer <= 0; // Đặt bộ đếm thời gian chờ
                            peri_trigger[1] <= 1; // Còi báo thua (bíp trầm dài)
                        end 
                        else if(next_pos == apple_pos) begin
                            // Ăn táo: Tăng điểm
                            grid_mem[next_pos] <= 3;
                            grid_mem[snake_pos[head_ptr]] <= 12;
                            head_ptr <= head_ptr + 1;
                            snake_pos[(head_ptr + 1) & 8'hFF] <= next_pos;
                            
                            // Tạo quả táo mới
                            apple_pos <= lfsr;
                            grid_mem[lfsr] <= 2;
                            
                            // KIỂM TRA ĐIỀU KIỆN CHIẾN THẮNG: ĐẠT 10 ĐIỂM
                            if(score >= 4'd9) begin
                                score <= 4'd10;
                                state <= 3; // Chuyển sang trạng thái WIN
                                win_timer <= 0; // Đặt bộ đếm thời gian chờ
                                peri_trigger[2] <= 1; // Audio & LED chiến thắng (Win)
                            end else begin
                                score <= score + 1;
                                peri_trigger[0] <= 1; // Còi bíp ăn điểm & nhấp nháy LED
                            end
                        end 
                        else begin
                            // Di chuyển bình thường
                            grid_mem[next_pos] <= 3;
                            grid_mem[snake_pos[head_ptr]] <= 12;
                            
                            grid_mem[snake_pos[tail_ptr]] <= 0; // Xóa đốt đuôi cũ
                            
                            head_ptr <= head_ptr + 1;
                            tail_ptr <= tail_ptr + 1;
                            snake_pos[(head_ptr + 1) & 8'hFF] <= next_pos;
                        end
                    end
                end else begin
                    tick_cnt <= tick_cnt + 1;
                end
            end
            else if(state == 2) begin
                // GAME OVER: Chờ ít nhất 1.5 giây để tránh bấm nhầm phím lúc đang hốt hoảng
                if(win_timer < 75000000) begin
                    win_timer <= win_timer + 1;
                end else if(key_left_pulse || key_right_pulse || restart_cmd) begin
                    state <= 0;
                end
            end
            else if(state == 3) begin
                // WIN: Chờ ít nhất 1.5 giây để ăn mừng
                // Sau đó ĐỢI người dùng bấm nút mới chơi tiếp (giống Game Over)
                if(win_timer < 75000000) begin
                    win_timer <= win_timer + 1;
                end else if(key_left_pulse || key_right_pulse || restart_cmd) begin
                    state <= 0;
                end
            end
        end
    end
    
    // Xuất màu pixel cho bộ quét UART
    always @(posedge clk) begin
        if(!en) 
            pixel_color <= 0;
        else 
            pixel_color <= grid_mem[pixel_addr];
    end

endmodule
