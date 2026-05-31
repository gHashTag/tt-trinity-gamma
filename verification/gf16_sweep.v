// Sweep self-check for gf16_mul against a float reference.
// Operands in [1,2) (exp=31), full mantissa grid. Flags relative error > 0.3%.
module gf16_mul_sweep;
    reg  [15:0] a, b;
    wire [15:0] result;
    gf16_mul uut (.a(a), .b(b), .result(result));

    function real decode_gf16;
        input [15:0] v;
        reg sign; reg [5:0] exp; reg [8:0] mant; real r; integer i;
        begin
            sign = v[15]; exp = v[14:9]; mant = v[8:0];
            if (exp == 6'd0 && mant == 9'd0) r = 0.0;
            else if (exp == 6'd63) r = 1.0e30;
            else begin
                r = 1.0 + mant / 512.0;
                if (exp >= 31) for (i=0;i<(exp-31);i=i+1) r = r*2.0;
                else for (i=0;i<(31-exp);i=i+1) r = r/2.0;
            end
            if (sign) r = -r;
            decode_gf16 = r;
        end
    endfunction

    integer ma, mb, fails;
    real va, vb, expd, got, rel, maxrel;
    reg [15:0] amax, bmax;

    initial begin
        fails = 0; maxrel = 0.0;
        for (ma = 0; ma < 512; ma = ma + 1) begin
            for (mb = 0; mb < 512; mb = mb + 1) begin
                a = {1'b0, 6'd31, ma[8:0]};
                b = {1'b0, 6'd31, mb[8:0]};
                #1;
                va = decode_gf16(a); vb = decode_gf16(b);
                expd = va * vb;
                got = decode_gf16(result);
                rel = (got > expd) ? (got-expd)/expd : (expd-got)/expd;
                if (rel > maxrel) begin maxrel = rel; amax = a; bmax = b; end
                if (rel > 0.003) begin
                    fails = fails + 1;
                    if (fails <= 10)
                        $display("FAIL a=%h(%f) b=%h(%f) res=%h got=%f exp=%f rel=%f%%",
                                 a, va, b, vb, result, got, expd, rel*100.0);
                end
            end
        end
        $display("=== sweep done: %0d / 262144 fail (>0.3%%) ; max rel err = %f%% at a=%h b=%h ===",
                 fails, maxrel*100.0, amax, bmax);
        if (fails == 0) $display("SWEEP CLEAN"); else $display("SWEEP FOUND BUGS");
        $finish;
    end
endmodule
