module Simon_Game (
    input i_clk,           // 50MHz clock
    input i_rst_n,         // Reset nút bấm
    input [2:0] i_sw,      // 3 Switch tương ứng 3 LED
    output [2:0] o_led,    // 3 LED hiển thị mẫu
    output [6:0] o_hex     // LED 7 đoạn hiển thị điểm
);

    // --- Khai báo trạng thái FSM ---
    localparam IDLE         = 3'd0;
    localparam GEN_PATTERN  = 3'd1;
    localparam SHOW_PATTERN = 3'd2;
    localparam WAIT_PLAYER  = 3'd3;
    localparam CHECK_INPUT  = 3'd4;
    localparam FAIL         = 3'd5;
    localparam WIN          = 3'd6;

    reg [2:0] current_state, next_state;
    reg [1:0] pattern [0:6]; // Lưu chuỗi 7 bước, mỗi bước chọn 1 trong 3 LED
    reg [2:0] game_length;   // Độ dài hiện tại của chuỗi (1 đến 7)
    reg [2:0] step_counter;  // Đếm bước đang hiển thị hoặc đang nhập
    reg [3:0] score_code;    // Mã gửi đến LED 7 đoạn

    // --- Clock Divider cho hiển thị (1Hz) ---
    reg [25:0] clk_div;
    wire tick = (clk_div == 26'd25_000_000); // 0.5s chớp 1 lần
    always @(posedge i_clk) clk_div <= tick ? 0 : clk_div + 1;

    // --- Logic FSM ---
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) current_state <= IDLE;
        else current_state <= next_state;
    end

    // Lưu ý: Đây là mã giả lược để bạn nắm cấu trúc logic chuyển trạng thái
    always @(posedge i_clk) begin
        case (current_state)
            IDLE: begin
                game_length <= 1;
                score_code <= 0;
                if (i_sw != 0) next_state <= GEN_PATTERN;
            end

            GEN_PATTERN: begin
                // Tạo mẫu ngẫu nhiên (giả lập)
                pattern[0] <= 2'b00; pattern[1] <= 2'b01; pattern[2] <= 2'b10;
                pattern[3] <= 2'b00; pattern[4] <= 2'b10; pattern[5] <= 2'b01;
                pattern[6] <= 2'b11;
                next_state <= SHOW_PATTERN;
                step_counter <= 0;
            end

            SHOW_PATTERN: begin
                if (tick) begin
                    if (step_counter < game_length) step_counter <= step_counter + 1;
                    else begin
                        step_counter <= 0;
                        next_state <= WAIT_PLAYER;
                    end
                end
            end

            WAIT_PLAYER: begin
                if (i_sw != 0) next_state <= CHECK_INPUT;
            end

            CHECK_INPUT: begin
                // So sánh i_sw với pattern[step_counter]
                // Nếu đúng: 
                //    Nếu step_counter == game_length-1: 
                //        Nếu game_length == 7 -> WIN, ngược lại -> GEN_PATTERN và game_length++
                // Nếu sai: -> FAIL
            end

            FAIL: score_code <= 10; // Hiển thị 'F'
            WIN:  score_code <= 11; // Hiển thị 'A'
        endcase
    end

    // Kết nối module 7 đoạn
    seven_seg_decoder scoreboard (.i_data(score_code), .o_seg(o_hex));

endmodule