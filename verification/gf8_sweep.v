// Exhaustive float-reference sweep of gf8_mul (GF8 = 1/3/4, bias 3).
module gf8_sweep;
    reg  [7:0] a, b; wire [7:0] result;
    gf8_mul uut(.a(a),.b(b),.result(result));

    function real dec; input [7:0] v; reg s; reg [2:0] e; reg [3:0] m; real r; integer i;
        begin s=v[7]; e=v[6:4]; m=v[3:0];
            if (e==0&&m==0) r=0.0;
            else if (e==3'd7) r=1.0e9;            // inf/nan sentinel
            else begin r=1.0+m/16.0; if(e>=3) for(i=0;i<(e-3);i=i+1) r=r*2.0; else for(i=0;i<(3-e);i=i+1) r=r/2.0; end
            if (s) r=-r; dec=r; end
    endfunction
    function isnorm; input [7:0] v; reg [2:0] e; reg [3:0] m;
        begin e=v[6:4]; m=v[3:0]; isnorm=(e!=3'd0 && e!=3'd7); end
    endfunction

    integer ia, ib, fails, checked; real va,vb,expd,got,re,maxre;
    // GF8 normal magnitude range: min 2^(1-3)*1.0=0.25 ; max 2^(6-3)*(1+15/16)=15.5
    initial begin
        fails=0; checked=0; maxre=0.0;
        for (ia=0; ia<256; ia=ia+1) for (ib=0; ib<256; ib=ib+1) begin
            a=ia[7:0]; b=ib[7:0];
            if (isnorm(a) && isnorm(b)) begin
                #1; va=dec(a); vb=dec(b); expd=va*vb;
                // only check products that land in GF8 normal range (avoid over/underflow)
                if ((expd<0?-expd:expd) >= 0.25 && (expd<0?-expd:expd) <= 15.5) begin
                    got=dec(result); re=(got>expd)?(got-expd)/((expd<0)?-expd:expd):(expd-got)/((expd<0)?-expd:expd);
                    checked=checked+1; if(re>maxre)maxre=re;
                    if (re>0.08) begin fails=fails+1; if(fails<=8) $display("GF8 FAIL a=%h(%f) b=%h(%f) res=%h got=%f exp=%f re=%f%%",a,va,b,vb,result,got,expd,re*100.0); end
                end
            end
        end
        $display("GF8 : %0d/%0d checked fail(>8%%) maxrel=%f%%  -> %s", fails, checked, maxre*100.0, (fails==0)?"CLEAN":"BUGS");
        $finish;
    end
endmodule
