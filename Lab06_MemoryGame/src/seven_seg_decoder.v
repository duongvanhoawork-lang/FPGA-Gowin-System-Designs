module seven_seg_decoder (
    input [3:0] i_data,      // 0-7 là điểm, 10 là 'F', 11 là 'A'
    output reg [6:0] o_seg   // abcdefg (active low - mức thấp sáng)
);
    always @(*) begin
        case (i_data)
            4'd0: o_seg = 7'b1000000; // 0
            4'd1: o_seg = 7'b1111001; // 1
            4'd2: o_seg = 7'b0100100; // 2
            4'd3: o_seg = 7'b0110000; // 3
            4'd4: o_seg = 7'b0011001; // 4
            4'd5: o_seg = 7'b0010010; // 5
            4'd6: o_seg = 7'b0000010; // 6
            4'd7: o_seg = 7'b1111000; // 7
            4'd10: o_seg = 7'b0001110; // F (Failure)
            4'd11: o_seg = 7'b0001000; // A (Ace/Win)
            default: o_seg = 7'b1111111; // Tắt hết
        endcase
    end
endmodule