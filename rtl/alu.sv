// =============================================================================
// File: rtl/alu.sv
// Description: Khối ALU 32-bit cho RV32I hỗ trợ phát hiện tràn có dấu
//              (pos_ov, neg_ov) tại nhánh ALU_SUB phục vụ lệnh SUBSAT.
// =============================================================================

module alu
    import isa_pkg::*;
(
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  alu_sel_e    alu_sel,
    output logic [31:0] alu_out,
    output logic        pos_ov,
    output logic        neg_ov
);

    logic [31:0] sub_res;
    assign sub_res = a - b;

    always_comb begin
        // Default an toàn để tránh suy diễn latch và không phát sinh X
        alu_out = 32'h0000_0000;
        pos_ov  = 1'b0;
        neg_ov  = 1'b0;

        unique case (alu_sel)
            ALU_ADD: begin
                alu_out = a + b;
            end

            ALU_SUB: begin
                alu_out = sub_res;
                // Toán học phát hiện tràn cho phép trừ có dấu S = A - B (Mục 4.1):
                // - Tràn dương (PosOv): A >= 0 (A[31]=0), B < 0 (B[31]=1), S < 0 (S[31]=1)
                // - Tràn âm    (NegOv): A < 0  (A[31]=1), B >= 0 (B[31]=0), S >= 0 (S[31]=0)
                pos_ov  = (~a[31]) &   b[31]  &   sub_res[31];
                neg_ov  =   a[31]  & (~b[31]) & (~sub_res[31]);
            end

            ALU_SLL: begin
                alu_out = a << b[4:0];
            end

            ALU_SLT: begin
                alu_out = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
            end

            ALU_SLTU: begin
                alu_out = (a < b) ? 32'd1 : 32'd0;
            end

            ALU_XOR: begin
                alu_out = a ^ b;
            end

            ALU_SRL: begin
                alu_out = a >> b[4:0];
            end

            ALU_SRA: begin
                alu_out = $unsigned($signed(a) >>> b[4:0]);
            end

            ALU_OR: begin
                alu_out = a | b;
            end

            ALU_AND: begin
                alu_out = a & b;
            end

            ALU_PASS_B: begin
                alu_out = b;
            end

            default: begin
                alu_out = 32'h0000_0000;
                pos_ov  = 1'b0;
                neg_ov  = 1'b0;
            end
        endcase
    end

endmodule
