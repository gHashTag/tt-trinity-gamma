module gf_identity;
    reg [19:0] a20,b20; wire [19:0] r20;
    reg [23:0] a24,b24; wire [23:0] r24;
    reg [31:0] a32,b32; wire [31:0] r32;
    gf20_mul u20(.a(a20),.b(b20),.result(r20));
    gf24_mul u24(.a(a24),.b(b24),.result(r24));
    gf32_mul u32(.a(a32),.b(b32),.result(r32));
    initial begin
        // 1.0 = {0, bias, 0}
        a20=20'h3F000; b20=20'h3F000;       // gf20 1.0 (exp63)
        a24={1'b0,9'd255,14'd0}; b24=a24;    // gf24 1.0 (exp255)
        a32={1'b0,12'd2047,19'd0}; b32=a32;  // gf32 1.0 (exp2047)
        #1;
        $display("GF20 1.0*1.0: a=%h result=%h  expect=%h  %s", a20,r20,a20,(r20==a20)?"OK":"WRONG");
        $display("GF24 1.0*1.0: a=%h result=%h  expect=%h  %s", a24,r24,a24,(r24==a24)?"OK":"WRONG");
        $display("GF32 1.0*1.0: a=%h result=%h  expect=%h  %s", a32,r32,a32,(r32==a32)?"OK":"WRONG");
        $finish;
    end
endmodule
