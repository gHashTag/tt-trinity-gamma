// SPDX-License-Identifier: Apache-2.0
// dot16_study.v -- STUDY ONLY (not for synthesis): 16-element gf16 dot products
// built from the existing primitives, in shipped and corrected (v2) forms, to
// measure the gf16_mul defect's task-level impact (argmax flips). a/w are packed
// 16x16-bit vectors. See test/impact_task_gf16.py.
`default_nettype none
module dot16 (input wire [255:0] a, input wire [255:0] w, output wire [15:0] result);
    wire [15:0] p0,p1,p2,p3,q0,q1;
    gf16_dot4 d0(.a0(a[15:0]),.a1(a[31:16]),.a2(a[47:32]),.a3(a[63:48]),
                 .b0(w[15:0]),.b1(w[31:16]),.b2(w[47:32]),.b3(w[63:48]),.result(p0));
    gf16_dot4 d1(.a0(a[79:64]),.a1(a[95:80]),.a2(a[111:96]),.a3(a[127:112]),
                 .b0(w[79:64]),.b1(w[95:80]),.b2(w[111:96]),.b3(w[127:112]),.result(p1));
    gf16_dot4 d2(.a0(a[143:128]),.a1(a[159:144]),.a2(a[175:160]),.a3(a[191:176]),
                 .b0(w[143:128]),.b1(w[159:144]),.b2(w[175:160]),.b3(w[191:176]),.result(p2));
    gf16_dot4 d3(.a0(a[207:192]),.a1(a[223:208]),.a2(a[239:224]),.a3(a[255:240]),
                 .b0(w[207:192]),.b1(w[223:208]),.b2(w[239:224]),.b3(w[255:240]),.result(p3));
    gf16_add s0(.a(p0),.b(p1),.result(q0));
    gf16_add s1(.a(p2),.b(p3),.result(q1));
    gf16_add s2(.a(q0),.b(q1),.result(result));
endmodule

module dot16_v2 (input wire [255:0] a, input wire [255:0] w, output wire [15:0] result);
    wire [15:0] p0,p1,p2,p3,q0,q1;
    gf16_dot4_v2 d0(.a0(a[15:0]),.a1(a[31:16]),.a2(a[47:32]),.a3(a[63:48]),
                 .b0(w[15:0]),.b1(w[31:16]),.b2(w[47:32]),.b3(w[63:48]),.result(p0));
    gf16_dot4_v2 d1(.a0(a[79:64]),.a1(a[95:80]),.a2(a[111:96]),.a3(a[127:112]),
                 .b0(w[79:64]),.b1(w[95:80]),.b2(w[111:96]),.b3(w[127:112]),.result(p1));
    gf16_dot4_v2 d2(.a0(a[143:128]),.a1(a[159:144]),.a2(a[175:160]),.a3(a[191:176]),
                 .b0(w[143:128]),.b1(w[159:144]),.b2(w[175:160]),.b3(w[191:176]),.result(p2));
    gf16_dot4_v2 d3(.a0(a[207:192]),.a1(a[223:208]),.a2(a[239:224]),.a3(a[255:240]),
                 .b0(w[207:192]),.b1(w[223:208]),.b2(w[239:224]),.b3(w[255:240]),.result(p3));
    gf16_v2_add s0(.a(p0),.b(p1),.result(q0));
    gf16_v2_add s1(.a(p2),.b(p3),.result(q1));
    gf16_v2_add s2(.a(q0),.b(q1),.result(result));
endmodule
