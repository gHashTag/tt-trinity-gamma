module e5m2_dump;
  reg signed [15:0] x; wire [7:0] q; integer f,i;
  fp8_e5m2_quantizer uut(.fp16_in(x),.fp8_out(q));
  initial begin f=$fopen("/tmp/gf16sim/e5m2_vec.txt","w");
    for(i=0;i<65536;i=i+1) begin x=i[15:0]; #1; $fwrite(f,"%04h %02h\n",x,q); end
    $fclose(f); $display("dumped"); $finish; end
endmodule
