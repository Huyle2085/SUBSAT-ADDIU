// =============================================================================
// File: tb/tb_addi_vs_addiu.sv
// Description: Testbench chuyên biệt đối chiếu trực tiếp (Side-by-Side)
//              giữa lệnh ADDI chuẩn RV32I (Sign-Extend) và lệnh tùy chỉnh
//              ADDIU (Zero-Extend) trên cùng bộ dữ liệu (rs1, imm12),
//              kèm kiểm thử tự động 1000 vector ngẫu nhiên.
// =============================================================================

`timescale 1ns/1ps

module tb_addi_vs_addiu;
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

    // Hàm tạo mã máy cho lệnh ADDI chuẩn RV32I (opcode = OP_IMM = 7'b0010011, funct3 = 3'b000)
    function automatic logic [31:0] enc_addi(
        input logic [4:0]  rd,
        input logic [4:0]  rs1,
        input logic [11:0] imm12
    );
        return {imm12, rs1, 3'b000, rd, OP_IMM};
    endfunction

    // Golden Model cho ADDI chuẩn (Sign-Extend 12-bit immediate)
    function automatic logic [31:0] addi_ref(
        input logic [31:0] rs1_val,
        input logic [11:0] imm12
    );
        logic [31:0] imm_sext;
        imm_sext = {{20{imm12[11]}}, imm12};
        return rs1_val + imm_sext;
    endfunction

    // Golden Model cho ADDIU tùy chỉnh (Zero-Extend 12-bit immediate)
    function automatic logic [31:0] addiu_ref(
        input logic [31:0] rs1_val,
        input logic [11:0] imm12
    );
        logic [31:0] imm_zext;
        imm_zext = {20'b0, imm12};
        return rs1_val + imm_zext;
    endfunction

    task automatic reset_core();
        rst_n = 1'b0;
        @(posedge clk);
        #1;
        rst_n = 1'b1;
    endtask

    // Chạy song song lệnh ADDI chuẩn (ghi vào x8) và lệnh ADDIU (ghi vào x9)
    // trên cùng toán hạng nguồn rs1 (x6) và hằng số imm12
    task automatic compare_addi_and_addiu(
        input string       case_name,
        input logic [31:0] val_rs1,
        input logic [11:0] imm12,
        input logic [31:0] exp_addi_sext,
        input logic [31:0] exp_addiu_zext
    );
        int          idx;
        imm_sel_e    addi_immsel, addiu_immsel;
        wb_sel_e     addi_wbsel,  addiu_wbsel;
        logic [31:0] addi_immout, addiu_immout;
        logic        addi_flag,   addiu_flag;
        logic [31:0] exp_diff;

        dut.u_datapath.u_regfile.regs[6] = val_rs1;

        // 1. Chạy lệnh ADDI chuẩn: ADDI x8, x6, imm12 (opcode=0010011, funct3=000)
        idx = dbg_pc[11:2];
        dut.u_imem.mem[idx] = enc_addi(5'd8, 5'd6, imm12);
        #1;
        addi_immsel = dbg_imm_sel;
        addi_immout = dbg_imm_out;
        addi_wbsel  = dbg_wb_sel;
        addi_flag   = dbg_is_addiu;
        @(posedge clk);
        #1;

        // 2. Chạy lệnh ADDIU tùy chỉnh: ADDIU x9, x6, imm12 (opcode=0001011, funct3=001)
        idx = dbg_pc[11:2];
        dut.u_imem.mem[idx] = enc_addiu(5'd9, 5'd6, imm12);
        #1;
        addiu_immsel = dbg_imm_sel;
        addiu_immout = dbg_imm_out;
        addiu_wbsel  = dbg_wb_sel;
        addiu_flag   = dbg_is_addiu;
        @(posedge clk);
        #1;

        // Khi imm12[11]=0, hai lệnh phải cho kết quả bằng nhau (diff = 0).
        // Khi imm12[11]=1, ADDIU lớn hơn ADDI đúng 2^12 = 4096 (32'h0000_1000) modulo 2^32.
        exp_diff = imm12[11] ? 32'h0000_1000 : 32'h0000_0000;

        if ((dut.u_datapath.u_regfile.regs[8] !== exp_addi_sext)  ||
            (dut.u_datapath.u_regfile.regs[9] !== exp_addiu_zext) ||
            (addi_immsel  !== IMM_I)                              ||
            (addiu_immsel !== IMM_I_ZERO)                         ||
            (addi_immout  !== {{20{imm12[11]}}, imm12})           ||
            (addiu_immout !== {20'b0, imm12})                     ||
            (addi_wbsel   !== WB_ALU)                             ||
            (addiu_wbsel  !== WB_ALU)                             ||
            (addi_flag    !== 1'b0)                               ||
            (addiu_flag   !== 1'b1)                               ||
            ((dut.u_datapath.u_regfile.regs[9] - dut.u_datapath.u_regfile.regs[8]) !== exp_diff)) begin
            $display("[FAIL] %-28s | rs1=%08h imm12=%03h | ADDI(x8)=%08h (imm=%08h, ImmSel=%0d) | ADDIU(x9)=%08h (imm=%08h, ImmSel=%0d)",
                     case_name, val_rs1, imm12,
                     dut.u_datapath.u_regfile.regs[8], addi_immout, addi_immsel,
                     dut.u_datapath.u_regfile.regs[9], addiu_immout, addiu_immsel);
            fail_cnt++;
        end else begin
            $display("[PASS] %-28s | rs1=%08h imm=%03h (b11=%b) | ADDI(x8)=%08h [ImmSel=%0d] vs ADDIU(x9)=%08h [ImmSel=%0d]",
                     case_name, val_rs1, imm12, imm12[11],
                     dut.u_datapath.u_regfile.regs[8], addi_immsel,
                     dut.u_datapath.u_regfile.regs[9], addiu_immsel);
            pass_cnt++;
        end
    endtask

    initial begin
        $display("================================================================================================================");
        $display(" DOI CHIEU TRUC TIEP: LENH ADDI CHUAN (SIGN-EXTEND) vs LENH ADDIU TUY CHINH (ZERO-EXTEND)");
        $display("================================================================================================================");

        reset_core();

        // ---------------------------------------------------------------------
        // PHẦN A: CÁC CA DIRECTED ĐỐI CHIẾU TRỰC TIẾP (12 KỊCH BẢN)
        // ---------------------------------------------------------------------
        $display("\n--- [NHOM 1] imm12[11] = 0 (0x000..0x7FF): ADDI va ADDIU cho ket qua Y HET NHAU ---");
        compare_addi_and_addiu("1. Zero imm (0x000)",         32'h0000_0000, 12'h000, 32'h0000_0000, 32'h0000_0000);
        compare_addi_and_addiu("2. Small pos imm (0x001)",    32'h0000_0064, 12'h001, 32'h0000_0065, 32'h0000_0065);
        compare_addi_and_addiu("3. Max pos 12b (0x7FF=+2047)",32'h0000_0010, 12'h7FF, 32'h0000_080F, 32'h0000_080F);
        compare_addi_and_addiu("4. Sign-flip (+ -> -, NoSat)",32'h7FFF_FF00, 12'h200, 32'h8000_0100, 32'h8000_0100);
        compare_addi_and_addiu("5. inst[31:25]==SUBSAT_F7",   32'h0000_0100, 12'h427, 32'h0000_0527, 32'h0000_0527);

        $display("\n--- [NHOM 2] imm12[11] = 1 (0x800..0xFFF): ADDI Sign-Extend (am) vs ADDIU Zero-Extend (duong) ---");
        compare_addi_and_addiu("6. Bien am/duong (0x800)",    32'h0000_0000, 12'h800, 32'hFFFF_F800, 32'h0000_0800);
        compare_addi_and_addiu("7. All-ones imm (0xFFF)",     32'h0000_0000, 12'hFFF, 32'hFFFF_FFFF, 32'h0000_0FFF);
        compare_addi_and_addiu("8. Base 0x1000 + 0xFFF",      32'h0000_1000, 12'hFFF, 32'h0000_0FFF, 32'h0000_1FFF);
        compare_addi_and_addiu("9. Wrap 32b (FFFFF001+FFF)",  32'hFFFF_F001, 12'hFFF, 32'hFFFF_F000, 32'h0000_0000);
        compare_addi_and_addiu("10.Tu INT32_MIN + 0x800",     32'h8000_0000, 12'h800, 32'h7FFF_F800, 32'h8000_0800);
        compare_addi_and_addiu("11.Tu INT32_MAX + 0xFFF",     32'h7FFF_FFFF, 12'hFFF, 32'h7FFF_FFFE, 32'h8000_0FFE);
        compare_addi_and_addiu("12.imm=0xC27 (b11=1 & F7)",   32'h0000_0100, 12'hC27, 32'hFFFF_FD27, 32'h0000_0D27);

        // ---------------------------------------------------------------------
        // PHẦN B: KIỂM TRA GHI VÀO THANH GHI x0 CHO CẢ ADDI VÀ ADDIU
        // ---------------------------------------------------------------------
        $display("\n--- [NHOM 3] Kiem tra ghi vao thanh ghi dich rd = x0 ---");
        begin
            int idx;
            dut.u_datapath.u_regfile.regs[6] = 32'h1234_5678;

            // ADDI x0, x6, 0xFFF
            idx = dbg_pc[11:2];
            dut.u_imem.mem[idx] = enc_addi(5'd0, 5'd6, 12'hFFF);
            #1;
            @(posedge clk);
            #1;

            // ADDIU x0, x6, 0xFFF
            idx = dbg_pc[11:2];
            dut.u_imem.mem[idx] = enc_addiu(5'd0, 5'd6, 12'hFFF);
            #1;
            @(posedge clk);
            #1;

            if (dut.u_datapath.u_regfile.regs[0] !== 32'h0000_0000) begin
                $display("[FAIL] 13. Ghi vao rd = x0: x0 bi thay doi thanh %08h", dut.u_datapath.u_regfile.regs[0]);
                fail_cnt++;
            end else begin
                $display("[PASS] 13. Ghi vao rd = x0           | Ca ADDI va ADDIU voi rd=x0 deu giu nguyen x0 = 00000000");
                pass_cnt++;
            end
        end

        // ---------------------------------------------------------------------
        // PHẦN C: 1000 CẶP NGẪU NHIÊN ĐỐI CHIẾU SONG SONG ADDI vs ADDIU
        // ---------------------------------------------------------------------
        $display("\n--- [NHOM 4] 1000 Vector ngau nhien doi chieu song song ADDI vs ADDIU ---");
        reset_core();

        for (int i = 0; i < 1000; i++) begin
            logic [31:0] r_rs1, exp_s, exp_z, act_s, act_z, exp_d;
            logic [11:0] r_imm;
            int          idx;

            r_rs1 = $urandom;
            r_imm = $urandom_range(0, 4095);

            dut.u_datapath.u_regfile.regs[6] = r_rs1;

            // Thực thi ADDI x8, x6, r_imm
            idx = dbg_pc[11:2];
            dut.u_imem.mem[idx] = enc_addi(5'd8, 5'd6, r_imm);
            #1;
            @(posedge clk);
            #1;

            // Thực thi ADDIU x9, x6, r_imm
            idx = dbg_pc[11:2];
            dut.u_imem.mem[idx] = enc_addiu(5'd9, 5'd6, r_imm);
            #1;
            @(posedge clk);
            #1;

            exp_s = addi_ref(r_rs1, r_imm);
            exp_z = addiu_ref(r_rs1, r_imm);
            act_s = dut.u_datapath.u_regfile.regs[8];
            act_z = dut.u_datapath.u_regfile.regs[9];
            exp_d = r_imm[11] ? 32'h0000_1000 : 32'h0000_0000;

            if ((act_s !== exp_s) || (act_z !== exp_z) || ((act_z - act_s) !== exp_d)) begin
                $display("[FAIL] RAND_%0d: rs1=%08h imm=%03h | Got ADDI=%08h ADDIU=%08h | Exp ADDI=%08h ADDIU=%08h",
                         i, r_rs1, r_imm, act_s, act_z, exp_s, exp_z);
                fail_cnt++;
            end else begin
                pass_cnt++;
            end

            if (dbg_pc >= 32'd3600) begin
                reset_core();
            end
        end

        $display("----------------------------------------------------------------------------------------------------------------");
        $display(" KET QUA DOI CHIEU tb_addi_vs_addiu: PASS = %0d | FAIL = %0d", pass_cnt, fail_cnt);
        $display("================================================================================================================");
        if (fail_cnt == 0)
            $display(" >>> tb_addi_vs_addiu PASSED SUCCESSFULLY! <<<");
        else
            $display(" >>> tb_addi_vs_addiu FAILED! <<<");
        $finish;
    end

endmodule
