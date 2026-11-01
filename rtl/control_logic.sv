// =============================================================================
// File: rtl/control_logic.sv
// Description: Khối điều khiển trung tâm (Control Logic) cho RV32I Single-Cycle
//              hỗ trợ hai lệnh tùy chỉnh trong vùng custom-0 (7'b0001011):
//              1) SUBSAT (funct3=3'b000, funct7=7'b0100001) - R-type bão hòa
//              2) ADDIU  (funct3=3'b001, imm[11:0] tùy ý)   - I-type zero-extend
//              Đảm bảo ImmSel[2:0] và WBSel[2:0] đồng bộ 3-bit, không sinh latch.
// =============================================================================

module control_logic
    import isa_pkg::*;
(
    input  logic [31:0] inst,
    input  logic        br_eq,
    input  logic        br_lt,
    input  logic        pos_ov,
    input  logic        neg_ov,

    output logic        pc_sel,       // 0: PC+4, 1: ALU_out
    output imm_sel_e    imm_sel,      // 3-bit chọn định dạng Immediate
    output logic        reg_w_en,     // Cho phép ghi RegFile
    output logic        br_un,        // 1: So sánh nhánh không dấu
    output logic        a_sel,        // 0: rs1_data, 1: PC
    output logic        b_sel,        // 0: rs2_data, 1: imm
    output alu_sel_e    alu_sel,      // Chọn phép toán ALU
    output logic        mem_rw,       // 0: Read/Idle, 1: Write DMEM
    output wb_sel_e     wb_sel,       // 3-bit chọn nguồn Write-Back MUX 5:1
    output logic        is_subsat,    // Cờ nhận diện lệnh SUBSAT hợp lệ
    output logic        is_addiu,     // Cờ nhận diện lệnh ADDIU hợp lệ
    output logic        illegal_inst  // Cờ báo mã lệnh không hợp lệ
);

    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;

    assign opcode = inst[6:0];
    assign funct3 = inst[14:12];
    assign funct7 = inst[31:25];

    // Giải mã ADDIU (I-type custom-0: chỉ kiểm tra opcode & funct3, KHÔNG dùng funct7!)
    assign is_addiu  = (opcode == OP_CUSTOM0) &&
                       (funct3 == ADDIU_F3);

    // Giải mã SUBSAT (R-type custom-0: kiểm tra đủ opcode, funct3, funct7)
    assign is_subsat = (opcode == OP_CUSTOM0) &&
                       (funct3 == SUBSAT_F3) &&
                       (funct7 == SUBSAT_F7);

    always_comb begin
        // ---------------------------------------------------------------------
        // Giá trị mặc định an toàn (không dùng X, không sinh latch, NOP-safe)
        // ---------------------------------------------------------------------
        pc_sel       = 1'b0;
        imm_sel      = IMM_I;
        reg_w_en     = 1'b0;
        br_un        = 1'b0;
        a_sel        = 1'b0;
        b_sel        = 1'b0;
        alu_sel      = ALU_ADD;
        mem_rw       = 1'b0;
        wb_sel       = WB_ALU;
        illegal_inst = 1'b0;

        // ---------------------------------------------------------------------
        // Giải mã lệnh ưu tiên rõ ràng
        // ---------------------------------------------------------------------
        if (is_addiu) begin
            // Lệnh ADDIU rd, rs1, imm12 (Mục 3 & Mục 4.3)
            pc_sel   = 1'b0;
            imm_sel  = IMM_I_ZERO; // 3'b101: Zero-extend {20'b0, inst[31:20]}
            reg_w_en = 1'b1;
            br_un    = 1'b0;
            a_sel    = 1'b0;       // A = R[rs1]
            b_sel    = 1'b1;       // B = imm_out (zero-extended)
            alu_sel  = ALU_ADD;    // Cộng 32-bit modulo 2^32
            mem_rw   = 1'b0;       // Không ghi DMEM
            wb_sel   = WB_ALU;     // 3'b001: Lấy alu_out, không chọn MAX/MIN
        end else if (is_subsat) begin
            // Lệnh SUBSAT rd, rs1, rs2 (Giữ nguyên nhánh SUBSAT đã thiết kế)
            pc_sel   = 1'b0;
            imm_sel  = IMM_I;
            reg_w_en = 1'b1;
            br_un    = 1'b0;
            a_sel    = 1'b0;       // rs1_data
            b_sel    = 1'b0;       // rs2_data
            alu_sel  = ALU_SUB;    // Dùng chung bộ trừ của ALU
            mem_rw   = 1'b0;
            // Chỉ WBSel phụ thuộc vào cờ tràn khi is_subsat = 1
            wb_sel   = pos_ov ? WB_MAX : (neg_ov ? WB_MIN : WB_ALU);
        end else begin
            unique case (opcode)
                // -------------------------------------------------------------
                // R-type chuẩn (ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND)
                // -------------------------------------------------------------
                OP_RTYPE: begin
                    a_sel    = 1'b0;
                    b_sel    = 1'b0;
                    wb_sel   = WB_ALU;
                    reg_w_en = 1'b1;

                    unique case (funct3)
                        3'b000: begin
                            if (funct7 == F7_STD)      alu_sel = ALU_ADD;
                            else if (funct7 == F7_ALT) alu_sel = ALU_SUB;
                            else begin
                                reg_w_en     = 1'b0;
                                illegal_inst = 1'b1;
                            end
                        end
                        3'b001: begin
                            if (funct7 == F7_STD) alu_sel = ALU_SLL;
                            else begin reg_w_en = 1'b0; illegal_inst = 1'b1; end
                        end
                        3'b010: begin
                            if (funct7 == F7_STD) alu_sel = ALU_SLT;
                            else begin reg_w_en = 1'b0; illegal_inst = 1'b1; end
                        end
                        3'b011: begin
                            if (funct7 == F7_STD) alu_sel = ALU_SLTU;
                            else begin reg_w_en = 1'b0; illegal_inst = 1'b1; end
                        end
                        3'b100: begin
                            if (funct7 == F7_STD) alu_sel = ALU_XOR;
                            else begin reg_w_en = 1'b0; illegal_inst = 1'b1; end
                        end
                        3'b101: begin
                            if (funct7 == F7_STD)      alu_sel = ALU_SRL;
                            else if (funct7 == F7_ALT) alu_sel = ALU_SRA;
                            else begin reg_w_en = 1'b0; illegal_inst = 1'b1; end
                        end
                        3'b110: begin
                            if (funct7 == F7_STD) alu_sel = ALU_OR;
                            else begin reg_w_en = 1'b0; illegal_inst = 1'b1; end
                        end
                        3'b111: begin
                            if (funct7 == F7_STD) alu_sel = ALU_AND;
                            else begin reg_w_en = 1'b0; illegal_inst = 1'b1; end
                        end
                        default: begin
                            reg_w_en     = 1'b0;
                            illegal_inst = 1'b1;
                        end
                    endcase
                end

                // -------------------------------------------------------------
                // I-type ALU chuẩn (ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI)
                // -------------------------------------------------------------
                OP_IMM: begin
                    imm_sel  = IMM_I; // Sign-extend
                    a_sel    = 1'b0;
                    b_sel    = 1'b1;
                    wb_sel   = WB_ALU;
                    reg_w_en = 1'b1;

                    unique case (funct3)
                        3'b000: alu_sel = ALU_ADD;
                        3'b010: alu_sel = ALU_SLT;
                        3'b011: alu_sel = ALU_SLTU;
                        3'b100: alu_sel = ALU_XOR;
                        3'b110: alu_sel = ALU_OR;
                        3'b111: alu_sel = ALU_AND;
                        3'b001: begin
                            if (funct7 == F7_STD) alu_sel = ALU_SLL;
                            else begin reg_w_en = 1'b0; illegal_inst = 1'b1; end
                        end
                        3'b101: begin
                            if (funct7 == F7_STD)      alu_sel = ALU_SRL;
                            else if (funct7 == F7_ALT) alu_sel = ALU_SRA;
                            else begin reg_w_en = 1'b0; illegal_inst = 1'b1; end
                        end
                        default: begin
                            reg_w_en     = 1'b0;
                            illegal_inst = 1'b1;
                        end
                    endcase
                end

                // -------------------------------------------------------------
                // LOAD (LW: funct3 = 3'b010)
                // -------------------------------------------------------------
                OP_LOAD: begin
                    if (funct3 == 3'b010) begin
                        imm_sel  = IMM_I;
                        a_sel    = 1'b0;
                        b_sel    = 1'b1;
                        alu_sel  = ALU_ADD;
                        mem_rw   = 1'b0;
                        wb_sel   = WB_MEM;
                        reg_w_en = 1'b1;
                    end else begin
                        illegal_inst = 1'b1;
                    end
                end

                // -------------------------------------------------------------
                // STORE (SW: funct3 = 3'b010)
                // -------------------------------------------------------------
                OP_STORE: begin
                    if (funct3 == 3'b010) begin
                        imm_sel  = IMM_S;
                        a_sel    = 1'b0;
                        b_sel    = 1'b1;
                        alu_sel  = ALU_ADD;
                        mem_rw   = 1'b1;
                        reg_w_en = 1'b0;
                    end else begin
                        illegal_inst = 1'b1;
                    end
                end

                // -------------------------------------------------------------
                // BRANCH (BEQ, BNE, BLT, BGE, BLTU, BGEU)
                // -------------------------------------------------------------
                OP_BRANCH: begin
                    imm_sel  = IMM_B;
                    a_sel    = 1'b1; // PC
                    b_sel    = 1'b1; // imm
                    alu_sel  = ALU_ADD;
                    reg_w_en = 1'b0;
                    br_un    = (funct3 == 3'b110) || (funct3 == 3'b111);

                    unique case (funct3)
                        3'b000: pc_sel =  br_eq; // BEQ
                        3'b001: pc_sel = ~br_eq; // BNE
                        3'b100: pc_sel =  br_lt; // BLT
                        3'b101: pc_sel = ~br_lt; // BGE
                        3'b110: pc_sel =  br_lt; // BLTU
                        3'b111: pc_sel = ~br_lt; // BGEU
                        default: begin
                            pc_sel       = 1'b0;
                            illegal_inst = 1'b1;
                        end
                    endcase
                end

                // -------------------------------------------------------------
                // JAL
                // -------------------------------------------------------------
                OP_JAL: begin
                    pc_sel   = 1'b1;
                    imm_sel  = IMM_J;
                    a_sel    = 1'b1; // PC
                    b_sel    = 1'b1; // imm
                    alu_sel  = ALU_ADD;
                    wb_sel   = WB_PC4;
                    reg_w_en = 1'b1;
                end

                // -------------------------------------------------------------
                // JALR
                // -------------------------------------------------------------
                OP_JALR: begin
                    if (funct3 == 3'b000) begin
                        pc_sel   = 1'b1;
                        imm_sel  = IMM_I;
                        a_sel    = 1'b0; // rs1
                        b_sel    = 1'b1; // imm
                        alu_sel  = ALU_ADD;
                        wb_sel   = WB_PC4;
                        reg_w_en = 1'b1;
                    end else begin
                        illegal_inst = 1'b1;
                    end
                end

                // -------------------------------------------------------------
                // LUI
                // -------------------------------------------------------------
                OP_LUI: begin
                    imm_sel  = IMM_U;
                    a_sel    = 1'b0;
                    b_sel    = 1'b1;
                    alu_sel  = ALU_PASS_B;
                    wb_sel   = WB_ALU;
                    reg_w_en = 1'b1;
                end

                // -------------------------------------------------------------
                // AUIPC
                // -------------------------------------------------------------
                OP_AUIPC: begin
                    imm_sel  = IMM_U;
                    a_sel    = 1'b1; // PC
                    b_sel    = 1'b1; // imm
                    alu_sel  = ALU_ADD;
                    wb_sel   = WB_ALU;
                    reg_w_en = 1'b1;
                end

                // -------------------------------------------------------------
                // Các lệnh không hợp lệ (bao gồm OP_CUSTOM0 với funct3 chưa dùng)
                // -------------------------------------------------------------
                default: begin
                    pc_sel       = 1'b0;
                    reg_w_en     = 1'b0;
                    mem_rw       = 1'b0;
                    wb_sel       = WB_ALU;
                    illegal_inst = 1'b1;
                end
            endcase
        end
    end

endmodule
