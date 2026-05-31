`default_nettype none
module int8_quantizer (
    input  wire signed [31:0] value,
    input  wire [7:0]  scale,
    output reg  [7:0]  result
);

    wire signed [31:0] scaled = value >>> scale;  // FIX: full width before saturate (was [7:0] -> truncated -> saturation dead -> wrap)

    always @(*) begin
        if (scaled > 32'sd127)
            result = 8'd127;
        else if (scaled < -32'sd128)
            result = 8'd128;
        else
            result = scaled[7:0];
    end

endmodule