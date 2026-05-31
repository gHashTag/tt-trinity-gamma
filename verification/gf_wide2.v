module gf_wide_sweep;
    reg  [19:0] a20,b20; wire [19:0] r20;
    reg  [23:0] a24,b24; wire [23:0] r24;
    reg  [31:0] a32,b32; wire [31:0] r32;
    reg  [11:0] ma20,mb20; reg [13:0] ma24,mb24; reg [18:0] ma32,mb32;
    gf20_mul u20(.a(a20),.b(b20),.result(r20));
    gf24_mul u24(.a(a24),.b(b24),.result(r24));
    gf32_mul u32(.a(a32),.b(b32),.result(r32));

    function real d20; input [19:0] v; reg [6:0] e; reg [11:0] m; real r; integer i;
        begin e=v[18:12]; m=v[11:0]; r=1.0+m/4096.0;
            if(e>=63) for(i=0;i<(e-63);i=i+1) r=r*2.0; else for(i=0;i<(63-e);i=i+1) r=r/2.0;
            if(v[19]) r=-r; d20=r; end endfunction
    function real d24; input [23:0] v; reg [8:0] e; reg [13:0] m; real r; integer i;
        begin e=v[22:14]; m=v[13:0]; r=1.0+m/16384.0;
            if(e>=255) for(i=0;i<(e-255);i=i+1) r=r*2.0; else for(i=0;i<(255-e);i=i+1) r=r/2.0;
            if(v[23]) r=-r; d24=r; end endfunction
    function real d32; input [31:0] v; reg [11:0] e; reg [18:0] m; real r; integer i;
        begin e=v[30:19]; m=v[18:0]; r=1.0+m/524288.0;
            if(e>=2047) for(i=0;i<(e-2047);i=i+1) r=r*2.0; else for(i=0;i<(2047-e);i=i+1) r=r/2.0;
            if(v[31]) r=-r; d32=r; end endfunction

    integer i, f20,f24,f32, n; real e_,g_,re,m20,m24,m32; integer seed;
    initial begin
        seed=11; f20=0;f24=0;f32=0; n=0; m20=0;m24=0;m32=0;
        for (i=0;i<100000;i=i+1) begin
            ma20=$random(seed); mb20=$random(seed); ma24=$random(seed); mb24=$random(seed); ma32=$random(seed); mb32=$random(seed);
            a20={1'b0,7'd63,ma20};   b20={1'b0,7'd63,mb20};
            a24={1'b0,9'd255,ma24};  b24={1'b0,9'd255,mb24};
            a32={1'b0,12'd2047,ma32};b32={1'b0,12'd2047,mb32};
            #1; n=n+1;
            e_=d20(a20)*d20(b20); g_=d20(r20); re=(g_>e_)?(g_-e_)/e_:(e_-g_)/e_; if(re>m20)m20=re; if(re>0.001) f20=f20+1;
            e_=d24(a24)*d24(b24); g_=d24(r24); re=(g_>e_)?(g_-e_)/e_:(e_-g_)/e_; if(re>m24)m24=re; if(re>0.001) f24=f24+1;
            e_=d32(a32)*d32(b32); g_=d32(r32); re=(g_>e_)?(g_-e_)/e_:(e_-g_)/e_; if(re>m32)m32=re; if(re>0.001) f32=f32+1;
        end
        $display("GF20: %0d/%0d fail(>0.1%%) maxrel=%f%%  -> %s", f20,n,m20*100.0,(f20==0)?"CLEAN":"BUGS");
        $display("GF24: %0d/%0d fail(>0.1%%) maxrel=%f%%  -> %s", f24,n,m24*100.0,(f24==0)?"CLEAN":"BUGS");
        $display("GF32: %0d/%0d fail(>0.1%%) maxrel=%f%%  -> %s", f32,n,m32*100.0,(f32==0)?"CLEAN":"BUGS");
        $finish;
    end
endmodule
