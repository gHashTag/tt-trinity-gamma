module gf32_check;
    reg [31:0] a,b; wire [31:0] r;
    gf32_mul uut(.a(a),.b(b),.result(r));
    function real d32; input [31:0] v; reg [11:0] e; reg [18:0] m; real x; integer i;
        begin e=v[30:19]; m=v[18:0];
            if(e==0&&m==0) x=0.0; else if(e==12'd4095) x=1.0e30;
            else begin x=1.0+m/524288.0; if(e>=2047) for(i=0;i<(e-2047);i=i+1) x=x*2.0; else for(i=0;i<(2047-e);i=i+1) x=x/2.0; end
            if(v[31]) x=-x; d32=x; end endfunction
    integer i,fails,checked; real va,vb,ex,go,re,mx; integer seed; reg [11:0] ea,eb; reg [18:0] ma,mb;
    initial begin
        seed=99; fails=0; checked=0; mx=0.0;
        // identity sanity
        a={1'b0,12'd2047,19'd0}; b=a; #1;
        $display("sanity 1.0*1.0 = %h (%f)  %s", r, d32(r), (d32(r)==1.0)?"OK":"WRONG");
        for (i=0;i<200000;i=i+1) begin
            ea=2042+({$random(seed)}%11); eb=2042+({$random(seed)}%11);
            ma=$random(seed); mb=$random(seed);
            a={1'b0,ea,ma}; b={1'b0,eb,mb}; #1;
            va=d32(a); vb=d32(b); ex=va*vb; go=d32(r);
            re=(go>ex)?(go-ex)/ex:(ex-go)/ex; checked=checked+1; if(re>mx)mx=re;
            if(re>0.000003) begin fails=fails+1; if(fails<=6) $display("FAIL a=%h b=%h r=%h got=%.8f exp=%.8f re=%.6f%%",a,b,r,go,ex,re*100.0); end
        end
        $display("GF32(fixed): %0d/%0d fail(>3e-6) maxrel=%.6f%%  -> %s", fails,checked,mx*100.0,(fails==0)?"CLEAN":"BUGS");
        $finish;
    end
endmodule
