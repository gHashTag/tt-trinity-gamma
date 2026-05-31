module gf8_add_sweep;
  reg [7:0] a,b; wire [7:0] r; gf8_add uut(.a(a),.b(b),.result(r));
  function real dec; input [7:0] v; reg [2:0] e; reg [3:0] m; real x; integer i;
    begin e=v[6:4]; m=v[3:0];
      if(e==0&&m==0) x=0.0; else if(e==3'd7) x=1.0e9;
      else begin x=1.0+m/16.0; if(e>=3) for(i=0;i<(e-3);i=i+1) x=x*2.0; else for(i=0;i<(3-e);i=i+1) x=x/2.0; end
      dec=v[7]?-x:x; end endfunction
  function isn; input [7:0] v; reg [2:0] e; begin e=v[6:4]; isn=(e!=0&&e!=3'd7); end endfunction
  integer ia,ib,fails,chk; real va,vb,ex,go,re,mx,ae;
  initial begin fails=0;chk=0;mx=0.0;
    for(ia=0;ia<256;ia=ia+1) for(ib=0;ib<256;ib=ib+1) begin
      a=ia[7:0]; b=ib[7:0];
      if(isn(a)&&isn(b)) begin #1; va=dec(a);vb=dec(b);ex=va+vb; ae=(ex<0)?-ex:ex;
        if(ae>=0.25&&ae<=15.5) begin go=dec(r); re=(go>ex)?(go-ex)/ae:(ex-go)/ae; chk=chk+1; if(re>mx)mx=re;
          if(re>0.08) begin fails=fails+1; if(fails<=6)$display("GF8ADD FAIL a=%h(%f)+b=%h(%f) r=%h got=%f exp=%f re=%.1f%%",a,va,b,vb,r,go,ex,re*100.0); end end
      end end
    $display("GF8_ADD: %0d/%0d fail(>8%%) maxrel=%.2f%% -> %s",fails,chk,mx*100.0,(fails==0)?"CLEAN":"BUGS"); $finish; end
endmodule
