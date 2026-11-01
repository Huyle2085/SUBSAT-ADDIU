// =============================================================================
// File: rtl/top.sv
// Description: Module cấp cao nhất (Top-Level Core + Memory) cho bộ xử lý
//              RV32I Single-Cycle tích hợp hai lệnh mở rộng SUBSAT & ADDIU.
//              Đảm bảo kết nối đồng bộ độ rộng 3-bit cho cả ImmSel[2:0] và WBSel[2:0].
// =============================================================================

module top
    import isa_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    // Cổng quan sát phục vụ Verification / Waveform / Assertions
    output logic [31:0] dbg_pc,
    output logic [31:0] dbg_inst,
    output logic [31:0] dbg_imm_out,
    output logic [31:0] dbg_alu_out,
    output logic [31:0] dbg_wb_data,
    output imm_sel_e    dbg_imm_sel,
    output wb_sel_e     dbg_wb_sel,
    output logic        dbg_a_sel,
    output logic        dbg_b_sel,
    output logic        dbg_reg_w_en,
    output logic        dbg_pos_ov,
    output logic        dbg_neg_ov,
    output logic        dbg_is_subsat,
    output logic        dbg_is_addiu,
    output logic        dbg_illegal_inst
);

    // Dây kết nối nội bộ
    logic [31:0] pc;
    logic [31:0] inst;
    logic [31:0] imm_out;
    logic [31:0] alu_out;
    logic [31:0] rs2_data;
    logic [31:0] dmem_rdata;
    logic [31:0] wb_data;

    logic        pc_sel;
    imm_sel_e    imm_sel; // 3-bit [2:0]
    logic        reg_w_en;
    logic        br_un;
    logic        a_sel;
    logic        b_sel;
    alu_sel_e    alu_sel;
    logic        mem_rw;
    wb_sel_e     wb_sel;  // 3-bit [2:0]

    logic        br_eq;
    logic        br_lt;
    logic        pos_ov;
    logic        neg_ov;
    logic        is_subsat;
    logic        is_addiu;
    logic        illegal_inst;

    // -------------------------------------------------------------------------
    // 1. Instruction Memory (IMEM)
    // -------------------------------------------------------------------------
    imem u_imem (
        .addr (pc),
        .inst (inst)
    );

    // -------------------------------------------------------------------------
    // 2. Control Logic
    // -------------------------------------------------------------------------
    control_logic u_control_logic (
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

    // -------------------------------------------------------------------------
    // 3. Datapath (bao gồm RegFile, ImmGen, BranchComp, ALU, WB MUX 5:1)
    // -------------------------------------------------------------------------
    datapath u_datapath (
        .clk        (clk),
        .rst_n      (rst_n),
        .pc         (pc),
        .inst       (inst),
        .alu_out    (alu_out),
        .rs2_data   (rs2_data),
        .dmem_rdata (dmem_rdata),
        .pc_sel     (pc_sel),
        .imm_sel    (imm_sel),
        .reg_w_en   (reg_w_en),
        .br_un      (br_un),
        .a_sel      (a_sel),
        .b_sel      (b_sel),
        .alu_sel    (alu_sel),
        .wb_sel     (wb_sel),
        .br_eq      (br_eq),
        .br_lt      (br_lt),
        .pos_ov     (pos_ov),
        .neg_ov     (neg_ov),
        .imm_out    (imm_out),
        .wb_data    (wb_data)
    );

    // -------------------------------------------------------------------------
    // 4. Data Memory (DMEM)
    // -------------------------------------------------------------------------
    dmem u_dmem (
        .clk    (clk),
        .rst_n  (rst_n),
        .mem_rw (mem_rw),
        .addr   (alu_out),
        .data_w (rs2_data),
        .data_r (dmem_rdata)
    );

    // -------------------------------------------------------------------------
    // Gán tín hiệu quan sát (Mục 4.4: đưa is_addiu, imm_out, Asel, Bsel, alu_out,
    // WBSel, wb_data, RegWEn vào quan sát / waveform)
    // -------------------------------------------------------------------------
    assign dbg_pc           = pc;
    assign dbg_inst         = inst;
    assign dbg_imm_out      = imm_out;
    assign dbg_alu_out      = alu_out;
    assign dbg_wb_data      = wb_data;
    assign dbg_imm_sel      = imm_sel;
    assign dbg_wb_sel       = wb_sel;
    assign dbg_a_sel        = a_sel;
    assign dbg_b_sel        = b_sel;
    assign dbg_reg_w_en     = reg_w_en;
    assign dbg_pos_ov       = pos_ov;
    assign dbg_neg_ov       = neg_ov;
    assign dbg_is_subsat    = is_subsat;
    assign dbg_is_addiu     = is_addiu;
    assign dbg_illegal_inst = illegal_inst;

endmodule
