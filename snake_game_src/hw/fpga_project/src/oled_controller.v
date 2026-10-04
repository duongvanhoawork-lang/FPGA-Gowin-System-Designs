module oled_controller(
    input clk,                    // 50 MHz
    input rst_n,                  // Active Low
    input [7:0] game_id,          // 8'h01: Snake, 8'h02: Tetris
    input [3:0] score,            // Score 0 - 10
    input [1:0] game_state,       // 0: Playing, 1: Game Over, 2: Win
    input point_scored_pulse,     // Pulse on score (for OLED flash)
    output i2c_sclk,              // Pin R3
    inout  i2c_sdat               // Pin T3
);

    // =========================================================================
    // 1. I2C BUS CONTROL (OPEN-DRAIN FOR SDA, PUSH-PULL FOR SCL)
    // =========================================================================
    reg sclk_out;
    reg sdat_out; // 0: pull low, 1: float (pull-up to 3.3V)
    
    assign i2c_sclk = sclk_out;
    assign i2c_sdat = (sdat_out == 1'b0) ? 1'b0 : 1'bz;

    // Bộ tạo nhịp xung I2C ~100kHz chuẩn (500 chu kỳ @ 50MHz)
    // Each I2C bit has 4 phases, 125 cycles per phase @ 50MHz
    reg [6:0] phase_cnt;
    wire phase_tick = (phase_cnt == 7'd124);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) phase_cnt <= 7'd0;
        else if(phase_tick) phase_cnt <= 7'd0;
        else phase_cnt <= phase_cnt + 7'd1;
    end

    // =========================================================================
    // 2. I2C BYTE ENGINE
    // =========================================================================
    localparam OP_IDLE  = 2'd0;
    localparam OP_START = 2'd1;
    localparam OP_BYTE  = 2'd2;
    localparam OP_STOP  = 2'd3;

    reg [1:0] cur_op;
    reg [7:0] shift_reg;
    reg [3:0] bit_idx;
    reg [1:0] phase;
    reg i2c_busy;
    reg i2c_done;

    reg [7:0] tx_byte;
    reg i2c_start_req;
    reg i2c_byte_req;
    reg i2c_stop_req;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            sclk_out  <= 1'b1;
            sdat_out  <= 1'b1;
            cur_op    <= OP_IDLE;
            shift_reg <= 8'd0;
            bit_idx   <= 4'd0;
            phase     <= 2'd0;
            i2c_busy  <= 1'b0;
            i2c_done  <= 1'b0;
        end else begin
            i2c_done <= 1'b0;
            
            if(!i2c_busy) begin
                if(i2c_start_req) begin
                    i2c_busy <= 1'b1;
                    cur_op   <= OP_START;
                    phase    <= 2'd0;
                end else if(i2c_byte_req) begin
                    i2c_busy  <= 1'b1;
                    cur_op    <= OP_BYTE;
                    phase     <= 2'd0;
                    bit_idx   <= 4'd8; // 8 bit dữ liệu + 1 bit ACK
                    shift_reg <= tx_byte; // Chốt byte cần gửi ngay lập tức
                end else if(i2c_stop_req) begin
                    i2c_busy <= 1'b1;
                    cur_op   <= OP_STOP;
                    phase    <= 2'd0;
                end
            end else if(phase_tick) begin
                phase <= phase + 2'd1;
                
                case(cur_op)
                    // --- ĐIỀU KIỆN START: SDA xuống trước khi SCL cao ---
                    OP_START: begin
                        case(phase)
                            2'd0: begin sdat_out <= 1'b1; sclk_out <= 1'b1; end
                            2'd1: begin sdat_out <= 1'b0; sclk_out <= 1'b1; end // START!
                            2'd2: begin sdat_out <= 1'b0; sclk_out <= 1'b1; end
                            2'd3: begin 
                                sdat_out <= 1'b0; 
                                sclk_out <= 1'b0; 
                                i2c_busy <= 1'b0; 
                                i2c_done <= 1'b1; 
                                cur_op   <= OP_IDLE;
                            end
                        endcase
                    end

                    // --- TRUYỀN 1 BYTE DỮ LIỆU + 1 BIT ACK ---
                    OP_BYTE: begin
                        case(phase)
                            2'd0: begin
                                sclk_out <= 1'b0;
                                if(bit_idx > 4'd0) begin
                                    sdat_out  <= shift_reg[7];
                                    shift_reg <= {shift_reg[6:0], 1'b0};
                                end else begin
                                    sdat_out <= 1'b1; // Thả nổi SDA để nhận ACK từ OLED
                                end
                            end
                            2'd1: begin
                                sclk_out <= 1'b1;
                            end
                            2'd2: begin
                                sclk_out <= 1'b1;
                            end
                            2'd3: begin
                                sclk_out <= 1'b0;
                                if(bit_idx > 4'd0) begin
                                    bit_idx <= bit_idx - 4'd1;
                                end else begin
                                    i2c_busy <= 1'b0;
                                    i2c_done <= 1'b1;
                                    cur_op   <= OP_IDLE;
                                end
                            end
                        endcase
                    end

                    // --- STOP CONDITION: SCL goes high then SDA goes high ---
                    OP_STOP: begin
                        case(phase)
                            2'd0: begin sdat_out <= 1'b0; sclk_out <= 1'b0; end
                            2'd1: begin sdat_out <= 1'b0; sclk_out <= 1'b1; end
                            2'd2: begin sdat_out <= 1'b1; sclk_out <= 1'b1; end // STOP!
                            2'd3: begin 
                                sdat_out <= 1'b1; 
                                sclk_out <= 1'b1; 
                                i2c_busy <= 1'b0; 
                                i2c_done <= 1'b1; 
                                cur_op   <= OP_IDLE;
                            end
                        endcase
                    end

                    default: begin
                        i2c_busy <= 1'b0;
                        cur_op   <= OP_IDLE;
                    end
                endcase
            end
        end
    end

    // =========================================================================
    // 3. ROM FONT CHỮ 8x8 (RỘNG 5 PIXEL + 3 PIXEL KHOẢNG TRẮNG = 8 PIXEL)
    // =========================================================================
    function [7:0] get_font_byte;
        input [7:0] ascii;
        input [2:0] col;
        begin
            case(ascii)
                "0": case(col) 0: get_font_byte=8'h3E; 1: get_font_byte=8'h51; 2: get_font_byte=8'h49; 3: get_font_byte=8'h45; 4: get_font_byte=8'h3E; default: get_font_byte=8'h00; endcase
                "1": case(col) 0: get_font_byte=8'h00; 1: get_font_byte=8'h42; 2: get_font_byte=8'h7F; 3: get_font_byte=8'h40; default: get_font_byte=8'h00; endcase
                "2": case(col) 0: get_font_byte=8'h42; 1: get_font_byte=8'h61; 2: get_font_byte=8'h51; 3: get_font_byte=8'h49; 4: get_font_byte=8'h46; default: get_font_byte=8'h00; endcase
                "3": case(col) 0: get_font_byte=8'h21; 1: get_font_byte=8'h41; 2: get_font_byte=8'h45; 3: get_font_byte=8'h4B; 4: get_font_byte=8'h31; default: get_font_byte=8'h00; endcase
                "4": case(col) 0: get_font_byte=8'h18; 1: get_font_byte=8'h14; 2: get_font_byte=8'h12; 3: get_font_byte=8'h7F; 4: get_font_byte=8'h10; default: get_font_byte=8'h00; endcase
                "5": case(col) 0: get_font_byte=8'h27; 1: get_font_byte=8'h45; 2: get_font_byte=8'h45; 3: get_font_byte=8'h45; 4: get_font_byte=8'h39; default: get_font_byte=8'h00; endcase
                "6": case(col) 0: get_font_byte=8'h3C; 1: get_font_byte=8'h4A; 2: get_font_byte=8'h49; 3: get_font_byte=8'h49; 4: get_font_byte=8'h30; default: get_font_byte=8'h00; endcase
                "7": case(col) 0: get_font_byte=8'h01; 1: get_font_byte=8'h71; 2: get_font_byte=8'h09; 3: get_font_byte=8'h05; 4: get_font_byte=8'h03; default: get_font_byte=8'h00; endcase
                "8": case(col) 0: get_font_byte=8'h36; 1: get_font_byte=8'h49; 2: get_font_byte=8'h49; 3: get_font_byte=8'h49; 4: get_font_byte=8'h36; default: get_font_byte=8'h00; endcase
                "9": case(col) 0: get_font_byte=8'h06; 1: get_font_byte=8'h49; 2: get_font_byte=8'h49; 3: get_font_byte=8'h29; 4: get_font_byte=8'h1E; default: get_font_byte=8'h00; endcase
                "A": case(col) 0: get_font_byte=8'h7C; 1: get_font_byte=8'h12; 2: get_font_byte=8'h11; 3: get_font_byte=8'h12; 4: get_font_byte=8'h7C; default: get_font_byte=8'h00; endcase
                "B": case(col) 0: get_font_byte=8'h7F; 1: get_font_byte=8'h49; 2: get_font_byte=8'h49; 3: get_font_byte=8'h49; 4: get_font_byte=8'h36; default: get_font_byte=8'h00; endcase
                "C": case(col) 0: get_font_byte=8'h3E; 1: get_font_byte=8'h41; 2: get_font_byte=8'h41; 3: get_font_byte=8'h41; 4: get_font_byte=8'h22; default: get_font_byte=8'h00; endcase
                "D": case(col) 0: get_font_byte=8'h7F; 1: get_font_byte=8'h41; 2: get_font_byte=8'h41; 3: get_font_byte=8'h22; 4: get_font_byte=8'h1C; default: get_font_byte=8'h00; endcase
                "E": case(col) 0: get_font_byte=8'h7F; 1: get_font_byte=8'h49; 2: get_font_byte=8'h49; 3: get_font_byte=8'h49; 4: get_font_byte=8'h41; default: get_font_byte=8'h00; endcase
                "F": case(col) 0: get_font_byte=8'h7F; 1: get_font_byte=8'h09; 2: get_font_byte=8'h09; 3: get_font_byte=8'h09; 4: get_font_byte=8'h01; default: get_font_byte=8'h00; endcase
                "G": case(col) 0: get_font_byte=8'h3E; 1: get_font_byte=8'h41; 2: get_font_byte=8'h49; 3: get_font_byte=8'h49; 4: get_font_byte=8'h7A; default: get_font_byte=8'h00; endcase
                "I": case(col) 0: get_font_byte=8'h00; 1: get_font_byte=8'h41; 2: get_font_byte=8'h7F; 3: get_font_byte=8'h41; default: get_font_byte=8'h00; endcase
                "K": case(col) 0: get_font_byte=8'h7F; 1: get_font_byte=8'h08; 2: get_font_byte=8'h14; 3: get_font_byte=8'h22; 4: get_font_byte=8'h41; default: get_font_byte=8'h00; endcase
                "M": case(col) 0: get_font_byte=8'h7F; 1: get_font_byte=8'h02; 2: get_font_byte=8'h0C; 3: get_font_byte=8'h02; 4: get_font_byte=8'h7F; default: get_font_byte=8'h00; endcase
                "N": case(col) 0: get_font_byte=8'h7F; 1: get_font_byte=8'h04; 2: get_font_byte=8'h08; 3: get_font_byte=8'h10; 4: get_font_byte=8'h7F; default: get_font_byte=8'h00; endcase
                "O": case(col) 0: get_font_byte=8'h3E; 1: get_font_byte=8'h41; 2: get_font_byte=8'h41; 3: get_font_byte=8'h41; 4: get_font_byte=8'h3E; default: get_font_byte=8'h00; endcase
                "P": case(col) 0: get_font_byte=8'h7F; 1: get_font_byte=8'h09; 2: get_font_byte=8'h09; 3: get_font_byte=8'h09; 4: get_font_byte=8'h06; default: get_font_byte=8'h00; endcase
                "R": case(col) 0: get_font_byte=8'h7F; 1: get_font_byte=8'h09; 2: get_font_byte=8'h19; 3: get_font_byte=8'h29; 4: get_font_byte=8'h46; default: get_font_byte=8'h00; endcase
                "S": case(col) 0: get_font_byte=8'h46; 1: get_font_byte=8'h49; 2: get_font_byte=8'h49; 3: get_font_byte=8'h49; 4: get_font_byte=8'h31; default: get_font_byte=8'h00; endcase
                "T": case(col) 0: get_font_byte=8'h01; 1: get_font_byte=8'h01; 2: get_font_byte=8'h7F; 3: get_font_byte=8'h01; 4: get_font_byte=8'h01; default: get_font_byte=8'h00; endcase
                "U": case(col) 0: get_font_byte=8'h3F; 1: get_font_byte=8'h40; 2: get_font_byte=8'h40; 3: get_font_byte=8'h40; 4: get_font_byte=8'h3F; default: get_font_byte=8'h00; endcase
                "V": case(col) 0: get_font_byte=8'h1F; 1: get_font_byte=8'h20; 2: get_font_byte=8'h40; 3: get_font_byte=8'h20; 4: get_font_byte=8'h1F; default: get_font_byte=8'h00; endcase
                "W": case(col) 0: get_font_byte=8'h7F; 1: get_font_byte=8'h20; 2: get_font_byte=8'h18; 3: get_font_byte=8'h20; 4: get_font_byte=8'h7F; default: get_font_byte=8'h00; endcase
                "Y": case(col) 0: get_font_byte=8'h07; 1: get_font_byte=8'h08; 2: get_font_byte=8'h70; 3: get_font_byte=8'h08; 4: get_font_byte=8'h07; default: get_font_byte=8'h00; endcase
                ":": case(col) 0: get_font_byte=8'h00; 1: get_font_byte=8'h36; 2: get_font_byte=8'h36; default: get_font_byte=8'h00; endcase
                "/": case(col) 0: get_font_byte=8'h20; 1: get_font_byte=8'h10; 2: get_font_byte=8'h08; 3: get_font_byte=8'h04; 4: get_font_byte=8'h02; default: get_font_byte=8'h00; endcase
                "!": case(col) 0: get_font_byte=8'h00; 1: get_font_byte=8'h7D; default: get_font_byte=8'h00; endcase
                "*": case(col) 0: get_font_byte=8'h2A; 1: get_font_byte=8'h1C; 2: get_font_byte=8'h7F; 3: get_font_byte=8'h1C; 4: get_font_byte=8'h2A; default: get_font_byte=8'h00; endcase
                "-": case(col) 0: get_font_byte=8'h08; 1: get_font_byte=8'h08; 2: get_font_byte=8'h08; 3: get_font_byte=8'h08; default: get_font_byte=8'h00; endcase
                "<": case(col) 0: get_font_byte=8'h08; 1: get_font_byte=8'h14; 2: get_font_byte=8'h22; 3: get_font_byte=8'h41; default: get_font_byte=8'h00; endcase
                ">": case(col) 0: get_font_byte=8'h41; 1: get_font_byte=8'h22; 2: get_font_byte=8'h14; 3: get_font_byte=8'h08; default: get_font_byte=8'h00; endcase
                "[": case(col) 0: get_font_byte=8'h7F; 1: get_font_byte=8'h41; default: get_font_byte=8'h00; endcase
                "]": case(col) 0: get_font_byte=8'h41; 1: get_font_byte=8'h7F; default: get_font_byte=8'h00; endcase
                "=": case(col) 0: get_font_byte=8'h14; 1: get_font_byte=8'h14; 2: get_font_byte=8'h14; 3: get_font_byte=8'h14; default: get_font_byte=8'h00; endcase
                default: get_font_byte = 8'h00;
            endcase
        end
    endfunction

    // =========================================================================
    // 4. CHARACTER GENERATOR (16 CHARACTERS PER PAGE)
    // =========================================================================


    // -------------------------------------------------------------------------
    // STATIC TEST TO PROVE COMPILER IS NOT BROKEN
    // -------------------------------------------------------------------------
    function [7:0] get_char;
        input [2:0] page;
        input [3:0] char_pos;
        begin
            get_char = "X";
        end
    endfunction
    function [7:0] get_init_cmd;
        input [4:0] idx;
        begin
            case(idx)
                5'd0:  get_init_cmd = 8'hAE; // Turn off display
                5'd1:  get_init_cmd = 8'hD5; // Tần số dao động clock
                5'd2:  get_init_cmd = 8'h80;
                5'd3:  get_init_cmd = 8'hA8; // Multiplex Ratio (64 rows)
                5'd4:  get_init_cmd = 8'h3F;
                5'd5:  get_init_cmd = 8'hD3; // Độ dời hiển thị
                5'd6:  get_init_cmd = 8'h00;
                5'd7:  get_init_cmd = 8'h40; // Start line (Line 0)
                5'd8:  get_init_cmd = 8'h8D; // ENABLE CHARGE PUMP (CRITICAL)
                5'd9:  get_init_cmd = 8'h14; // TURN ON 7.5V PUMP FOR 0.96 INCH DISPLAY
                5'd10: get_init_cmd = 8'h20; // Chế độ định địa chỉ
                5'd11: get_init_cmd = 8'h02; // Chế độ Page Addressing
                5'd12: get_init_cmd = 8'hA1; // Segment remap (left to right)
                5'd13: get_init_cmd = 8'hC8; // COM output scan direction (top to bottom)
                5'd14: get_init_cmd = 8'hDA; // COM hardware configuration
                5'd15: get_init_cmd = 8'h12;
                5'd16: get_init_cmd = 8'h81; // Contrast control
                5'd17: get_init_cmd = 8'hCF; // High brightness
                5'd18: get_init_cmd = 8'hD9; // Chu kỳ nạp trước (Pre-charge)
                5'd19: get_init_cmd = 8'hF1;
                5'd20: get_init_cmd = 8'hDB; // VCOMH deselect level
                5'd21: get_init_cmd = 8'h40;
                5'd22: get_init_cmd = 8'hA4; // Bật hiển thị theo bộ nhớ RAM
                5'd23: get_init_cmd = 8'hA6; // Normal Display mode
                5'd24: get_init_cmd = 8'hAF; // TURN ON DISPLAY
                default: get_init_cmd = 8'hAF;
            endcase
        end
    endfunction

    // =========================================================================
    // 6. MAIN CONTROLLER FSM
    // =========================================================================
    localparam S_POR            = 5'd0;
    localparam S_INIT_START     = 5'd1;
    localparam S_INIT_ADDR      = 5'd2;
    localparam S_INIT_CTRL      = 5'd3;
    localparam S_INIT_CMD       = 5'd4;
    localparam S_INIT_WAIT_STOP = 5'd5;
    localparam S_CHECK_FLASH    = 5'd6;
    localparam S_FLASH_START    = 5'd7;
    localparam S_FLASH_ADDR     = 5'd8;
    localparam S_FLASH_CTRL     = 5'd9;
    localparam S_FLASH_CMD      = 5'd10;
    localparam S_FLASH_WAIT_CMD = 5'd11;
    localparam S_FLASH_WAIT_STOP= 5'd12;
    localparam S_PAGE_START     = 5'd13;
    localparam S_PAGE_ADDR      = 5'd14;
    localparam S_PAGE_CTRL      = 5'd15;
    localparam S_PAGE_CMD1      = 5'd16;
    localparam S_PAGE_CMD2      = 5'd17;
    localparam S_PAGE_CMD3      = 5'd18;
    localparam S_PAGE_WAIT_CMD3 = 5'd19;
    localparam S_PAGE_WAIT_STOP = 5'd20;
    localparam S_DATA_START     = 5'd21;
    localparam S_DATA_ADDR      = 5'd22;
    localparam S_DATA_CTRL      = 5'd23;
    localparam S_DATA_WAIT_CTRL = 5'd24;
    localparam S_DATA_BYTE      = 5'd25;
    localparam S_DATA_WAIT_STOP = 5'd26;
    localparam S_DATA_BYTE_MAP  = 5'd27;
    reg [7:0] current_char_reg;

    reg [4:0] state;
    reg [22:0] por_timer; // Wait 100ms after power-on for stability
    reg [4:0] init_idx;
    reg [2:0] cur_page;
    reg [7:0] cur_col; // 0 đến 128

    // Manage screen flash when eating apple
    reg [23:0] flash_timer;
    reg is_flashing;
    reg flash_pending;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state         <= S_POR;
            por_timer     <= 23'd0;
            init_idx      <= 5'd0;
            cur_page      <= 3'd0;
            cur_col       <= 8'd0;
            tx_byte       <= 8'd0;
            i2c_start_req <= 1'b0;
            i2c_byte_req  <= 1'b0;
            i2c_stop_req  <= 1'b0;
            flash_timer   <= 24'd0;
            is_flashing   <= 1'b0;
            flash_pending <= 1'b0;
        end else begin
            // Default single clock pulse for requests
            i2c_start_req <= 1'b0;
            i2c_byte_req  <= 1'b0;
            i2c_stop_req  <= 1'b0;

            // Handle color inversion flash counter when eating apple
            if(point_scored_pulse) begin
                flash_timer   <= 24'd7500000; // ~150ms @ 50MHz
                is_flashing   <= 1'b1;
                flash_pending <= 1'b1;
            end else if(is_flashing) begin
                if(flash_timer > 24'd0) begin
                    flash_timer <= flash_timer - 24'd1;
                end else begin
                    is_flashing   <= 1'b0;
                    flash_pending <= 1'b1; // Flash done, return to normal display
                end
            end

            case(state)
                // 0: Chờ 100ms sau khi cấp nguồn (5,000,000 chu kỳ @ 50MHz)
                S_POR: begin
                    if(por_timer >= 23'd5000000) begin
                        state <= S_INIT_START;
                    end else begin
                        por_timer <= por_timer + 23'd1;
                    end
                end

                // --- 1..5: SEND ALL 25 INIT COMMANDS IN 1 I2C FRAME ---
                S_INIT_START: begin
                    if(!i2c_busy) begin
                        i2c_start_req <= 1'b1;
                        state         <= S_INIT_ADDR;
                    end
                end

                S_INIT_ADDR: begin
                    if(i2c_done) begin
                        tx_byte      <= 8'h78; // Địa chỉ I2C của OLED (0x3C << 1)
                        i2c_byte_req <= 1'b1;
                        state        <= S_INIT_CTRL;
                    end
                end

                S_INIT_CTRL: begin
                    if(i2c_done) begin
                        tx_byte      <= 8'h00; // Control Byte: Co=0, D/C#=0 (Chuỗi lệnh command)
                        i2c_byte_req <= 1'b1;
                        init_idx     <= 5'd0;
                        state        <= S_INIT_CMD;
                    end
                end

                S_INIT_CMD: begin
                    if(i2c_done) begin
                        if(init_idx < 5'd25) begin
                            tx_byte      <= get_init_cmd(init_idx);
                            i2c_byte_req <= 1'b1;
                            init_idx     <= init_idx + 5'd1;
                        end else begin
                            i2c_stop_req <= 1'b1;
                            state        <= S_INIT_WAIT_STOP;
                        end
                    end
                end

                S_INIT_WAIT_STOP: begin
                    if(i2c_done) begin
                        cur_page <= 3'd0;
                        state    <= S_PAGE_START;
                    end
                end

                // --- 6: CHECK FLASH EFFECT OR SCAN NEXT PAGE ---
                S_CHECK_FLASH: begin
                    if(flash_pending) begin
                        flash_pending <= 1'b0;
                        i2c_start_req <= 1'b1;
                        state         <= S_FLASH_ADDR;
                    end else begin
                        i2c_start_req <= 1'b1;
                        state         <= S_PAGE_ADDR;
                    end
                end

                // --- 7..12: SEND INVERT (0xA7) OR NORMAL (0xA6) COMMAND ---
                S_FLASH_START: begin
                    if(!i2c_busy) begin
                        i2c_start_req <= 1'b1;
                        state         <= S_FLASH_ADDR;
                    end
                end

                S_FLASH_ADDR: begin
                    if(i2c_done) begin
                        tx_byte      <= 8'h78;
                        i2c_byte_req <= 1'b1;
                        state        <= S_FLASH_CTRL;
                    end
                end

                S_FLASH_CTRL: begin
                    if(i2c_done) begin
                        tx_byte      <= 8'h00;
                        i2c_byte_req <= 1'b1;
                        state        <= S_FLASH_CMD;
                    end
                end

                S_FLASH_CMD: begin
                    if(i2c_done) begin
                        tx_byte      <= is_flashing ? 8'hA7 : 8'hA6;
                        i2c_byte_req <= 1'b1;
                        state        <= S_FLASH_WAIT_CMD;
                    end
                end

                S_FLASH_WAIT_CMD: begin
                    if(i2c_done) begin
                        i2c_stop_req <= 1'b1;
                        state        <= S_FLASH_WAIT_STOP;
                    end
                end

                S_FLASH_WAIT_STOP: begin
                    if(i2c_done) begin
                        i2c_start_req <= 1'b1;
                        state         <= S_PAGE_ADDR;
                    end
                end

                // --- 13..20: SET PAGE AND COLUMN ADDRESS ---
                S_PAGE_START: begin
                    if(!i2c_busy) begin
                        i2c_start_req <= 1'b1;
                        state         <= S_PAGE_ADDR;
                    end
                end

                S_PAGE_ADDR: begin
                    if(i2c_done) begin
                        tx_byte      <= 8'h78;
                        i2c_byte_req <= 1'b1;
                        state        <= S_PAGE_CTRL;
                    end
                end

                S_PAGE_CTRL: begin
                    if(i2c_done) begin
                        tx_byte      <= 8'h00; // Command stream
                        i2c_byte_req <= 1'b1;
                        state        <= S_PAGE_CMD1;
                    end
                end

                S_PAGE_CMD1: begin
                    if(i2c_done) begin
                        tx_byte      <= {5'b10110, cur_page}; // 0xB0 | cur_page
                        i2c_byte_req <= 1'b1;
                        state        <= S_PAGE_CMD2;
                    end
                end

                S_PAGE_CMD2: begin
                    if(i2c_done) begin
                        tx_byte      <= 8'h00; // Lower column address = 0
                        i2c_byte_req <= 1'b1;
                        state        <= S_PAGE_CMD3;
                    end
                end

                S_PAGE_CMD3: begin
                    if(i2c_done) begin
                        tx_byte      <= 8'h10; // Higher column address = 0
                        i2c_byte_req <= 1'b1;
                        state        <= S_PAGE_WAIT_CMD3;
                    end
                end

                S_PAGE_WAIT_CMD3: begin
                    if(i2c_done) begin
                        i2c_stop_req <= 1'b1;
                        state        <= S_PAGE_WAIT_STOP;
                    end
                end

                S_PAGE_WAIT_STOP: begin
                    if(i2c_done) begin
                        i2c_start_req <= 1'b1; // New START for Data transmission!
                        state         <= S_DATA_ADDR;
                    end
                end

                // --- 21..26: WRITE 128 BYTES PIXEL DATA FOR CURRENT PAGE ---
                S_DATA_START: begin
                    if(!i2c_busy) begin
                        i2c_start_req <= 1'b1;
                        state         <= S_DATA_ADDR;
                    end
                end

                S_DATA_ADDR: begin
                    if(i2c_done) begin
                        tx_byte      <= 8'h78;
                        i2c_byte_req <= 1'b1;
                        state        <= S_DATA_CTRL;
                    end
                end

                S_DATA_CTRL: begin
                    if(i2c_done) begin
                        tx_byte      <= 8'h40; // Control Byte: Co=0, D/C#=1 (Data stream)
                        i2c_byte_req <= 1'b1;
                        state        <= S_DATA_WAIT_CTRL;
                    end
                end

                S_DATA_WAIT_CTRL: begin
                    if(i2c_done) begin
                        if(cur_page == 3'd1 || cur_page == 3'd3 || cur_page == 3'd5 || cur_page == 3'd7) begin
                            tx_byte <= get_font_byte(get_char(cur_page, cur_col[6:3]), cur_col[2:0]);
                        end else begin
                            tx_byte <= 8'h00;
                        end
                        i2c_byte_req <= 1'b1;
                        cur_col      <= cur_col + 8'd1;
                        state        <= S_DATA_BYTE;
                    end
                end

                S_DATA_BYTE: begin
                    if(i2c_done) begin
                        if(cur_col < 8'd128) begin
                            if(cur_page == 3'd1 || cur_page == 3'd3 || cur_page == 3'd5 || cur_page == 3'd7) begin
                                tx_byte <= get_font_byte(get_char(cur_page, cur_col[6:3]), cur_col[2:0]);
                            end else begin
                                tx_byte <= 8'h00;
                            end
                            i2c_byte_req <= 1'b1;
                            cur_col      <= cur_col + 8'd1;
                        end else begin
                            i2c_stop_req <= 1'b1;
                            state        <= S_DATA_WAIT_STOP;
                        end
                    end
                end

                S_DATA_WAIT_STOP: begin
                    if(i2c_done) begin
                        cur_col <= 8'd0;
                        if(cur_page >= 3'd7) begin
                            cur_page <= 3'd0; 
                        end else begin
                            cur_page <= cur_page + 3'd1;
                        end
                        state <= S_CHECK_FLASH;
                    end
                end

                default: state <= S_POR;
            endcase
        end
    end

endmodule












