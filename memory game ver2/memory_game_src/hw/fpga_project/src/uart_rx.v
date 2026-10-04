module uart_rx #(parameter CLKS_PER_BIT = 54) (
    input clk,
    input rst_n,
    input rx,
    output reg [7:0] rx_data,
    output reg rx_valid
);

    reg [2:0] state;
    reg [15:0] clk_cnt;
    reg [2:0] bit_idx;
    reg [7:0] data_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= 0;
            rx_valid <= 0;
            clk_cnt <= 0;
        end else begin
            rx_valid <= 0;
            case (state)
                0: begin // IDLE
                    if (rx == 0) begin
                        state <= 1;
                        clk_cnt <= 0;
                    end
                end
                1: begin // START BIT
                    if (clk_cnt < (CLKS_PER_BIT / 2)) begin
                        clk_cnt <= clk_cnt + 1;
                    end else begin
                        if (rx == 0) begin // Verify start bit
                            clk_cnt <= 0;
                            bit_idx <= 0;
                            state <= 2;
                        end else begin
                            state <= 0;
                        end
                    end
                end
                2: begin // DATA BITS
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1;
                    end else begin
                        clk_cnt <= 0;
                        data_reg[bit_idx] <= rx;
                        if (bit_idx < 7) begin
                            bit_idx <= bit_idx + 1;
                        end else begin
                            state <= 3;
                        end
                    end
                end
                3: begin // STOP BIT
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1;
                    end else begin
                        clk_cnt <= 0;
                        rx_data <= data_reg;
                        rx_valid <= 1;
                        state <= 0;
                    end
                end
            endcase
        end
    end

endmodule
