module gf12_add_sweep;
  reg [11:0] a,b; wire [11:0] r; gf12_add u(.a(a),.b(b),.result(r));
  function real dec; input [11:0] v; reg [3:0] e; reg [6:0] m; real x; integer i;
   begin e=v[10:7];m=v[6:0]; if(e==0&&m==0)x=0.0; else if(e==4'd15)x=1e9; else begin x=1.0+m/128.0; if(e>=7)for(i=0;i<e-7;i=i+1)x=x*2.0; else for(i=0;i<7-e;i=i+1)x=x/2.0; end dec=v[11]?-x:x; end endfunction
  function isn; input [11:0] v; reg[3:0] e; begin e=v[10:7]; isn=(e!=0&&e!=4'd15); end endfunction
  integer i,fsame,fopp,chk; real va,vb,ex,go,re,mx,ae; integer seed;
  initial begin seed=1;fsame=0;fopp=0;chk=0;mx=0.0;
   for(i=0;i<300000;i=i+1) begin a={$random(seed)}%4096; b={$random(seed)}%4096;
    if(isn(a)&&isn(b))begin #1;va=dec(a);vb=dec(b);ex=va+vb;ae=(ex<0)?-ex:ex;
     if(ae>=0.05&&ae<=240.0)begin go=dec(r);re=(go>ex)?(go-ex)/ae:(ex-go)/ae;chk=chk+1;if(re>mx)mx=re;
      if(re>0.012)begin if(a[11]==b[11])fsame=fsame+1; else fopp=fopp+1; end end end end
   $display("GF12_ADD: same-sign fail=%0d  opp-sign fail=%0d  /%0d chk  maxrel=%.2f%%",fsame,fopp,chk,mx*100.0); $finish; end endmodule
