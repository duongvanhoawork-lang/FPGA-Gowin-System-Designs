`ifndef TETRIS_MODULE_DEFINED
`define TETRIS_MODULE_DEFINED

module tetris(
    input clk,
    input rst_n,
    input en,
    input [5:0] keys,
    input [7:0] pixel_addr,
    output reg [3:0] pixel_color,
    output reg [7:0] peri_trigger
);
    
    // Ma trận hiển thị 16x16 (nhưng Tetris chỉ chơi trong cột 3 đến 12)
    reg [3:0] board [0:255];
    
    // Bộ sinh số ngẫu nhiên cho khối gạch (LFSR)
    reg [7:0] lfsr;
    always @(posedge clk) if(!rst_n) lfsr <= 8'hA5; else lfsr <= {lfsr[6:0], lfsr[7]^lfsr[5]^lfsr[4]^lfsr[3]};
    
    // Khai báo toạ độ các viên gạch (Mã hoá 16 bit: dy3,dx3, dy2,dx2, dy1,dx1, dy0,dx0)
    function [15:0] get_base_shape;
        input [2:0] id;
        begin
            case(id)
                0: get_base_shape = 16'h7654; // I
                1: get_base_shape = 16'h9851; // J
                2: get_base_shape = 16'hA951; // L
                3: get_base_shape = 16'hA965; // O
                4: get_base_shape = 16'h9865; // S
                5: get_base_shape = 16'h6541; // T
                6: get_base_shape = 16'hA954; // Z
                default: get_base_shape = 16'h7654;
            endcase
        end
    endfunction
    
    // Chọn màu cho 7 loại gạch
    function [3:0] piece_color_func;
        input [2:0] id;
        begin
            case(id)
                0: piece_color_func = 8; // Cyan
                1: piece_color_func = 4; // Blue
                2: piece_color_func = 6; // Orange
                3: piece_color_func = 5; // Yellow
                4: piece_color_func = 3; // Green
                5: piece_color_func = 7; // Purple
                6: piece_color_func = 2; // Red
                default: piece_color_func = 8;
            endcase
        end
    endfunction
    
    // Tính toán xoay ma trận 4x4
    function [3:0] rotate_coord;
        input [1:0] x;
        input [1:0] y;
        input [1:0] r;
        begin
            case(r)
                0: rotate_coord = {y, x};
                1: rotate_coord = {x, 2'd3 - y};
                2: rotate_coord = {2'd3 - y, 2'd3 - x};
                3: rotate_coord = {2'd3 - x, y};
            endcase
        end
    endfunction
    
    reg [2:0] piece_id;
    reg [1:0] piece_rot;
    reg [4:0] piece_x;
    reg [4:0] piece_y;
    
    reg [4:0] test_x, test_y;
    reg [1:0] test_rot;
    
    wire [15:0] base_shape = get_base_shape(piece_id);
    wire [3:0] p_color = piece_color_func(piece_id);
    
    // --- Toạ độ tính toán va chạm ---
    wire [3:0] t_b0 = rotate_coord(base_shape[1:0], base_shape[3:2], test_rot);
    wire [3:0] t_b1 = rotate_coord(base_shape[5:4], base_shape[7:6], test_rot);
    wire [3:0] t_b2 = rotate_coord(base_shape[9:8], base_shape[11:10], test_rot);
    wire [3:0] t_b3 = rotate_coord(base_shape[13:12], base_shape[15:14], test_rot);
    
    wire [4:0] t_ax0 = test_x + t_b0[1:0]; wire [4:0] t_ay0 = test_y + t_b0[3:2];
    wire [4:0] t_ax1 = test_x + t_b1[1:0]; wire [4:0] t_ay1 = test_y + t_b1[3:2];
    wire [4:0] t_ax2 = test_x + t_b2[1:0]; wire [4:0] t_ay2 = test_y + t_b2[3:2];
    wire [4:0] t_ax3 = test_x + t_b3[1:0]; wire [4:0] t_ay3 = test_y + t_b3[3:2];
    
    wire t_hit0 = (t_ax0 < 3) || (t_ax0 > 12) || (t_ay0 > 15) || (board[{t_ay0[3:0], t_ax0[3:0]}] != 0);
    wire t_hit1 = (t_ax1 < 3) || (t_ax1 > 12) || (t_ay1 > 15) || (board[{t_ay1[3:0], t_ax1[3:0]}] != 0);
    wire t_hit2 = (t_ax2 < 3) || (t_ax2 > 12) || (t_ay2 > 15) || (board[{t_ay2[3:0], t_ax2[3:0]}] != 0);
    wire t_hit3 = (t_ax3 < 3) || (t_ax3 > 12) || (t_ay3 > 15) || (board[{t_ay3[3:0], t_ax3[3:0]}] != 0);
    wire test_collision = t_hit0 | t_hit1 | t_hit2 | t_hit3;
    
    // --- Toạ độ thực tế để Render ---
    wire [3:0] p_b0 = rotate_coord(base_shape[1:0], base_shape[3:2], piece_rot);
    wire [3:0] p_b1 = rotate_coord(base_shape[5:4], base_shape[7:6], piece_rot);
    wire [3:0] p_b2 = rotate_coord(base_shape[9:8], base_shape[11:10], piece_rot);
    wire [3:0] p_b3 = rotate_coord(base_shape[13:12], base_shape[15:14], piece_rot);
    
    wire [4:0] p_ax0 = piece_x + p_b0[1:0]; wire [4:0] p_ay0 = piece_y + p_b0[3:2];
    wire [4:0] p_ax1 = piece_x + p_b1[1:0]; wire [4:0] p_ay1 = piece_y + p_b1[3:2];
    wire [4:0] p_ax2 = piece_x + p_b2[1:0]; wire [4:0] p_ay2 = piece_y + p_b2[3:2];
    wire [4:0] p_ax3 = piece_x + p_b3[1:0]; wire [4:0] p_ay3 = piece_y + p_b3[3:2];
    
    reg [26:0] tick_cnt;
    wire tick = (tick_cnt >= 50000000); // 1.0Hz Free fall (1000ms)
    
    reg [6:0] state; // 7-bit to safely support state 81
    reg [3:0] check_y, move_y;
    integer i;
    
    // --- STATE MACHINE CHÍNH ---
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state <= 11; 
            peri_trigger <= 0;
            tick_cnt <= 0;
        end else if(en) begin
            peri_trigger <= 0;
            if(tick) tick_cnt <= 0; else tick_cnt <= tick_cnt + 1;
            
            case(state)
                11: begin // INITIAL CLEAR
                    for(i=0; i<256; i=i+1) board[i] <= 0;
                    state <= 1;
                end
                0: begin // IDLE
                    if(keys[2]) begin // Left
                        test_x <= piece_x - 1; test_y <= piece_y; test_rot <= piece_rot; state <= 3;
                    end else if(keys[3]) begin // Right
                        test_x <= piece_x + 1; test_y <= piece_y; test_rot <= piece_rot; state <= 4;
                    end else if(keys[0]) begin // Up (Xoay khối gạch)
                        test_x <= piece_x; test_y <= piece_y; test_rot <= piece_rot + 1; state <= 5;
                    end else if(keys[1] || tick) begin // Down / Fast drop hoặc rơi tự do
                        test_x <= piece_x; test_y <= piece_y + 1; test_rot <= piece_rot; state <= 6;
                    end
                end
                1: begin // SPAWN
                    piece_id <= (lfsr[2:0] < 7) ? lfsr[2:0] : (lfsr[2:0] - 1);
                    piece_x <= 6; piece_y <= 0; piece_rot <= 0;
                    test_x <= 6; test_y <= 0; test_rot <= 0;
                    state <= 2;
                end
                2: begin // CHECK SPAWN
                    if(test_collision) begin
                        state <= 9; // Thua game
                        peri_trigger[1] <= 1;
                    end else state <= 0;
                end
                3: begin // Xử lý Left
                    if(!test_collision) begin piece_x <= piece_x - 1; peri_trigger[0] <= 1; end
                    state <= 0;
                end
                4: begin // Xử lý Right
                    if(!test_collision) begin piece_x <= piece_x + 1; peri_trigger[0] <= 1; end
                    state <= 0;
                end
                5: begin // Xử lý Xoay
                    if(!test_collision) begin piece_rot <= piece_rot + 1; peri_trigger[0] <= 1; end
                    state <= 0;
                end
                6: begin // Xử lý Rơi
                    if(!test_collision) begin
                        piece_y <= piece_y + 1;
                        state <= 0;
                    end else begin // Va chạm -> Khóa gạch
                        test_x <= piece_x; test_y <= piece_y; test_rot <= piece_rot;
                        state <= 7;
                    end
                end
                7: begin // LOCK (Khóa gạch vào bàn chơi)
                    board[{t_ay0[3:0], t_ax0[3:0]}] <= p_color;
                    board[{t_ay1[3:0], t_ax1[3:0]}] <= p_color;
                    board[{t_ay2[3:0], t_ax2[3:0]}] <= p_color;
                    board[{t_ay3[3:0], t_ax3[3:0]}] <= p_color;
                    peri_trigger[0] <= 1;
                    state <= 8;
                    check_y <= 15;
                end
                8: begin // CHECK LINE
                    if(board[{check_y, 4'd3}] != 0 && board[{check_y, 4'd4}] != 0 && board[{check_y, 4'd5}] != 0 &&
                       board[{check_y, 4'd6}] != 0 && board[{check_y, 4'd7}] != 0 && board[{check_y, 4'd8}] != 0 &&
                       board[{check_y, 4'd9}] != 0 && board[{check_y, 4'd10}] != 0 && board[{check_y, 4'd11}] != 0 &&
                       board[{check_y, 4'd12}] != 0) begin
                        move_y <= check_y;
                        state <= 7'd81;
                        peri_trigger[2] <= 1; // Nháy LED khi ăn điểm
                    end else begin
                        if(check_y == 0) state <= 1; // Đã quét xong -> Spawn gạch mới
                        else check_y <= check_y - 1;
                    end
                end
                7'd81: begin // SHIFT DOWN (Kéo các dòng phía trên xuống)
                    if(move_y == 0) begin
                        board[{4'd0, 4'd3}] <= 0; board[{4'd0, 4'd4}] <= 0; board[{4'd0, 4'd5}] <= 0;
                        board[{4'd0, 4'd6}] <= 0; board[{4'd0, 4'd7}] <= 0; board[{4'd0, 4'd8}] <= 0;
                        board[{4'd0, 4'd9}] <= 0; board[{4'd0, 4'd10}] <= 0; board[{4'd0, 4'd11}] <= 0;
                        board[{4'd0, 4'd12}] <= 0;
                        state <= 8; // Kiểm tra lại chính dòng đó vì dòng trên vừa rớt xuống
                    end else begin
                        board[{move_y, 4'd3}] <= board[{move_y - 4'd1, 4'd3}];
                        board[{move_y, 4'd4}] <= board[{move_y - 4'd1, 4'd4}];
                        board[{move_y, 4'd5}] <= board[{move_y - 4'd1, 4'd5}];
                        board[{move_y, 4'd6}] <= board[{move_y - 4'd1, 4'd6}];
                        board[{move_y, 4'd7}] <= board[{move_y - 4'd1, 4'd7}];
                        board[{move_y, 4'd8}] <= board[{move_y - 4'd1, 4'd8}];
                        board[{move_y, 4'd9}] <= board[{move_y - 4'd1, 4'd9}];
                        board[{move_y, 4'd10}] <= board[{move_y - 4'd1, 4'd10}];
                        board[{move_y, 4'd11}] <= board[{move_y - 4'd1, 4'd11}];
                        board[{move_y, 4'd12}] <= board[{move_y - 4'd1, 4'd12}];
                        move_y <= move_y - 1;
                    end
                end
                9: begin // GAME OVER
                    if(keys[4]) begin // Bấm Enter để chơi lại
                        state <= 10;
                        check_y <= 0;
                    end
                end
                10: begin // Xoá bàn chơi khi Restart
                    board[{check_y, 4'd3}] <= 0; board[{check_y, 4'd4}] <= 0; board[{check_y, 4'd5}] <= 0;
                    board[{check_y, 4'd6}] <= 0; board[{check_y, 4'd7}] <= 0; board[{check_y, 4'd8}] <= 0;
                    board[{check_y, 4'd9}] <= 0; board[{check_y, 4'd10}] <= 0; board[{check_y, 4'd11}] <= 0;
                    board[{check_y, 4'd12}] <= 0;
                    if(check_y == 15) state <= 1;
                    else check_y <= check_y + 1;
                end
            endcase
        end
    end
    
    // --- Render Hình ảnh liên tục cho UART ---
    wire [3:0] px = pixel_addr[3:0];
    wire [3:0] py = pixel_addr[7:4];
    
    wire is_piece = (state != 11 && state != 9 && state != 10 && state != 7) && (
        (px == p_ax0[3:0] && py == p_ay0[3:0]) ||
        (px == p_ax1[3:0] && py == p_ay1[3:0]) ||
        (px == p_ax2[3:0] && py == p_ay2[3:0]) ||
        (px == p_ax3[3:0] && py == p_ay3[3:0])
    );
    
    always @(posedge clk) begin
        if(!en) pixel_color <= 0;
        else begin
            if(px < 3 || px > 12) pixel_color <= 11; // Vẽ 2 bờ tường xám
            else if(is_piece) pixel_color <= p_color; // Vẽ viên gạch đang rơi
            else pixel_color <= board[pixel_addr]; // Vẽ nền và gạch đã xếp
        end
    end

endmodule

`endif
