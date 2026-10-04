module memory_game(
    input clk,
    input rst_n,
    input en,
    
    input key_left_pulse,
    input key_right_pulse,
    input key_rot_pulse,
    input key_drop_pulse,
    input restart_cmd,
    
    input [7:0] pixel_addr,
    output reg [3:0] pixel_color,
    output reg [3:0] score,
    output reg [1:0] game_state,
    output reg [7:0] peri_trigger
);

    // Box mapping (0 to 3)
    // 0: UP (Rot)
    // 1: RIGHT (Right)
    // 2: DOWN (Drop)
    // 3: LEFT (Left)
    
    wire [3:0] px = pixel_addr[3:0];
    wire [3:0] py = pixel_addr[7:4];
    
    wire box_up = (px >= 6 && px <= 9) && (py >= 2 && py <= 5);
    wire box_right = (px >= 10 && px <= 13) && (py >= 6 && py <= 9);
    wire box_down = (px >= 6 && px <= 9) && (py >= 10 && py <= 13);
    wire box_left = (px >= 2 && px <= 5) && (py >= 6 && py <= 9);
    
    wire rb_up = box_up && (px == 7 || px == 8 || py == 3 || py == 4);
    wire rb_right = box_right && (px == 11 || px == 12 || py == 7 || py == 8);
    wire rb_down = box_down && (px == 7 || px == 8 || py == 11 || py == 12);
    wire rb_left = box_left && (px == 3 || px == 4 || py == 7 || py == 8);
    
    reg [2:0] state;
    reg [1:0] seq_mem [0:15];
    reg [15:0] lfsr;
    
    reg [3:0] show_idx;
    reg [3:0] input_idx;
    reg [3:0] gen_idx;
    
    reg [24:0] timer; 
    reg [1:0] current_lit_box;
    reg box_is_lit;
    
    wire any_key = key_left_pulse | key_right_pulse | key_rot_pulse | key_drop_pulse | restart_cmd;
    reg [1:0] user_key_val;
    always @(*) begin
        if (key_rot_pulse) user_key_val = 2'd0;
        else if (key_right_pulse) user_key_val = 2'd1;
        else if (key_drop_pulse) user_key_val = 2'd2;
        else user_key_val = 2'd3;
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            lfsr <= 16'hACE1;
        else if (en)
            lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= 0;
            score <= 0;
            show_idx <= 0;
            input_idx <= 0;
            gen_idx <= 0;
            timer <= 0;
            box_is_lit <= 0;
            peri_trigger <= 0;
        end else if (en) begin
            peri_trigger <= 0; // Xung mặc định bằng 0
            
            case(state)
                0: begin // INIT: Generate sequence for this turn
                    seq_mem[gen_idx] <= lfsr[1:0];
                    gen_idx <= gen_idx + 1;
                    if (gen_idx == 4'd15) begin
                        state <= 1;
                        timer <= 0;
                        show_idx <= 0;
                    end
                end
                
                1: begin // SHOW_DELAY
                    box_is_lit <= 0;
                    if (timer >= 15000000) begin // 0.3s delay between lights
                        timer <= 0;
                        state <= 2;
                        current_lit_box <= seq_mem[show_idx];
                        peri_trigger[0] <= 1; // Beep!
                    end else begin
                        timer <= timer + 1;
                    end
                end
                
                2: begin // SHOW_BOX
                    box_is_lit <= 1;
                    if (timer >= 25000000) begin // 0.5s light duration
                        timer <= 0;
                        if (show_idx == score) begin
                            state <= 3; // Finished showing, wait for input
                            input_idx <= 0;
                        end else begin
                            state <= 1;
                            show_idx <= show_idx + 1;
                        end
                    end else begin
                        timer <= timer + 1;
                    end
                end
                
                3: begin // WAIT_INPUT
                    box_is_lit <= 0;
                    if (key_left_pulse || key_right_pulse || key_rot_pulse || key_drop_pulse) begin
                        current_lit_box <= user_key_val;
                        if (user_key_val == seq_mem[input_idx]) begin
                            peri_trigger[0] <= 1;
                            state <= 4;
                            timer <= 0;
                            input_idx <= input_idx + 1;
                        end else begin
                            state <= 5;
                            timer <= 0;
                            peri_trigger[1] <= 1; // Game Over beep
                        end
                    end
                end
                
                4: begin // LIT_INPUT (visual feedback for player press)
                    box_is_lit <= 1;
                    if (timer >= 12000000) begin // 0.24s light up
                        box_is_lit <= 0;
                        if (input_idx > score) begin // Round completed!
                            if (score >= 4'd4) begin // Win condition (5 levels)
                                score <= 4'd5;
                                state <= 6; 
                                timer <= 0;
                                peri_trigger[2] <= 1; // WIN beep
                            end else begin
                                score <= score + 1;
                                state <= 0; // GENERATE NEW RANDOM SEQUENCE
                                gen_idx <= 0;
                                timer <= 0;
                            end
                        end else begin
                            state <= 3; // Wait for next button
                        end
                    end else begin
                        timer <= timer + 1;
                    end
                end
                
                5: begin // GAME OVER
                    box_is_lit <= 0;
                    if (timer < 75000000) begin
                        timer <= timer + 1;
                    end else if (any_key) begin
                        state <= 0;
                        score <= 0;
                        gen_idx <= 0;
                    end
                end
                
                6: begin // WIN
                    box_is_lit <= 0;
                    if (timer < 75000000) begin
                        timer <= timer + 1;
                    end else if (any_key) begin
                        state <= 0;
                        score <= 0;
                        gen_idx <= 0;
                    end
                end
            endcase
        end
    end
    
    // game_state map
    always @(*) begin
        if (state == 5) game_state = 2'b01;      // GAME OVER
        else if (state == 6) game_state = 2'b10; // WIN
        else game_state = 2'b00;                 // PLAYING
    end
    
    // Rendering Logic
    always @(posedge clk) begin
        if (!en) begin
            pixel_color <= 0;
        end else begin
            if (box_up) begin
                if (box_is_lit && current_lit_box == 2'd0)
                    pixel_color <= rb_up ? 4'd5 : 4'd2; // Lit: Red box, Yellow ribbon
                else 
                    pixel_color <= rb_up ? 4'd12 : 4'd11; // Unlit
            end
            else if (box_right) begin
                if (box_is_lit && current_lit_box == 2'd1)
                    pixel_color <= rb_right ? 4'd5 : 4'd6; // Lit: Orange box
                else 
                    pixel_color <= rb_right ? 4'd12 : 4'd11;
            end
            else if (box_down) begin
                if (box_is_lit && current_lit_box == 2'd2)
                    pixel_color <= rb_down ? 4'd5 : 4'd4; // Lit: Blue box
                else 
                    pixel_color <= rb_down ? 4'd12 : 4'd11;
            end
            else if (box_left) begin
                if (box_is_lit && current_lit_box == 2'd3)
                    pixel_color <= rb_left ? 4'd5 : 4'd3; // Lit: Green box
                else 
                    pixel_color <= rb_left ? 4'd12 : 4'd11;
            end
            else begin
                pixel_color <= 4'd0;
            end
        end
    end

endmodule
