// =============================================================================
// File: rtl/datapath.sv
// Description: Datapath RV32I Single-Cycle tích hợp:
//              - ImmGen 6 chế độ (ImmSel[2:0] 3-bit, có IMM_I_ZERO cho ADDIU)
//              - Write-Back MUX 5:1 (WBSel[2:0] 3-bit, có WB_MAX/WB_MIN cho SUBSAT)
//              - Đường truyền cờ pos_ov/neg_ov từ ALU và xuất imm_out phục vụ quan sát.
// =============================================================================

module datapath
    import isa_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    // Giao tiếp bộ nhớ lệnh & dữ liệu
    output logic [31:0] pc,
    input  logic [31:0] inst,
    output logic [31:0] alu_out,
    output logic [31:0] rs2_data,
    input  logic [31:0] dmem_rdata,

    // Tín hiệu điều khiển từ Control Logic (ImmSel & WBSel đều đủ 3-bit [2:0])
    input  logic        pc_sel,
    input  imm_sel_e    imm_sel,
    input  logic        reg_w_en,
    input  logic        br_un,
    input  logic        a_sel,
    input  logic        b_sel,
    input  alu_sel_e    alu_sel,
    input  wb_sel_e     wb_sel,

    // Cờ trạng thái gửi về Control Logic
    output logic        br_eq,
    output logic        br_lt,
    output logic        pos_ov,
    output logic        neg_ov,

    // Cổng quan sát kết quả Immediate & Write-Back phục vụ kiểm thử / waveform
    output logic [31:0] imm_out,
    output logic [31:0] wb_data
);

    // Tín hiệu nội bộ
    logic [31:0] pc_next;
    logic [31:0] pc_plus4;
    logic [31:0] rs1_data;
    logic [31:0] imm_ext;
    logic [31:0] alu_in_a;
    logic [31:0] alu_in_b;

    // -------------------------------------------------------------------------
    // 1. Program Counter (PC) Logic
    // -------------------------------------------------------------------------
    assign pc_plus4 = pc + 32'd4;
    assign pc_next  = pc_sel ? alu_out : pc_plus4;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= 32'h0000_0000;
        end else begin
            pc <= pc_next;
        end
    end

    // -------------------------------------------------------------------------
    // 2. Register File (32 x 32-bit, x0 cứng bằng 0)
    // -------------------------------------------------------------------------
    regfile u_regfile (
        .clk      (clk),
        .rst_n    (rst_n),
        .reg_w_en (reg_w_en),
        .rs1_addr (inst[19:15]),
        .rs2_addr (inst[24:20]),
        .rd_addr  (inst[11:7]),
        .wb_data  (wb_data),
        .rs1_data (rs1_data),
        .rs2_data (rs2_data)
    );

    // -------------------------------------------------------------------------
    // 3. Immediate Generator (nhận đủ 32-bit inst[31:0] và 3-bit imm_sel[2:0])
    // -------------------------------------------------------------------------
    imm_gen u_imm_gen (
        .inst    (inst),
        .imm_sel (imm_sel),
        .imm_out (imm_ext)
    );

    assign imm_out = imm_ext;

    // -------------------------------------------------------------------------
    // 4. Branch Comparator
    // -------------------------------------------------------------------------
    branch_comp u_branch_comp (
        .data_r1 (rs1_data),
        .data_r2 (rs2_data),
        .br_un   (br_un),
        .br_eq   (br_eq),
        .br_lt   (br_lt)
    );

    // -------------------------------------------------------------------------
    // 5. ALU Input MUXes & ALU (xuất cờ pos_ov, neg_ov)
    // -------------------------------------------------------------------------
    assign alu_in_a = a_sel ? pc      : rs1_data;
    assign alu_in_b = b_sel ? imm_ext : rs2_data;

    alu u_alu (
        .a       (alu_in_a),
        .b       (alu_in_b),
        .alu_sel (alu_sel),
        .alu_out (alu_out),
        .pos_ov  (pos_ov),
        .neg_ov  (neg_ov)
    );

    // -------------------------------------------------------------------------
    // 6. Write-Back MUX 5:1 (WBSel[2:0])
    //    - 3'b000 (WB_MEM): dataR (DMEM)      -> LOAD
    //    - 3'b001 (WB_ALU): alu_out           -> ADD/SUB/ADDI/ADDIU/logic, SUBSAT không tràn
    //    - 3'b010 (WB_PC4): PC + 4            -> JAL/JALR
    //    - 3'b011 (WB_MAX): 32'h7FFF_FFFF     -> SUBSAT tràn dương
    //    - 3'b100 (WB_MIN): 32'h8000_0000     -> SUBSAT tràn âm
    //    - 101-111        : Mặc định an toàn -> alu_out
    // -------------------------------------------------------------------------
    always_comb begin
        wb_data = alu_out;
        unique case (wb_sel)
            WB_MEM:  wb_data = dmem_rdata;
            WB_ALU:  wb_data = alu_out;
            WB_PC4:  wb_data = pc_plus4;
            WB_MAX:  wb_data = INT32_MAX;
            WB_MIN:  wb_data = INT32_MIN;
            default: wb_data = alu_out;
        endcase
    end

endmodule
