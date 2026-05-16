`default_nettype none
// vsa_matmul_16x16.v — 16×16 ternary XOR-popcount matmul (JEPA-T tier)
// Apache-2.0
//
// PhD anchor: Chapter 35 (CROWN) — large-scale ternary VSA inference.
// 4x area of vsa_matmul_8x8. R-SI-1: zero `*` operators.
// Each element 2 bits {00=+1, 01=-1, 10=0, 11=0}. Result is signed 8-bit.
//
// L-S19: Uses gf16_popcount16 (3-stage pipeline, 16 elements).
//        Fmax target: 150 MHz. LATENCY=3 cycles.
//
// Latency from start: 1 (latch) + 1 (valid pulse) + 3 (pipeline) = 5 cycles.
//
// Encoding (per element, 2 bits):
//   00 = +1   01 = -1   10 = 0   11 = 0

module vsa_matmul_16x16 (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [511:0] a_flat,   // 16×16×2 = 512 bits
    input  wire [511:0] b_flat,
    output reg          done,
    output reg  [2047:0] c_flat,  // 16×16×8 = 2048 bits signed
    output wire          matmul_ok
);

    localparam LATENCY = 3;  // L-S19: 3-stage pipeline

    reg [511:0] a_reg, b_reg;
    reg         busy;
    reg         pipe_valid_in;

    // 256 pipelined inner-product units (16×16)
    wire [255:0] pc_valid_out;
    wire [7:0]   pc_result [0:255];

    genvar gi, gj;
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : gen_row
            for (gj = 0; gj < 16; gj = gj + 1) begin : gen_col
                // Verilog-2005 compatible: extract 32 bits using shift and mask
                wire [31:0] a_row_conn = (a_reg >> (gi * 32)) & 32'hFFFFFFFF;
                wire [31:0] b_row_conn = (b_reg >> (gj * 32)) & 32'hFFFFFFFF;
                gf16_popcount16 #(.N_ELEMS(16), .LATENCY(LATENCY)) u_pc (
                    .clk      (clk),
                    .rst_n    (rst_n),
                    .valid_in (pipe_valid_in),
                    .a_row    (a_row_conn),
                    .b_row    (b_row_conn),
                    .valid_out(pc_valid_out[gi*16 + gj]),
                    .result   (pc_result[gi*16 + gj])
                );
            end
        end
    endgenerate

    reg [1:0] state;
    localparam ST_IDLE  = 2'd0;
    localparam ST_LATCH = 2'd1;
    localparam ST_PIPE  = 2'd2;
    localparam ST_DONE  = 2'd3;

    integer ci, cj;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_reg        <= 512'b0;
            b_reg        <= 512'b0;
            c_flat       <= 2048'b0;
            busy         <= 1'b0;
            done         <= 1'b0;
            pipe_valid_in <= 1'b0;
            state        <= ST_IDLE;
        end else begin
            done          <= 1'b0;
            pipe_valid_in <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (start) begin
                        a_reg <= a_flat;
                        b_reg <= b_flat;
                        busy  <= 1'b1;
                        state <= ST_LATCH;
                    end
                end
                ST_LATCH: begin
                    pipe_valid_in <= 1'b1;
                    state <= ST_PIPE;
                end
                ST_PIPE: begin
                    if (pc_valid_out[0]) begin
                        // Verilog-2005 compatible: assign results byte-by-byte
                        for (ci = 0; ci < 16; ci = ci + 1) begin
                            for (cj = 0; cj < 16; cj = cj + 1) begin
                                // Verilog-2005 compatible: use case for byte assignment
                                case (ci*16 + cj)
                                    8'd0:   c_flat[7:0]     <= pc_result[0];
                                    8'd1:   c_flat[15:8]    <= pc_result[1];
                                    8'd2:   c_flat[23:16]   <= pc_result[2];
                                    8'd3:   c_flat[31:24]   <= pc_result[3];
                                    8'd4:   c_flat[39:32]   <= pc_result[4];
                                    8'd5:   c_flat[47:40]   <= pc_result[5];
                                    8'd6:   c_flat[55:48]   <= pc_result[6];
                                    8'd7:   c_flat[63:56]   <= pc_result[7];
                                    8'd8:   c_flat[71:64]   <= pc_result[8];
                                    8'd9:   c_flat[79:72]   <= pc_result[9];
                                    8'd10:  c_flat[87:80]   <= pc_result[10];
                                    8'd11:  c_flat[95:88]   <= pc_result[11];
                                    8'd12:  c_flat[103:96]  <= pc_result[12];
                                    8'd13:  c_flat[111:104] <= pc_result[13];
                                    8'd14:  c_flat[119:112] <= pc_result[14];
                                    8'd15:  c_flat[127:120] <= pc_result[15];
                                    8'd16:  c_flat[135:128] <= pc_result[16];
                                    8'd17:  c_flat[143:136] <= pc_result[17];
                                    8'd18:  c_flat[151:144] <= pc_result[18];
                                    8'd19:  c_flat[159:152] <= pc_result[19];
                                    8'd20:  c_flat[167:160] <= pc_result[20];
                                    8'd21:  c_flat[175:168] <= pc_result[21];
                                    8'd22:  c_flat[183:176] <= pc_result[22];
                                    8'd23:  c_flat[191:184] <= pc_result[23];
                                    8'd24:  c_flat[199:192] <= pc_result[24];
                                    8'd25:  c_flat[207:200] <= pc_result[25];
                                    8'd26:  c_flat[215:208] <= pc_result[26];
                                    8'd27:  c_flat[223:216] <= pc_result[27];
                                    8'd28:  c_flat[231:224] <= pc_result[28];
                                    8'd29:  c_flat[239:232] <= pc_result[29];
                                    8'd30:  c_flat[247:240] <= pc_result[30];
                                    8'd31:  c_flat[255:248] <= pc_result[31];
                                    8'd32:  c_flat[263:256] <= pc_result[32];
                                    8'd33:  c_flat[271:264] <= pc_result[33];
                                    8'd34:  c_flat[279:272] <= pc_result[34];
                                    8'd35:  c_flat[287:280] <= pc_result[35];
                                    8'd36:  c_flat[295:288] <= pc_result[36];
                                    8'd37:  c_flat[303:296] <= pc_result[37];
                                    8'd38:  c_flat[311:304] <= pc_result[38];
                                    8'd39:  c_flat[319:312] <= pc_result[39];
                                    8'd40:  c_flat[327:320] <= pc_result[40];
                                    8'd41:  c_flat[335:328] <= pc_result[41];
                                    8'd42:  c_flat[343:336] <= pc_result[42];
                                    8'd43:  c_flat[351:344] <= pc_result[43];
                                    8'd44:  c_flat[359:352] <= pc_result[44];
                                    8'd45:  c_flat[367:360] <= pc_result[45];
                                    8'd46:  c_flat[375:368] <= pc_result[46];
                                    8'd47:  c_flat[383:376] <= pc_result[47];
                                    8'd48:  c_flat[391:384] <= pc_result[48];
                                    8'd49:  c_flat[399:392] <= pc_result[49];
                                    8'd50:  c_flat[407:400] <= pc_result[50];
                                    8'd51:  c_flat[415:408] <= pc_result[51];
                                    8'd52:  c_flat[423:416] <= pc_result[52];
                                    8'd53:  c_flat[431:424] <= pc_result[53];
                                    8'd54:  c_flat[439:432] <= pc_result[54];
                                    8'd55:  c_flat[447:440] <= pc_result[55];
                                    8'd56:  c_flat[455:448] <= pc_result[56];
                                    8'd57:  c_flat[463:456] <= pc_result[57];
                                    8'd58:  c_flat[471:464] <= pc_result[58];
                                    8'd59:  c_flat[479:472] <= pc_result[59];
                                    8'd60:  c_flat[487:480] <= pc_result[60];
                                    8'd61:  c_flat[495:488] <= pc_result[61];
                                    8'd62:  c_flat[503:496] <= pc_result[62];
                                    8'd63:  c_flat[511:504] <= pc_result[63];
                                    8'd64:  c_flat[519:512] <= pc_result[64];
                                    8'd65:  c_flat[527:520] <= pc_result[65];
                                    8'd66:  c_flat[535:528] <= pc_result[66];
                                    8'd67:  c_flat[543:536] <= pc_result[67];
                                    8'd68:  c_flat[551:544] <= pc_result[68];
                                    8'd69:  c_flat[559:552] <= pc_result[69];
                                    8'd70:  c_flat[567:560] <= pc_result[70];
                                    8'd71:  c_flat[575:568] <= pc_result[71];
                                    8'd72:  c_flat[583:576] <= pc_result[72];
                                    8'd73:  c_flat[591:584] <= pc_result[73];
                                    8'd74:  c_flat[599:592] <= pc_result[74];
                                    8'd75:  c_flat[607:600] <= pc_result[75];
                                    8'd76:  c_flat[615:608] <= pc_result[76];
                                    8'd77:  c_flat[623:616] <= pc_result[77];
                                    8'd78:  c_flat[631:624] <= pc_result[78];
                                    8'd79:  c_flat[639:632] <= pc_result[79];
                                    8'd80:  c_flat[647:640] <= pc_result[80];
                                    8'd81:  c_flat[655:648] <= pc_result[81];
                                    8'd82:  c_flat[663:656] <= pc_result[82];
                                    8'd83:  c_flat[671:664] <= pc_result[83];
                                    8'd84:  c_flat[679:672] <= pc_result[84];
                                    8'd85:  c_flat[687:680] <= pc_result[85];
                                    8'd86:  c_flat[695:688] <= pc_result[86];
                                    8'd87:  c_flat[703:696] <= pc_result[87];
                                    8'd88:  c_flat[711:704] <= pc_result[88];
                                    8'd89:  c_flat[719:712] <= pc_result[89];
                                    8'd90:  c_flat[727:720] <= pc_result[90];
                                    8'd91:  c_flat[735:728] <= pc_result[91];
                                    8'd92:  c_flat[743:736] <= pc_result[92];
                                    8'd93:  c_flat[751:744] <= pc_result[93];
                                    8'd94:  c_flat[759:752] <= pc_result[94];
                                    8'd95:  c_flat[767:760] <= pc_result[95];
                                    8'd96:  c_flat[775:768] <= pc_result[96];
                                    8'd97:  c_flat[783:776] <= pc_result[97];
                                    8'd98:  c_flat[791:784] <= pc_result[98];
                                    8'd99:  c_flat[799:792] <= pc_result[99];
                                    8'd100: c_flat[807:800] <= pc_result[100];
                                    8'd101: c_flat[815:808] <= pc_result[101];
                                    8'd102: c_flat[823:816] <= pc_result[102];
                                    8'd103: c_flat[831:824] <= pc_result[103];
                                    8'd104: c_flat[839:832] <= pc_result[104];
                                    8'd105: c_flat[847:840] <= pc_result[105];
                                    8'd106: c_flat[855:848] <= pc_result[106];
                                    8'd107: c_flat[863:856] <= pc_result[107];
                                    8'd108: c_flat[871:864] <= pc_result[108];
                                    8'd109: c_flat[879:872] <= pc_result[109];
                                    8'd110: c_flat[887:880] <= pc_result[110];
                                    8'd111: c_flat[895:888] <= pc_result[111];
                                    8'd112: c_flat[903:896] <= pc_result[112];
                                    8'd113: c_flat[911:904] <= pc_result[113];
                                    8'd114: c_flat[919:912] <= pc_result[114];
                                    8'd115: c_flat[927:920] <= pc_result[115];
                                    8'd116: c_flat[935:928] <= pc_result[116];
                                    8'd117: c_flat[943:936] <= pc_result[117];
                                    8'd118: c_flat[951:944] <= pc_result[118];
                                    8'd119: c_flat[959:952] <= pc_result[119];
                                    8'd120: c_flat[967:960] <= pc_result[120];
                                    8'd121: c_flat[975:968] <= pc_result[121];
                                    8'd122: c_flat[983:976] <= pc_result[122];
                                    8'd123: c_flat[991:984] <= pc_result[123];
                                    8'd124: c_flat[999:992] <= pc_result[124];
                                    8'd125: c_flat[1007:1000]<= pc_result[125];
                                    8'd126: c_flat[1015:1008]<= pc_result[126];
                                    8'd127: c_flat[1023:1016]<= pc_result[127];
                                    8'd128: c_flat[1031:1024]<= pc_result[128];
                                    8'd129: c_flat[1039:1032]<= pc_result[129];
                                    8'd130: c_flat[1047:1040]<= pc_result[130];
                                    8'd131: c_flat[1055:1048]<= pc_result[131];
                                    8'd132: c_flat[1063:1056]<= pc_result[132];
                                    8'd133: c_flat[1071:1064]<= pc_result[133];
                                    8'd134: c_flat[1079:1072]<= pc_result[134];
                                    8'd135: c_flat[1087:1080]<= pc_result[135];
                                    8'd136: c_flat[1095:1088]<= pc_result[136];
                                    8'd137: c_flat[1103:1096]<= pc_result[137];
                                    8'd138: c_flat[1111:1104]<= pc_result[138];
                                    8'd139: c_flat[1119:1112]<= pc_result[139];
                                    8'd140: c_flat[1127:1120]<= pc_result[140];
                                    8'd141: c_flat[1135:1128]<= pc_result[141];
                                    8'd142: c_flat[1143:1136]<= pc_result[142];
                                    8'd143: c_flat[1151:1144]<= pc_result[143];
                                    8'd144: c_flat[1159:1152]<= pc_result[144];
                                    8'd145: c_flat[1167:1160]<= pc_result[145];
                                    8'd146: c_flat[1175:1168]<= pc_result[146];
                                    8'd147: c_flat[1183:1176]<= pc_result[147];
                                    8'd148: c_flat[1191:1184]<= pc_result[148];
                                    8'd149: c_flat[1199:1192]<= pc_result[149];
                                    8'd150: c_flat[1207:1200]<= pc_result[150];
                                    8'd151: c_flat[1215:1208]<= pc_result[151];
                                    8'd152: c_flat[1223:1216]<= pc_result[152];
                                    8'd153: c_flat[1231:1224]<= pc_result[153];
                                    8'd154: c_flat[1239:1232]<= pc_result[154];
                                    8'd155: c_flat[1247:1240]<= pc_result[155];
                                    8'd156: c_flat[1255:1248]<= pc_result[156];
                                    8'd157: c_flat[1263:1256]<= pc_result[157];
                                    8'd158: c_flat[1271:1264]<= pc_result[158];
                                    8'd159: c_flat[1279:1272]<= pc_result[159];
                                    8'd160: c_flat[1287:1280]<= pc_result[160];
                                    8'd161: c_flat[1295:1288]<= pc_result[161];
                                    8'd162: c_flat[1303:1296]<= pc_result[162];
                                    8'd163: c_flat[1311:1304]<= pc_result[163];
                                    8'd164: c_flat[1319:1312]<= pc_result[164];
                                    8'd165: c_flat[1327:1320]<= pc_result[165];
                                    8'd166: c_flat[1335:1328]<= pc_result[166];
                                    8'd167: c_flat[1343:1336]<= pc_result[167];
                                    8'd168: c_flat[1351:1344]<= pc_result[168];
                                    8'd169: c_flat[1359:1352]<= pc_result[169];
                                    8'd170: c_flat[1367:1360]<= pc_result[170];
                                    8'd171: c_flat[1375:1368]<= pc_result[171];
                                    8'd172: c_flat[1383:1376]<= pc_result[172];
                                    8'd173: c_flat[1391:1384]<= pc_result[173];
                                    8'd174: c_flat[1399:1392]<= pc_result[174];
                                    8'd175: c_flat[1407:1400]<= pc_result[175];
                                    8'd176: c_flat[1415:1408]<= pc_result[176];
                                    8'd177: c_flat[1423:1416]<= pc_result[177];
                                    8'd178: c_flat[1431:1424]<= pc_result[178];
                                    8'd179: c_flat[1439:1432]<= pc_result[179];
                                    8'd180: c_flat[1447:1440]<= pc_result[180];
                                    8'd181: c_flat[1455:1448]<= pc_result[181];
                                    8'd182: c_flat[1463:1456]<= pc_result[182];
                                    8'd183: c_flat[1471:1464]<= pc_result[183];
                                    8'd184: c_flat[1479:1472]<= pc_result[184];
                                    8'd185: c_flat[1487:1480]<= pc_result[185];
                                    8'd186: c_flat[1495:1488]<= pc_result[186];
                                    8'd187: c_flat[1503:1496]<= pc_result[187];
                                    8'd188: c_flat[1511:1504]<= pc_result[188];
                                    8'd189: c_flat[1519:1512]<= pc_result[189];
                                    8'd190: c_flat[1527:1520]<= pc_result[190];
                                    8'd191: c_flat[1535:1528]<= pc_result[191];
                                    8'd192: c_flat[1543:1536]<= pc_result[192];
                                    8'd193: c_flat[1551:1544]<= pc_result[193];
                                    8'd194: c_flat[1559:1552]<= pc_result[194];
                                    8'd195: c_flat[1567:1560]<= pc_result[195];
                                    8'd196: c_flat[1575:1568]<= pc_result[196];
                                    8'd197: c_flat[1583:1576]<= pc_result[197];
                                    8'd198: c_flat[1591:1584]<= pc_result[198];
                                    8'd199: c_flat[1599:1592]<= pc_result[199];
                                    8'd200: c_flat[1607:1600]<= pc_result[200];
                                    8'd201: c_flat[1615:1608]<= pc_result[201];
                                    8'd202: c_flat[1623:1616]<= pc_result[202];
                                    8'd203: c_flat[1631:1624]<= pc_result[203];
                                    8'd204: c_flat[1639:1632]<= pc_result[204];
                                    8'd205: c_flat[1647:1640]<= pc_result[205];
                                    8'd206: c_flat[1655:1648]<= pc_result[206];
                                    8'd207: c_flat[1663:1656]<= pc_result[207];
                                    8'd208: c_flat[1671:1664]<= pc_result[208];
                                    8'd209: c_flat[1679:1672]<= pc_result[209];
                                    8'd210: c_flat[1687:1680]<= pc_result[210];
                                    8'd211: c_flat[1695:1688]<= pc_result[211];
                                    8'd212: c_flat[1703:1696]<= pc_result[212];
                                    8'd213: c_flat[1711:1704]<= pc_result[213];
                                    8'd214: c_flat[1719:1712]<= pc_result[214];
                                    8'd215: c_flat[1727:1720]<= pc_result[215];
                                    8'd216: c_flat[1735:1728]<= pc_result[216];
                                    8'd217: c_flat[1743:1736]<= pc_result[217];
                                    8'd218: c_flat[1751:1744]<= pc_result[218];
                                    8'd219: c_flat[1759:1752]<= pc_result[219];
                                    8'd220: c_flat[1767:1760]<= pc_result[220];
                                    8'd221: c_flat[1775:1768]<= pc_result[221];
                                    8'd222: c_flat[1783:1776]<= pc_result[222];
                                    8'd223: c_flat[1791:1784]<= pc_result[223];
                                    8'd224: c_flat[1799:1792]<= pc_result[224];
                                    8'd225: c_flat[1807:1800]<= pc_result[225];
                                    8'd226: c_flat[1815:1808]<= pc_result[226];
                                    8'd227: c_flat[1823:1816]<= pc_result[227];
                                    8'd228: c_flat[1831:1824]<= pc_result[228];
                                    8'd229: c_flat[1839:1832]<= pc_result[229];
                                    8'd230: c_flat[1847:1840]<= pc_result[230];
                                    8'd231: c_flat[1855:1848]<= pc_result[231];
                                    8'd232: c_flat[1863:1856]<= pc_result[232];
                                    8'd233: c_flat[1871:1864]<= pc_result[233];
                                    8'd234: c_flat[1879:1872]<= pc_result[234];
                                    8'd235: c_flat[1887:1880]<= pc_result[235];
                                    8'd236: c_flat[1895:1888]<= pc_result[236];
                                    8'd237: c_flat[1903:1896]<= pc_result[237];
                                    8'd238: c_flat[1911:1904]<= pc_result[238];
                                    8'd239: c_flat[1919:1912]<= pc_result[239];
                                    8'd240: c_flat[1927:1920]<= pc_result[240];
                                    8'd241: c_flat[1935:1928]<= pc_result[241];
                                    8'd242: c_flat[1943:1936]<= pc_result[242];
                                    8'd243: c_flat[1951:1944]<= pc_result[243];
                                    8'd244: c_flat[1959:1952]<= pc_result[244];
                                    8'd245: c_flat[1967:1960]<= pc_result[245];
                                    8'd246: c_flat[1975:1968]<= pc_result[246];
                                    8'd247: c_flat[1983:1976]<= pc_result[247];
                                    8'd248: c_flat[1991:1984]<= pc_result[248];
                                    8'd249: c_flat[1999:1992]<= pc_result[249];
                                    8'd250: c_flat[2007:2000]<= pc_result[250];
                                    8'd251: c_flat[2015:2008]<= pc_result[251];
                                    8'd252: c_flat[2023:2016]<= pc_result[252];
                                    8'd253: c_flat[2031:2024]<= pc_result[253];
                                    8'd254: c_flat[2039:2032]<= pc_result[254];
                                    8'd255: c_flat[2047:2040]<= pc_result[255];
                                endcase
                            end
                        end
                        done  <= 1'b1;
                        busy  <= 1'b0;
                        state <= ST_IDLE;
                    end
                end
                default: state <= ST_IDLE;
            endcase
        end
    end

    assign matmul_ok = 1'b1;

endmodule
