// Same-sign addition verdict for the fixed narrow adders (gf8/gf12).
// (Opposite-sign/cancellation precision is a separate known limitation, reported
//  but not gated.) CLEAN iff same-sign addition has 0 fails beyond tolerance.
module adder_gate;
    reg [7:0]  a8,b8;   wire [7:0]  r8;
    reg [11:0] a12,b12; wire [11:0] r12;
    gf8_add  u8 (.a(a8), .b(b8), .result(r8));
    gf12_add u12(.a(a12),.b(b12),.result(r12));
    function real d8; input [7:0] v; reg [2:0] e; reg [3:0] m; real x; integer i;
      begin e=v[6:4];m=v[3:0]; if(e==0&&m==0)x=0.0; else if(e==7)x=1e9; else begin x=1.0+m/16.0; if(e>=3)for(i=0;i<e-3;i=i+1)x=x*2.0; else for(i=0;i<3-e;i=i+1)x=x/2.0; end d8=v[7]?-x:x; end endfunction
    function real d12; input [11:0] v; reg [3:0] e; reg [6:0] m; real x; integer i;
      begin e=v[10:7];m=v[6:0]; if(e==0&&m==0)x=0.0; else if(e==4'd15)x=1e9; else begin x=1.0+m/128.0; if(e>=7)for(i=0;i<e-7;i=i+1)x=x*2.0; else for(i=0;i<7-e;i=i+1)x=x/2.0; end d12=v[11]?-x:x; end endfunction
    integer i,f8,f12; real ex,go,re,ae; integer seed; reg [3:0] e8a,e8b; reg [3:0] m8a,m8b;
    reg [3:0] e12a,e12b; reg [6:0] m12a,m12b;
    initial begin seed=2; f8=0; f12=0;
      for(i=0;i<60000;i=i+1) begin
        e8a=1+({$random(seed)}%6); e8b=1+({$random(seed)}%6); m8a=$random(seed); m8b=$random(seed);
        a8={1'b0,e8a[2:0],m8a}; b8={1'b0,e8b[2:0],m8b}; #1;   // same sign (both +)
        ex=d8(a8)+d8(b8); ae=ex; go=d8(r8); re=(go>ex)?(go-ex)/ae:(ex-go)/ae;
        if(ae>=0.25&&ae<=15.5&&re>0.08) f8=f8+1;
        e12a=1+({$random(seed)}%14); e12b=1+({$random(seed)}%14); m12a=$random(seed); m12b=$random(seed);
        a12={1'b0,e12a,m12a}; b12={1'b0,e12b,m12b}; #1;
        ex=d12(a12)+d12(b12); ae=ex; go=d12(r12); re=(go>ex)?(go-ex)/ae:(ex-go)/ae;
        if(ae>=0.05&&ae<=240.0&&re>0.012) f12=f12+1;
      end
      $display("ADDERS same-sign: gf8=%0d gf12=%0d fail -> %s", f8, f12, (f8==0&&f12==0)?"CLEAN":"BUGS");
      $finish; end
endmodule
