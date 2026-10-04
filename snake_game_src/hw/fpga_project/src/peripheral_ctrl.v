module peripheral_ctrl(
    input clk,
    input rst_n,
    input btn_click_pulse,        // Pulse on button click (beep)
    input [7:0] peri_trigger,     // [0]: Ăn điểm, [1]: Game Over, [2]: Win
    input [3:0] score,            // Current score (displayed on 4 LEDs)
    input [1:0] game_state,       // 0: Playing, 1: Game Over, 2: Win
    output reg buzzer,
    output reg [3:0] led
);

    // --- BUZZER FREQUENCY GENERATOR (PWM) ---
    // Cycle values for audio frequencies (at 50MHz):
    // Click nút bấm: ~2.8kHz  -> chu kỳ = 17,857
    // Eat apple: ~1.8kHz -> cycle = 27,777
    // Game Over:     ~600Hz   -> chu kỳ = 83,333
    // Win Fanfare:   ~2.5kHz  -> chu kỳ = 20,000
    reg [16:0] pwm_period;
    reg [16:0] pwm_cnt;
    
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            pwm_cnt <= 0;
        end else begin
            if (pwm_cnt >= pwm_period) 
                pwm_cnt <= 0;
            else 
                pwm_cnt <= pwm_cnt + 1;
        end
    end
    
    // Buzzer duration counter
    reg [25:0] tone_timer;
    reg is_playing;
    
    // LED flash counter on score (~200ms = 10,000,000 cycles)
    reg [23:0] flash_timer;
    reg led_flash_active;
    
    // Win celebration flash counter
    reg [22:0] win_blink_cnt;
    
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            buzzer <= 0;
            led <= 0;
            pwm_period <= 20000;
            tone_timer <= 0;
            is_playing <= 0;
            flash_timer <= 0;
            led_flash_active <= 0;
            win_blink_cnt <= 0;
        end else begin
            // 1. PRIORITIZE BUZZER AUDIO TRIGGERS
            if(peri_trigger[2]) begin
                // WIN: Long resonant beep (~800ms)
                pwm_period <= 17857; // ~2.8kHz
                tone_timer <= 40000000; // 0.8s
                is_playing <= 1;
            end else if(peri_trigger[1]) begin
                // GAME OVER: Deep warning beep (~350ms)
                pwm_period <= 83333; // ~600Hz
                tone_timer <= 17500000; // 0.35s
                is_playing <= 1;
            end else if(peri_trigger[0]) begin
                // ĂN ĐƯỢC 1 ĐIỂM: Tiếng vui tươi (~80ms)
                pwm_period <= 27777; // ~1.8kHz
                tone_timer <= 4000000; // 0.08s
                is_playing <= 1;
                // Trigger LED flash
                led_flash_active <= 1;
                flash_timer <= 10000000; // Flash 200ms
            end else if(btn_click_pulse && !is_playing) begin
                // EACH BUTTON PRESS: Short click beep (~20ms)
                pwm_period <= 20000; // ~2.5kHz
                tone_timer <= 1000000; // 20ms
                is_playing <= 1;
            end
            
            // 2. ĐẾM THỜI LƯỢNG BUZZER
            if(is_playing) begin
                if(tone_timer > 0) begin
                    tone_timer <= tone_timer - 1;
                    buzzer <= (pwm_cnt < (pwm_period >> 1)); // Output 50% duty square wave
                end else begin
                    is_playing <= 0;
                    buzzer <= 0;
                end
            end else begin
                buzzer <= 0;
            end
            
            // 3. HIỆU ỨNG LEDS
            if(game_state == 2'b10) begin
                // On WIN: 4 LEDs flash alternately to celebrate
                win_blink_cnt <= win_blink_cnt + 1;
                led <= win_blink_cnt[22] ? 4'b1010 : 4'b0101;
            end else if(game_state == 2'b01) begin
                // Khi GAME OVER: Cả 4 LED sáng đứng hoặc tắt
                led <= 4'b0000;
            end else if(led_flash_active) begin
                // KHI ĂN ĐƯỢC ĐIỂM: 4 LED nhấp nháy sáng bừng lên
                if(flash_timer > 0) begin
                    flash_timer <= flash_timer - 1;
                    led <= 4'b1111;
                end else begin
                    led_flash_active <= 0;
                end
            end else begin
                // ĐANG CHƠI BÌNH THƯỜNG: Hiển thị điểm số hiện tại (0 - 10) dưới dạng nhị phân trên 4 LED!
                led <= score;
            end
        end
    end

endmodule
