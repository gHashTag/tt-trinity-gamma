// Dump random (a,b,result) vectors for gf64/128/256 at exp=bias (values [1,2)).
// Python checks against an exact (Fraction) reference with round-half-up.
module gf_wide_dump;
    reg  [63:0]  a64,b64;  wire [63:0]  r64;
    reg  [127:0] a128,b128; wire [127:0] r128;
    reg  [255:0] a256,b256; wire [255:0] r256;
    gf64_mul  u64 (.a(a64),.b(b64),.result(r64));
    gf128_mul u128(.a(a128),.b(b128),.result(r128));
    gf256_mul u256(.a(a256),.b(b256),.result(r256));
    integer fa,fb,fc,i;
    reg [255:0] m;  // random mantissa bits source
    initial begin
        fa=$fopen("/tmp/gf16sim/gf64_vec.txt","w");
        fb=$fopen("/tmp/gf16sim/gf128_vec.txt","w");
        fc=$fopen("/tmp/gf16sim/gf256_vec.txt","w");
        for (i=0;i<20000;i=i+1) begin
            // gf64: M=39, exp=bias 8388607 (24-bit field)
            m={$random,$random}; a64={1'b0,24'd8388607, m[38:0]};
            m={$random,$random}; b64={1'b0,24'd8388607, m[38:0]};
            // gf128: M=79, exp=bias (48-bit)
            m={$random,$random,$random}; a128={1'b0,48'd140737488355327, m[78:0]};
            m={$random,$random,$random}; b128={1'b0,48'd140737488355327, m[78:0]};
            // gf256: M=158, exp=bias (97-bit)
            m={$random,$random,$random,$random,$random}; a256={1'b0,97'd79228162514264337593543950335, m[157:0]};
            m={$random,$random,$random,$random,$random}; b256={1'b0,97'd79228162514264337593543950335, m[157:0]};
            #1;
            $fwrite(fa,"%h %h %h\n",a64,b64,r64);
            $fwrite(fb,"%h %h %h\n",a128,b128,r128);
            $fwrite(fc,"%h %h %h\n",a256,b256,r256);
        end
        $fclose(fa);$fclose(fb);$fclose(fc);
        $display("dumped 20000 vectors each for gf64/128/256");
        $finish;
    end
endmodule
