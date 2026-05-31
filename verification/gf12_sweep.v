// Random float-reference sweep of gf12_mul (GF12 = 1/4/7, bias 7).
module gf12_sweep;
    reg  [11:0] a, b; wire [11:0] result;
    gf12_mul uut(.a(a),.b(b),.result(result));
    function real dec; input [11:0] v; reg s; reg [3:0] e; reg [6:0] m; real r; integer i;
        begin s=v[11]; e=v[10:7]; m=v[6:0];
            if (e==0&&m==0) r=0.0; else if (e==4'd15) r=1.0e9;
            else begin r=1.0+m/128.0; if(e>=7) for(i=0;i<(e-7);i=i+1) r=r*2.0; else for(i=0;i<(7-e);i=i+1) r=r/2.0; end
            if (s) r=-r; dec=r; end
    endfunction
    function isnorm; input [11:0] v; reg [3:0] e; begin e=v[10:7]; isnorm=(e!=0 && e!=4'd15); end endfunction
    integer i, fails, checked; real va,vb,expd,got,re,maxre,ae; integer seed;
    initial begin
        seed=3; fails=0; checked=0; maxre=0.0;
        for (i=0;i<200000;i=i+1) begin
            a={$random(seed)}%4096; b={$random(seed)}%4096;
            if (isnorm(a)&&isnorm(b)) begin
                #1; va=dec(a); vb=dec(b); expd=va*vb; ae=(expd<0)?-expd:expd;
                if (ae>=0.02 && ae<=200.0) begin
                    got=dec(result); re=(got>expd)?(got-expd)/ae:(expd-got)/ae;
                    checked=checked+1; if(re>maxre)maxre=re;
                    if (re>0.015) begin fails=fails+1; if(fails<=6) $display("GF12 FAIL a=%h(%f) b=%h(%f) res=%h got=%f exp=%f re=%f%%",a,va,b,vb,result,got,expd,re*100.0); end
                end
            end
        end
        $display("GF12: %0d/%0d checked fail(>1.5%%) maxrel=%f%%  -> %s", fails, checked, maxre*100.0, (fails==0)?"CLEAN":"BUGS");
        $finish;
    end
endmodule
