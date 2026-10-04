module uart_tx #(parameter CLKS_PER_BIT = 54) (
    input clk,
    input rst_n,
    input tx_start,
    input [7:0] tx_data,
    output reg tx,
    output reg tx_busy
);

    reg [2:0] state;
    reg [7:0] data_reg;
    reg [2:0] bit_idx;
    reg [15:0] clk_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= 0;
            tx <= 1;
            tx_busy <= 0;
            clk_cnt <= 0;
        end else begin
            case (state)
                0: begin // IDLE
                    tx <= 1;
                    tx_busy <= 0;
                    if (tx_start) begin
                        data_reg <= tx_data;
                        tx_busy <= 1;
                        state <= 1;
                        clk_cnt <= 0;
                    end
                end
                1: begin // START BIT
                    tx <= 0;
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1;
                    end else begin
                        clk_cnt <= 0;
                        bit_idx <= 0;
                        state <= 2;
                    end
                end
                2: begin // DATA BITS
                    tx <= data_reg[bit_idx];
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1;
                    end else begin
                        clk_cnt <= 0;
                        if (bit_idx < 7) begin
                            bit_idx <= bit_idx + 1;
                        end else begin
                            state <= 3;
                        end
                    end
                end
                3: begin // STOP BIT
                    tx <= 1;
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1;
                    end else begin
                        clk_cnt <= 0;
                        state <= 0;
                    end
                end
            endcase
        end
    end

endmodule
