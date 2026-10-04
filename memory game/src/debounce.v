module debounce (
    input clk,
    input i_btn,
    output reg o_btn_state
);
    reg [16:0] count;
    reg btn_sync;

    always @(posedge clk) begin
        btn_sync <= i_btn;
        if (btn_sync == o_btn_state)
            count <= 0;
        else begin
            count <= count + 1;
            if (count == 17'd100_000) // Khoảng 2ms với clk 50MHz
                o_btn_state <= btn_sync;
        end
    end
endmodule