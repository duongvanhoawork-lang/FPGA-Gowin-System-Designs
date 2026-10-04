module top_console(
    input clk,       
    input rst_n,     
    input uart_rx,   
    output uart_tx,  
    output buzzer,
    output [3:0] led,
    input [1:0] btn,       // KEY0, KEY1
    input [3:0] gpio_btn,  // GPIO
    output i2c_sclk,       
    inout  i2c_sdat        
);

    // --- UART RX ---
    wire [7:0] rx_data;
    wire rx_valid;
    
    uart_rx #(.CLKS_PER_BIT(54)) u_rx (
        .clk(clk), 
        .rst_n(rst_n), 
        .rx(uart_rx), 
        .rx_data(rx_data), 
        .rx_valid(rx_valid)
    );
    
    // --- LỌC NHIỄU (DEBOUNCE) ---
    reg [15:0] db0_cnt, db1_cnt;
    reg btn0_state, btn1_state;
    reg btn0_pulse, btn1_pulse;

    always @(posedge clk) begin
        if(btn[0] == btn0_state) db0_cnt <= 0;
        else begin
            db0_cnt <= db0_cnt + 1;
            if(db0_cnt == 16'hFFFF) begin
                btn0_state <= btn[0];
                btn0_pulse <= ~btn[0];
            end else btn0_pulse <= 0;
        end
        
        if(btn[1] == btn1_state) db1_cnt <= 0;
        else begin
            db1_cnt <= db1_cnt + 1;
            if(db1_cnt == 16'hFFFF) begin
                btn1_state <= btn[1];
                btn1_pulse <= ~btn[1];
            end else btn1_pulse <= 0;
        end
    end
    
    reg [15:0] dg0_cnt, dg1_cnt, dg2_cnt, dg3_cnt;
    reg g0_state, g1_state, g2_state, g3_state;
    reg g0_pulse, g1_pulse, g2_pulse, g3_pulse;

    always @(posedge clk) begin
        if(gpio_btn[0] == g0_state) dg0_cnt <= 0;
        else begin
            dg0_cnt <= dg0_cnt + 1;
            if(dg0_cnt == 16'hFFFF) begin
                g0_state <= gpio_btn[0];
                g0_pulse <= ~gpio_btn[0];
            end else g0_pulse <= 0;
        end
        
        if(gpio_btn[1] == g1_state) dg1_cnt <= 0;
        else begin
            dg1_cnt <= dg1_cnt + 1;
            if(dg1_cnt == 16'hFFFF) begin
                g1_state <= gpio_btn[1];
                g1_pulse <= ~gpio_btn[1];
            end else g1_pulse <= 0;
        end
        
        if(gpio_btn[2] == g2_state) dg2_cnt <= 0;
        else begin
            dg2_cnt <= dg2_cnt + 1;
            if(dg2_cnt == 16'hFFFF) begin
                g2_state <= gpio_btn[2];
                g2_pulse <= ~gpio_btn[2];
            end else g2_pulse <= 0;
        end
        
        if(gpio_btn[3] == g3_state) dg3_cnt <= 0;
        else begin
            dg3_cnt <= dg3_cnt + 1;
            if(dg3_cnt == 16'hFFFF) begin
                g3_state <= gpio_btn[3];
                g3_pulse <= ~gpio_btn[3];
            end else g3_pulse <= 0;
        end
    end

    // --- UART GAME CONTROL LOGIC ---
    reg [7:0] rx_command;
    reg [3:0] rx_state;
    reg [7:0] rx_data_reg;
    
    reg uart_left_pulse, uart_right_pulse, uart_up_pulse, uart_down_pulse, uart_restart_pulse;
    
    // HARDCODE SNAKE GAME ID
    wire [7:0] game_id = 8'h01; 
    
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            uart_left_pulse <= 0;
            uart_right_pulse <= 0;
            uart_up_pulse <= 0;
            uart_down_pulse <= 0;
            uart_restart_pulse <= 0;
        end else begin
            uart_left_pulse <= 0;
            uart_right_pulse <= 0;
            uart_up_pulse <= 0;
            uart_down_pulse <= 0;
            uart_restart_pulse <= 0;
            
            if(rx_valid) begin
                if(rx_state == 0 && rx_data == 8'hBB) 
                    rx_state <= 1;
                else if(rx_state == 1) begin
                    if(rx_data == 8'hAA) begin
                        case(rx_command)
                            1, 7:         uart_left_pulse <= 1;
                            2, 8:         uart_right_pulse <= 1;
                            3, 9:         uart_up_pulse <= 1;
                            4, 10:        uart_down_pulse <= 1;
                            5, 6, 11, 12: uart_restart_pulse <= 1;
                        endcase
                    end
                    rx_state <= 0;
                end else 
                    rx_state <= 0;
                    
                rx_command <= rx_data_reg;
                rx_data_reg <= rx_data;
            end
        end
    end

    // --- INSTANTIATE SNAKE GAME ---
    wire snake_restart = uart_restart_pulse | btn0_pulse;
    
    wire [7:0] pixel_addr;
    wire [3:0] snake_pixel_color;
    wire [3:0] snake_score;
    wire [1:0] snake_game_state;
    wire [7:0] snake_peri_trigger;
    
    snake u_snake(
        .clk(clk),
        .rst_n(rst_n),
        .en(1'b1), // Always run Snake Game
        .key_left_pulse(g0_pulse | btn0_pulse | uart_left_pulse),
        .key_right_pulse(g1_pulse | btn1_pulse | uart_right_pulse),
        .key_up_pulse(g2_pulse | uart_up_pulse),
        .key_down_pulse(g3_pulse | uart_down_pulse),
        .restart_cmd(snake_restart),
        .pixel_addr(pixel_addr),
        .pixel_color(snake_pixel_color),
        .score(snake_score),
        .game_state(snake_game_state),
        .peri_trigger(snake_peri_trigger)
    );

    wire active_point_pulse = snake_peri_trigger[0];
    wire active_die_pulse   = snake_peri_trigger[1];
    wire active_win_pulse   = snake_peri_trigger[2];

    // --- OLED DISPLAY ---
    oled_controller u_oled(
        .clk(clk),
        .rst_n(rst_n),
        .game_id(game_id), // Always 01
        .score(snake_score),
        .game_state(snake_game_state),
        .i2c_sclk(i2c_sclk),
        .i2c_sdat(i2c_sdat)
    );

    // --- AUDIO & LED CONTROL (PERIPHERAL) ---
    peripheral_ctrl u_peri(
        .clk(clk),
        .rst_n(rst_n),
        .point_pulse(active_point_pulse),
        .die_pulse(active_die_pulse),
        .win_pulse(active_win_pulse),
        .buzzer(buzzer)
    );

    // --- UART TX TO PC ---
    wire tx_busy;
    reg [7:0] tx_data;
    reg tx_req;
    reg [2:0] tx_state;

    always @(posedge clk) begin
        if(!rst_n) begin
            tx_state <= 0;
            tx_req <= 0;
            tx_data <= 0;
        end else begin
            case(tx_state)
                0: begin
                    tx_req <= 0;
                    tx_state <= 1;
                end
                1: begin
                    if(!tx_busy) begin
                        tx_data <= 8'hCC; // Sync byte 1
                        tx_req <= 1;
                        tx_state <= 2;
                    end
                end
                2: begin
                    if(tx_busy) tx_req <= 0;
                    if(!tx_req && !tx_busy) begin
                        tx_data <= 8'hDD; // Sync byte 2
                        tx_req <= 1;
                        tx_state <= 3;
                    end
                end
                3: begin
                    if(tx_busy) tx_req <= 0;
                    if(!tx_req && !tx_busy) begin
                        tx_data <= game_id;
                        tx_req <= 1;
                        tx_state <= 4;
                    end
                end
                4: begin
                    if(tx_busy) tx_req <= 0;
                    if(!tx_req && !tx_busy) begin
                        tx_data <= snake_pixel_color;
                        tx_req <= 1;
                        tx_state <= 5;
                    end
                end
                5: begin
                    if(tx_busy) tx_req <= 0;
                    if(!tx_req && !tx_busy) begin
                        tx_data <= pixel_addr;
                        tx_req <= 1;
                        tx_state <= 0;
                    end
                end
            endcase
        end
    end

    uart_tx #(.CLKS_PER_BIT(54)) u_tx (
        .clk(clk),
        .rst_n(rst_n),
        .tx_req(tx_req),
        .tx_data(tx_data),
        .tx(uart_tx),
        .tx_busy(tx_busy)
    );

    assign led = ~snake_score; // Display score on LEDs
endmodule
