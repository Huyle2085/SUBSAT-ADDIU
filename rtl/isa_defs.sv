// =============================================================================
// File: rtl/isa_defs.sv
// Description: Package chứa hằng số kiến trúc RV32I, mã hóa lệnh tùy chỉnh
//              SUBSAT & ADDIU (custom-0), ALUSel, WBSel (3-bit) và ImmSel (3-bit).
// =============================================================================

`ifndef ISA_DEFS_SV
`define ISA_DEFS_SV

package isa_pkg;

    // Độ rộng dữ liệu chuẩn RV32I
    parameter int XLEN = 32;

    // Hằng số bão hòa có dấu 32-bit (Signed 32-bit Saturation Constants)
    localparam logic [31:0] INT32_MAX = 32'h7FFF_FFFF; // +2147483647
    localparam logic [31:0] INT32_MIN = 32'h8000_0000; // -2147483648

    // -------------------------------------------------------------------------
    // Major Opcodes [6:0]
    // -------------------------------------------------------------------------
    localparam logic [6:0] OP_CUSTOM0 = 7'b0001011; // 0x0B: vùng custom-0 cho SUBSAT & ADDIU

    typedef enum logic [6:0] {
        OP_LOAD   = 7'b0000011, // 0x03: LB, LH, LW, LBU, LHU
        SUBSAT_OP = 7'b0001011, // 0x0B: custom-0 (dành cho SUBSAT & ADDIU)
        OP_IMM    = 7'b0010011, // 0x13: ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI
        OP_AUIPC  = 7'b0010111, // 0x17: AUIPC
        OP_STORE  = 7'b0100011, // 0x23: SB, SH, SW
        OP_RTYPE  = 7'b0110011, // 0x33: ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND
        OP_LUI    = 7'b0110111, // 0x37: LUI
        OP_BRANCH = 7'b1100011, // 0x63: BEQ, BNE, BLT, BGE, BLTU, BGEU
        OP_JALR   = 7'b1100111, // 0x67: JALR
        OP_JAL    = 7'b1101111  // 0x6F: JAL
    } opcode_e;

    // -------------------------------------------------------------------------
    // Định nghĩa trường funct3 và funct7 của lệnh SUBSAT & ADDIU (custom-0)
    // -------------------------------------------------------------------------
    localparam logic [2:0] SUBSAT_F3 = 3'b000;
    localparam logic [6:0] SUBSAT_F7 = 7'b0100001; // 0x21 (R-type custom-0)
    localparam logic [2:0] ADDIU_F3  = 3'b001;     // I-type custom-0 (không dùng funct7)

    // Định nghĩa funct7 chuẩn cho R-type
    localparam logic [6:0] F7_STD = 7'b0000000; // ADD, SRL, ...
    localparam logic [6:0] F7_ALT = 7'b0100000; // SUB, SRA

    // -------------------------------------------------------------------------
    // Mã điều khiển ALU (ALUSel)
    // -------------------------------------------------------------------------
    typedef enum logic [3:0] {
        ALU_ADD    = 4'b0000,
        ALU_SUB    = 4'b0001,
        ALU_SLL    = 4'b0010,
        ALU_SLT    = 4'b0011,
        ALU_SLTU   = 4'b0100,
        ALU_XOR    = 4'b0101,
        ALU_SRL    = 4'b0110,
        ALU_SRA    = 4'b0111,
        ALU_OR     = 4'b1000,
        ALU_AND    = 4'b1001,
        ALU_PASS_B = 4'b1010
    } alu_sel_e;

    // -------------------------------------------------------------------------
    // Mã điều khiển Write-Back MUX 5:1 (WBSel[2:0] - 3-bit)
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {
        WB_MEM = 3'b000, // 0: dataR từ DMEM (LOAD)
        WB_ALU = 3'b001, // 1: alu_out (ADD/SUB/ADDI/ADDIU/logic, SUBSAT không tràn)
        WB_PC4 = 3'b010, // 2: PC + 4 (JAL/JALR)
        WB_MAX = 3'b011, // 3: 32'h7FFF_FFFF (SUBSAT tràn dương)
        WB_MIN = 3'b100  // 4: 32'h8000_0000 (SUBSAT tràn âm)
    } wb_sel_e;

    // -------------------------------------------------------------------------
    // Mã điều khiển chọn kiểu mở rộng Immediate (ImmSel[2:0] - 3-bit, Mục 2.2)
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {
        IMM_I      = 3'b000, // IMM_I_SIGN: {{20{inst[31]}}, inst[31:20]} (ADDI/LW/JALR)
        IMM_S      = 3'b001, // {{20{inst[31]}}, inst[31:25], inst[11:7]} (SW)
        IMM_B      = 3'b010, // {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0}
        IMM_U      = 3'b011, // {inst[31:12], 12'b0} (LUI/AUIPC)
        IMM_J      = 3'b100, // {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0}
        IMM_I_ZERO = 3'b101  // {20'b0, inst[31:20]} (ADDIU zero-extend 12-bit immediate)
    } imm_sel_e;

    localparam imm_sel_e IMM_I_SIGN = IMM_I;

    // -------------------------------------------------------------------------
    // Helper Functions tạo mã máy cho R-type, SUBSAT và ADDIU
    // -------------------------------------------------------------------------
    function automatic logic [31:0] encode_rtype(
        input logic [6:0] funct7,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [4:0] rd,
        input logic [6:0] opcode
    );
        return {funct7, rs2, rs1, funct3, rd, opcode};
    endfunction

    function automatic logic [31:0] encode_subsat(
        input logic [4:0] rd,
        input logic [4:0] rs1,
        input logic [4:0] rs2
    );
        return {SUBSAT_F7, rs2, rs1, SUBSAT_F3, rd, SUBSAT_OP};
    endfunction

    // Hàm tạo mã máy I-type cho ADDIU (Mục 5.2):
    // enc_addiu(5, 6, 12'hFFF) = 32'hFFF3_128B
    function automatic logic [31:0] enc_addiu(
        input logic [4:0]  rd,
        input logic [4:0]  rs1,
        input logic [11:0] imm12
    );
        return {imm12, rs1, ADDIU_F3, rd, OP_CUSTOM0};
    endfunction

    function automatic logic [31:0] encode_addiu(
        input logic [4:0]  rd,
        input logic [4:0]  rs1,
        input logic [11:0] imm12
    );
        return enc_addiu(rd, rs1, imm12);
    endfunction

endpackage

`endif // ISA_DEFS_SV
