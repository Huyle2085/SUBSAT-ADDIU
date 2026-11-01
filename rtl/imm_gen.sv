// =============================================================================
// File: rtl/imm_gen.sv
// Description: Bộ tạo số tức thời (Immediate Generator) cho RV32I + ADDIU.
//              Hỗ trợ 6 chế độ ImmSel[2:0] (3-bit):
//              - IMM_I (000)      : Sign-extend 12-bit inst[31:20] (ADDI/LW/JALR)
//              - IMM_S (001)      : Sign-extend 12-bit S-type (SW)
//              - IMM_B (010)      : Sign-extend 13-bit B-type (Branch)
//              - IMM_U (011)      : Upper 20-bit U-type (LUI/AUIPC)
//              - IMM_J (100)      : Sign-extend 21-bit J-type (JAL)
//              - IMM_I_ZERO (101) : Zero-extend 12-bit {20'b0, inst[31:20]} (ADDIU)
// =============================================================================

module imm_gen
    import isa_pkg::*;
(
    input  logic [31:0] inst,
    input  imm_sel_e    imm_sel,
    output logic [31:0] imm_out
);

    always_comb begin
        imm_out = 32'h0000_0000;

        unique case (imm_sel)
            IMM_I:      imm_out = {{20{inst[31]}}, inst[31:20]};
            IMM_S:      imm_out = {{20{inst[31]}}, inst[31:25], inst[11:7]};
            IMM_B:      imm_out = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
            IMM_U:      imm_out = {inst[31:12], 12'h000};
            IMM_J:      imm_out = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};
            IMM_I_ZERO: imm_out = {20'b0, inst[31:20]};
            default:    imm_out = 32'h0000_0000;
        endcase
    end

endmodule
