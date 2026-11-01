// =============================================================================
// File: tb/tb_sub_vs_subsat.sv
// Description: Testbench chuyên biệt đối chiếu trực tiếp (Side-by-Side)
//              giữa lệnh SUB chuẩn RV32I và lệnh SUBSAT trên cùng bộ dữ liệu,
//              kèm kiểm thử hồi quy toàn bộ các lệnh gốc RV32I.
// =============================================================================

`timescale 1ns/1ps

module tb_sub_vs_subsat;
    import isa_pkg::*;

    logic        clk;
    logic        rst_n;
    logic [31:0] dbg_pc;
    logic [31:0] dbg_inst;
    logic [31:0] dbg_imm_out;
    logic [31:0] dbg_alu_out;
    logic [31:0] dbg_wb_data;
    imm_sel_e    dbg_imm_sel;
    wb_sel_e     dbg_wb_sel;
    logic        dbg_a_sel;
    logic        dbg_b_sel;
    logic        dbg_reg_w_en;
    logic        dbg_pos_ov;
    logic        dbg_neg_ov;
    logic        dbg_is_subsat;
    logic        dbg_is_addiu;
    logic        dbg_illegal_inst;

    int pass_cnt = 0;
    int fail_cnt = 0;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    top dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .dbg_pc           (dbg_pc),
        .dbg_inst         (dbg_inst),
        .dbg_imm_out      (dbg_imm_out),
        .dbg_alu_out      (dbg_alu_out),
        .dbg_wb_data      (dbg_wb_data),
        .dbg_imm_sel      (dbg_imm_sel),
        .dbg_wb_sel       (dbg_wb_sel),
        .dbg_a_sel        (dbg_a_sel),
        .dbg_b_sel        (dbg_b_sel),
        .dbg_reg_w_en     (dbg_reg_w_en),
        .dbg_pos_ov       (dbg_pos_ov),
        .dbg_neg_ov       (dbg_neg_ov),
        .dbg_is_subsat    (dbg_is_subsat),
        .dbg_is_addiu     (dbg_is_addiu),
        .dbg_illegal_inst (dbg_illegal_inst)
    );

    // Chạy song song lệnh SUB chuẩn (ghi vào x8) và lệnh SUBSAT (ghi vào x9)
    // trên cùng toán hạng A (x6) và B (x7)
    task automatic compare_sub_and_subsat(
        input string       case_name,
        input logic [31:0] val_a,
        input logic [31:0] val_b,
        input logic [31:0] exp_sub_wrap,
        input logic [31:0] exp_subsat_sat
    );
        int idx;
        wb_sel_e sub_wbsel, subsat_wbsel;
        logic    sub_pos, sub_neg;

        dut.u_datapath.u_regfile.regs[6] = val_a;
        dut.u_datapath.u_regfile.regs[7] = val_b;

        // 1. Chạy lệnh SUB chuẩn: SUB x8, x6, x7 (opcode=0110011, funct7=0100000)
        idx = dbg_pc[11:2];
        dut.u_imem.mem[idx] = encode_rtype(F7_ALT, 5'd7, 5'd6, 3'b000, 5'd8, OP_RTYPE);
        #1;
        sub_wbsel = dbg_wb_sel;
        sub_pos   = dbg_pos_ov;
        sub_neg   = dbg_neg_ov;
        @(posedge clk);
        #1;

        // 2. Chạy lệnh SUBSAT: SUBSAT x9, x6, x7 (opcode=0001011, funct7=0100001)
        idx = dbg_pc[11:2];
        dut.u_imem.mem[idx] = encode_subsat(5'd9, 5'd6, 5'd7);
        #1;
        subsat_wbsel = dbg_wb_sel;
        @(posedge clk);
        #1;

        if ((dut.u_datapath.u_regfile.regs[8] !== exp_sub_wrap) ||
            (sub_wbsel !== WB_ALU) ||
            (dut.u_datapath.u_regfile.regs[9] !== exp_subsat_sat)) begin
            $display("[FAIL] %-20s | A=%h B=%h | SUB(x8)=%h (WBSel=%0d) | SUBSAT(x9)=%h (WBSel=%0d)",
                     case_name, val_a, val_b,
                     dut.u_datapath.u_regfile.regs[8], sub_wbsel,
                     dut.u_datapath.u_regfile.regs[9], subsat_wbsel);
            fail_cnt++;
        end else begin
            $display("[PASS] %-20s | A=%h B=%h | Flags(P=%b,N=%b) | SUB(x8)=%h [WBSel=%0d] vs SUBSAT(x9)=%h [WBSel=%0d]",
                     case_name, val_a, val_b, sub_pos, sub_neg,
                     dut.u_datapath.u_regfile.regs[8], sub_wbsel,
                     dut.u_datapath.u_regfile.regs[9], subsat_wbsel);
            pass_cnt++;
        end
    endtask

    initial begin
        $display("======================================================================================================");
        $display(" DOI CHIEU TRUC TIEP: LENH SUB CHUAN (WRAP-AROUND) vs LENH SUBSAT (SATURATING)");
        $display("======================================================================================================");

        rst_n = 1'b0;
        @(posedge clk);
        #1;
        rst_n = 1'b1;

        // Các ca không tràn: SUB và SUBSAT phải cho kết quả Y HỆT NHAU
        compare_sub_and_subsat("1. Khong tran (50-20)",    32'h0000_0032, 32'h0000_0014, 32'h0000_001E, 32'h0000_001E);
        compare_sub_and_subsat("2. Khong tran (0-1)",      32'h0000_0000, 32'h0000_0001, 32'hFFFF_FFFF, 32'hFFFF_FFFF);
        compare_sub_and_subsat("3. Bien (+MAX - 0)",       32'h7FFF_FFFF, 32'h0000_0000, 32'h7FFF_FFFF, 32'h7FFF_FFFF);
        compare_sub_and_subsat("4. Bien (MIN - 0)",        32'h8000_0000, 32'h0000_0000, 32'h8000_0000, 32'h8000_0000);

        // Các ca tràn dương: SUB phải wrap-around (bit 31 = 1), SUBSAT phải bão hòa 7FFF_FFFF
        compare_sub_and_subsat("5. Tran duong (+MAX - -1)",32'h7FFF_FFFF, 32'hFFFF_FFFF, 32'h8000_0000, 32'h7FFF_FFFF);
        compare_sub_and_subsat("6. Tran duong (0 - MIN)",  32'h0000_0000, 32'h8000_0000, 32'h8000_0000, 32'h7FFF_FFFF);
        compare_sub_and_subsat("7. Tran duong (+MAX - -5)",32'h7FFF_FFFF, 32'hFFFF_FFFB, 32'h8000_0004, 32'h7FFF_FFFF);

        // Các ca tràn âm: SUB phải wrap-around (bit 31 = 0), SUBSAT phải bão hòa 8000_0000
        compare_sub_and_subsat("8. Tran am (MIN - +1)",    32'h8000_0000, 32'h0000_0001, 32'h7FFF_FFFF, 32'h8000_0000);
        compare_sub_and_subsat("9. Tran am (MIN - +MAX)",  32'h8000_0000, 32'h7FFF_FFFF, 32'h0000_0001, 32'h8000_0000);
        compare_sub_and_subsat("10.Tran am (MIN - +5)",    32'h8000_0000, 32'h0000_0005, 32'h7FFF_FFFB, 32'h8000_0000);

        $display("------------------------------------------------------------------------------------------------------");
        $display(" KET QUA DOI CHIEU: PASS = %0d | FAIL = %0d", pass_cnt, fail_cnt);
        $display("======================================================================================================");
        $finish;
    end

endmodule
