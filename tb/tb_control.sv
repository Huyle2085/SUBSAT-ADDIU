// =============================================================================
// File: tb/tb_control.sv
// Description: Unit Testbench cho module Control Logic (hỗ trợ SUBSAT & ADDIU).
//              Kiểm tra giải mã ADDIU (ImmSel=IMM_I_ZERO=3'b101, WBSel=WB_ALU),
//              SUBSAT (3 nhánh WBSel), lệnh SUB/ADDI chuẩn và mã lệnh sai (U14/T14).
// =============================================================================

`timescale 1ns/1ps

module tb_control;
    import isa_pkg::*;

    logic [31:0] inst;
    logic        br_eq;
    logic        br_lt;
    logic        pos_ov;
    logic        neg_ov;

    logic        pc_sel;
    imm_sel_e    imm_sel;
    logic        reg_w_en;
    logic        br_un;
    logic        a_sel;
    logic        b_sel;
    alu_sel_e    alu_sel;
    logic        mem_rw;
    wb_sel_e     wb_sel;
    logic        is_subsat;
    logic        is_addiu;
    logic        illegal_inst;

    int pass_cnt = 0;
    int fail_cnt = 0;

    control_logic dut (
        .inst         (inst),
        .br_eq        (br_eq),
        .br_lt        (br_lt),
        .pos_ov       (pos_ov),
        .neg_ov       (neg_ov),
        .pc_sel       (pc_sel),
        .imm_sel      (imm_sel),
        .reg_w_en     (reg_w_en),
        .br_un        (br_un),
        .a_sel        (a_sel),
        .b_sel        (b_sel),
        .alu_sel      (alu_sel),
        .mem_rw       (mem_rw),
        .wb_sel       (wb_sel),
        .is_subsat    (is_subsat),
        .is_addiu     (is_addiu),
        .illegal_inst (illegal_inst)
    );

    task automatic check_ctrl(
        input string       name,
        input logic [31:0] in_inst,
        input logic        in_pos_ov,
        input logic        in_neg_ov,
        input logic        exp_is_subsat,
        input logic        exp_is_addiu,
        input imm_sel_e    exp_imm_sel,
        input logic        exp_reg_w_en,
        input alu_sel_e    exp_alu_sel,
        input wb_sel_e     exp_wb_sel,
        input logic        exp_illegal
    );
        inst   = in_inst;
        pos_ov = in_pos_ov;
        neg_ov = in_neg_ov;
        br_eq  = 1'b0;
        br_lt  = 1'b0;
        #1;

        if (is_addiu && is_subsat) begin
            $display("[FAIL] %s: Mutex violation! is_addiu && is_subsat == 1", name);
            fail_cnt++;
        end else if ((is_subsat    !== exp_is_subsat) ||
                     (is_addiu     !== exp_is_addiu)  ||
                     (imm_sel      !== exp_imm_sel)   ||
                     (reg_w_en     !== exp_reg_w_en)  ||
                     (alu_sel      !== exp_alu_sel)   ||
                     (wb_sel       !== exp_wb_sel)    ||
                     (illegal_inst !== exp_illegal)) begin
            $display("[FAIL] %s: inst=%h | Got subsat=%b addiu=%b imm=%0d regW=%b alu=%0d wb=%0d ill=%b",
                     name, in_inst, is_subsat, is_addiu, imm_sel, reg_w_en, alu_sel, wb_sel, illegal_inst);
            fail_cnt++;
        end else begin
            pass_cnt++;
        end
    endtask

    initial begin
        $display("=================================================================");
        $display(" BAT DAU UNIT TEST: tb_control (SUBSAT + ADDIU)");
        $display("=================================================================");

        // 1. ADDIU x5, x6, 0xFFF (32'hFFF3_128B) trong cả 3 trạng thái cờ tràn (phải luôn chọn WB_ALU & IMM_I_ZERO)
        check_ctrl("ADDIU_FFF_NoOv",   enc_addiu(5'd5, 5'd6, 12'hFFF), 1'b0, 1'b0, 1'b0, 1'b1, IMM_I_ZERO, 1'b1, ALU_ADD, WB_ALU, 1'b0);
        check_ctrl("ADDIU_FFF_PosOv",  enc_addiu(5'd5, 5'd6, 12'hFFF), 1'b1, 1'b0, 1'b0, 1'b1, IMM_I_ZERO, 1'b1, ALU_ADD, WB_ALU, 1'b0);
        check_ctrl("ADDIU_FFF_NegOv",  enc_addiu(5'd5, 5'd6, 12'hFFF), 1'b0, 1'b1, 1'b0, 1'b1, IMM_I_ZERO, 1'b1, ALU_ADD, WB_ALU, 1'b0);
        // ADDIU với inst[31:25] trùng SUBSAT_F7 (0100001) vẫn phải giải mã là ADDIU!
        check_ctrl("ADDIU_Imm427",     enc_addiu(5'd5, 5'd6, 12'h427), 1'b1, 1'b0, 1'b0, 1'b1, IMM_I_ZERO, 1'b1, ALU_ADD, WB_ALU, 1'b0);

        // 2. SUBSAT x5, x6, x7 (32'h4273_028B) trong 3 trạng thái cờ tràn
        check_ctrl("SUBSAT_NoOv",      encode_subsat(5'd5, 5'd6, 5'd7), 1'b0, 1'b0, 1'b1, 1'b0, IMM_I, 1'b1, ALU_SUB, WB_ALU, 1'b0);
        check_ctrl("SUBSAT_PosOv",     encode_subsat(5'd5, 5'd6, 5'd7), 1'b1, 1'b0, 1'b1, 1'b0, IMM_I, 1'b1, ALU_SUB, WB_MAX, 1'b0);
        check_ctrl("SUBSAT_NegOv",     encode_subsat(5'd5, 5'd6, 5'd7), 1'b0, 1'b1, 1'b1, 1'b0, IMM_I, 1'b1, ALU_SUB, WB_MIN, 1'b0);

        // 3. SUB thường & ADDI chuẩn
        check_ctrl("SUB_Std_PosOv",    encode_rtype(F7_ALT, 5'd7, 5'd6, 3'b000, 5'd5, OP_RTYPE), 1'b1, 1'b0, 1'b0, 1'b0, IMM_I, 1'b1, ALU_SUB, WB_ALU, 1'b0);
        check_ctrl("ADDI_Std",         {12'hFFF, 5'd6, 3'b000, 5'd5, OP_IMM},                    1'b1, 1'b0, 1'b0, 1'b0, IMM_I, 1'b1, ALU_ADD, WB_ALU, 1'b0);

        // 4. LW & JAL
        check_ctrl("LW_Std",           {12'd4, 5'd1, 3'b010, 5'd2, OP_LOAD}, 1'b0, 1'b0, 1'b0, 1'b0, IMM_I, 1'b1, ALU_ADD, WB_MEM, 1'b0);
        check_ctrl("JAL_Std",          {20'd8, 5'd1, OP_JAL},                1'b0, 1'b0, 1'b0, 1'b0, IMM_J, 1'b1, ALU_ADD, WB_PC4, 1'b0);

        // 5. Mã hóa sai (U14 / T14): custom-0 với funct3 chưa dùng (010..111) hoặc funct3=000 nhưng sai funct7
        check_ctrl("BAD_Custom0_F3_2", encode_rtype(SUBSAT_F7, 5'd7, 5'd6, 3'b010,    5'd5, SUBSAT_OP), 1'b1, 1'b0, 1'b0, 1'b0, IMM_I, 1'b0, ALU_ADD, WB_ALU, 1'b1);
        check_ctrl("BAD_Custom0_F7",   encode_rtype(F7_ALT,    5'd7, 5'd6, SUBSAT_F3, 5'd5, SUBSAT_OP), 1'b1, 1'b0, 1'b0, 1'b0, IMM_I, 1'b0, ALU_ADD, WB_ALU, 1'b1);
        check_ctrl("BAD_RType_F7",     encode_rtype(SUBSAT_F7, 5'd7, 5'd6, SUBSAT_F3, 5'd5, OP_RTYPE),  1'b1, 1'b0, 1'b0, 1'b0, IMM_I, 1'b0, ALU_ADD, WB_ALU, 1'b1);

        $display("-----------------------------------------------------------------");
        $display(" KET QUA tb_control: PASS = %0d | FAIL = %0d", pass_cnt, fail_cnt);
        $display("=================================================================");
        if (fail_cnt == 0)
            $display(" >>> tb_control PASSED <<<");
        else
            $display(" >>> tb_control FAILED <<<");
        $finish;
    end

endmodule
