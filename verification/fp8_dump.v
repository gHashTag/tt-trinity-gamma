// Exhaustively dump fp16 -> fp8(E4M3) for all 65536 fp16 inputs.
module fp8_dump;
    reg signed [15:0] x; wire [7:0] q;
    fp8_e4m3_quantizer uut(.fp16_in(x), .fp8_out(q));
    integer f,i;
    initial begin
        f=$fopen("/tmp/gf16sim/fp8_vec.txt","w");
        for (i=0;i<65536;i=i+1) begin x=i[15:0]; #1; $fwrite(f,"%04h %02h\n",x,q); end
        $fclose(f); $display("dumped 65536 fp16->fp8 vectors"); $finish;
    end
endmodule
