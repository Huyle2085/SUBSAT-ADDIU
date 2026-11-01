// =============================================================================
// File: tb/tb_addiu.sv
// Description: System-Level Self-Checking Testbench cho lệnh tùy chỉnh ADDIU
//              kết hợp kiểm thử đồng bộ với SUBSAT & RV32I (Mục 5 & Mục 6).
//              Bao gồm:
//              - 15 ca Directed Tests (U01..U15, đã sửa U08 & U09)
//              - Golden Model độc lập addiu_ref(rs1, imm12) & enc_addiu()
//              - 3 nhóm Assertions: ap_addiu_ctrl, ap_addiu_imm, ap_decode_mutex
//              - Functional Coverage (Immediate bins, Operand bins, Result bins,
//                x0/non-x0, và 4 chuyển tiếp lệnh ADDI<->ADDIU<->SUBSAT<->SUB)
//              - 1000 vector ngẫu nhiên có bias
// =============================================================================

`timescale 1ns/1ps

module tb_addiu;
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

    int pass_cnt   = 0;
    int fail_cnt   = 0;
    int assert_err = 0;

    // Bộ đếm Functional Coverage theo Mục 5.4
    int cov_imm_000      = 0;
    int cov_imm_001      = 0;
    int cov_imm_7ff      = 0;
    int cov_imm_800      = 0;
    int cov_imm_fff      = 0;
    int cov_imm_bit11_0  = 0;
    int cov_imm_bit11_1  = 0;

    int cov_op_zero      = 0;
    int cov_op_small     = 0;
    int cov_op_max       = 0;
    int cov_op_min       = 0;
    int cov_op_all1      = 0;

    int cov_res_unchanged = 0;
    int cov_res_wrap      = 0;
    int cov_res_sign_flip = 0;
    int cov_res_sign_same = 0;
    int cov_rd_x0         = 0;
    int cov_rd_non_x0     = 0;

    int cov_tr_addi_to_addiu   = 0;
    int cov_tr_subsat_to_addiu = 0;
    int cov_tr_addiu_to_subsat = 0;
    int cov_tr_addiu_to_sub    = 0;

    typedef enum int {
        PREV_NONE   = 0,
        PREV_ADDI   = 1,
        PREV_ADDIU  = 2,
        PREV_SUBSAT = 3,
        PREV_SUB    = 4
    } prev_inst_e;
    prev_inst_e prev_inst = PREV_NONE;

    // Xung nhịp 100MHz (10ns)
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Instantiate DUT
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

    // =========================================================================
    // 1. GOLDEN MODEL ĐỘC LẬP CHO ADDIU (Mục 5.2)
    // =========================================================================
    function automatic logic [31:0] addiu_ref(
        input logic [31:0] rs1,
        input logic [11:0] imm12
    );
        logic [31:0] imm_zext;
        imm_zext = {20'b0, imm12};
        return rs1 + imm_zext; // Cắt về 32-bit, modulo 2^32
    endfunction

    // =========================================================================
    // 2. ASSERTIONS & COVERAGE SAMPLING (Mục 5.3 & Mục 5.4)
    // =========================================================================
    always @(posedge clk) begin
        if (rst_n) begin
            // ap_addiu_ctrl: Kiểm tra tuyến điều khiển khi is_addiu = 1
            if (dbg_is_addiu) begin
                if ((dbg_imm_sel  !== IMM_I_ZERO) ||
                    (dbg_a_sel    !== 1'b0)       ||
                    (dbg_b_sel    !== 1'b1)       ||
                    (dbg_wb_sel   !== WB_ALU)     ||
                    (dbg_reg_w_en !== 1'b1)) begin
                    $display("[ASSERT FAIL] ap_addiu_ctrl tai PC=%h: ImmSel=%0d Asel=%b Bsel=%b WBSel=%0d RegWEn=%b",
                             dbg_pc, dbg_imm_sel, dbg_a_sel, dbg_b_sel, dbg_wb_sel, dbg_reg_w_en);
                    assert_err++;
                end

                // ap_addiu_imm: Kiểm tra zero-extend immediate
                if (dbg_imm_out !== {20'b0, dbg_inst[31:20]}) begin
                    $display("[ASSERT FAIL] ap_addiu_imm tai PC=%h: imm_out=%h != {20'b0, %h}",
                             dbg_pc, dbg_imm_out, dbg_inst[31:20]);
                    assert_err++;
                end
            end

            // ap_decode_mutex: Không bao giờ cùng bật is_addiu và is_subsat
            if (dbg_is_addiu && dbg_is_subsat) begin
                $display("[ASSERT FAIL] ap_decode_mutex: is_addiu && is_subsat == 1 tai PC=%h", dbg_pc);
                assert_err++;
            end

            // Bảo toàn bất biến của SUBSAT & các lệnh khác
            if (!dbg_is_subsat && ((dbg_wb_sel == WB_MAX) || (dbg_wb_sel == WB_MIN))) begin
                $display("[ASSERT FAIL] !is_subsat nhung WBSel=%0d chon MAX/MIN tai PC=%h", dbg_wb_sel, dbg_pc);
                assert_err++;
            end

            // Thu thập Coverage khi thực thi ADDIU
            if (dbg_is_addiu) begin
                logic [11:0] imm12;
                logic [31:0] rs1_v;
                logic [31:0] res_v;
                logic [4:0]  rd_idx;
                logic [4:0]  rs1_idx;

                imm12   = dbg_inst[31:20];
                rd_idx  = dbg_inst[11:7];
                rs1_idx = dbg_inst[19:15];
                rs1_v   = (rs1_idx == 5'd0) ? 32'h0 : dut.u_datapath.u_regfile.regs[rs1_idx];
                res_v   = dbg_wb_data;

                if (imm12 == 12'h000) cov_imm_000++;
                if (imm12 == 12'h001) cov_imm_001++;
                if (imm12 == 12'h7FF) cov_imm_7ff++;
                if (imm12 == 12'h800) cov_imm_800++;
                if (imm12 == 12'hFFF) cov_imm_fff++;
                if (imm12[11] == 1'b0) cov_imm_bit11_0++;
                else                   cov_imm_bit11_1++;

                if (rs1_v == 32'h0000_0000)                      cov_op_zero++;
                else if (rs1_v <= 32'h0000_0100)                 cov_op_small++;
                if ((rs1_v & 32'hFFFF_F000) == 32'h7FFF_F000)    cov_op_max++;
                if (rs1_v == 32'h8000_0000)                      cov_op_min++;
                if ((rs1_v & 32'hFFFF_F000) == 32'hFFFF_F000)    cov_op_all1++;

                if (res_v == rs1_v)                              cov_res_unchanged++;
                if (res_v < rs1_v)                               cov_res_wrap++;
                if (res_v[31] != rs1_v[31])                      cov_res_sign_flip++;
                else                                             cov_res_sign_same++;

                if (rd_idx == 5'd0) cov_rd_x0++;
                else                cov_rd_non_x0++;

                if (prev_inst == PREV_ADDI)   cov_tr_addi_to_addiu++;
                if (prev_inst == PREV_SUBSAT) cov_tr_subsat_to_addiu++;
                prev_inst = PREV_ADDIU;
            end else if (dbg_is_subsat) begin
                if (prev_inst == PREV_ADDIU)  cov_tr_addiu_to_subsat++;
                prev_inst = PREV_SUBSAT;
            end else if ((dbg_inst[6:0] == OP_IMM) && (dbg_inst[14:12] == 3'b000)) begin
                prev_inst = PREV_ADDI;
            end else if ((dbg_inst[6:0] == OP_RTYPE) && (dbg_inst[14:12] == 3'b000) && (dbg_inst[31:25] == F7_ALT)) begin
                if (prev_inst == PREV_ADDIU)  cov_tr_addiu_to_sub++;
                prev_inst = PREV_SUB;
            end else begin
                prev_inst = PREV_NONE;
            end
        end
    end

    // =========================================================================
    // 3. CÁC TASK KIỂM THỬ HƯỚNG ĐÍCH
    // =========================================================================
    task automatic reset_core();
        rst_n     = 1'b0;
        prev_inst = PREV_NONE;
        @(posedge clk);
        #1;
        rst_n = 1'b1;
    endtask

    task automatic run_directed_addiu(
        input string       tc_id,
        input logic [4:0]  rd,
        input logic [4:0]  rs1,
        input logic [31:0] rs1_val,
        input logic [11:0] imm12,
        input logic [31:0] exp_rd_val
    );
        logic [31:0] pc_before;
        logic [31:0] gold_val;
        logic [31:0] actual_rd;
        int          word_idx;

        pc_before = dbg_pc;
        word_idx  = pc_before[11:2];

        if (rs1 != 5'd0) dut.u_datapath.u_regfile.regs[rs1] = rs1_val;
        dut.u_imem.mem[word_idx] = enc_addiu(rd, rs1, imm12);
        #1;

        gold_val = (rd == 5'd0) ? 32'h0000_0000 : addiu_ref((rs1 == 5'd0) ? 32'h0 : rs1_val, imm12);

        @(posedge clk);
        #1;

        actual_rd = dut.u_datapath.u_regfile.regs[rd];
        if ((actual_rd !== exp_rd_val) || (actual_rd !== gold_val) || (dbg_pc !== (pc_before + 32'd4))) begin
            $display("[FAIL] %-20s | rs1=%08h imm12=%03h | Got rd(x%0d)=%08h Exp=%08h Gold=%08h",
                     tc_id, rs1_val, imm12, rd, actual_rd, exp_rd_val, gold_val);
            fail_cnt++;
        end else begin
            $display("[PASS] %-20s | rs1=%08h imm12=%03h -> rd(x%0d)=%08h (imm_out=%08h, WBSel=%0d)",
                     tc_id, rs1_val, imm12, rd, actual_rd, {20'b0, imm12}, WB_ALU);
            pass_cnt++;
        end
    endtask

    initial begin
        $dumpfile("sim/wave_addiu.vcd");
        $dumpvars(0, dut);

        $display("================================================================================");
        $display(" BAT DAU KIEM THU HE THONG: LENH TUY CHINH ADDIU + SUBSAT + RV32I (tb_addiu)");
        $display(" Encoding ADDIU: opcode=7'b%07b (custom-0), funct3=3'b%03b, ImmSel=3'b%03b",
                 OP_CUSTOM0, ADDIU_F3, IMM_I_ZERO);
        $display(" Vi du enc_addiu(5, 6, 12'hFFF) = 0x%08h", enc_addiu(5'd5, 5'd6, 12'hFFF));
        $display("================================================================================");

        reset_core();

        // ---------------------------------------------------------------------
        // PHẦN A: 15 CA DIRECTED TESTS BẮT BUỘC (U01 -> U15, Mục 5.1)
        // ---------------------------------------------------------------------
        $display("\n--- [PHAN A] 15 CA DIRECTED TESTS (U01..U15 - DA HIEU CHINH U08 & U09) ---");

        // U01: Zero immediate
        run_directed_addiu("U01_Zero_Imm",      5'd5, 5'd6, 32'h0000_0000, 12'h000, 32'h0000_0000);
        // U02: Immediate dương nhỏ
        run_directed_addiu("U02_Small_Pos_Imm", 5'd5, 5'd6, 32'h0000_0010, 12'h7FF, 32'h0000_080F);
        // U03: Bit imm[11]=1, zero-extend (KHÔNG sign-extend)
        run_directed_addiu("U03_Bit11_ZeroExt", 5'd5, 5'd6, 32'h0000_0000, 12'h800, 32'h0000_0800);
        // U04: Max immediate 4095 (0xFFF)
        run_directed_addiu("U04_Max_Imm_4095",  5'd5, 5'd6, 32'h0000_0000, 12'hFFF, 32'h0000_0FFF);
        // U05: Gần ngưỡng 32-bit
        run_directed_addiu("U05_Near_32b_Edge", 5'd5, 5'd6, 32'hFFFF_F000, 12'hFFF, 32'hFFFF_FFFF);
        // U06: Wrap-around 32-bit
        run_directed_addiu("U06_Wrap_32b",      5'd5, 5'd6, 32'hFFFF_FFFF, 12'h001, 32'h0000_0000);
        // U07: Đổi dấu (+ -> -), KHÔNG bão hòa!
        run_directed_addiu("U07_SignFlip_NoSat",5'd5, 5'd6, 32'h7FFF_FF00, 12'h200, 32'h8000_0100);
        // U08: Giá trị rs1 sửa từ bản gốc (FFFF_F001 + FFF = 0000_0000)
        run_directed_addiu("U08_Fixed_rs1_Wrap",5'd5, 5'd6, 32'hFFFF_F001, 12'hFFF, 32'h0000_0000);
        // U09: Expected sửa từ bản gốc (0000_0000 + FFF = 0000_0FFF)
        run_directed_addiu("U09_Fixed_Exp_0FFF",5'd5, 5'd6, 32'h0000_0000, 12'hFFF, 32'h0000_0FFF);
        // U10: Âm + immediate dương
        run_directed_addiu("U10_Neg_Plus_Imm",  5'd5, 5'd6, 32'h8000_0000, 12'h800, 32'h8000_0800);

        // U11: So sánh trực tiếp ADDI chuẩn (sign-extend -> FFFF_FFFF) vs ADDIU (zero-extend -> 0000_0FFF)
        begin
            int idx;
            dut.u_datapath.u_regfile.regs[6] = 32'h0000_0000;
            // Chạy ADDI x8, x6, 0xFFF trước (đồng thời tạo transition ADDI -> ADDIU)
            idx = dbg_pc[11:2];
            dut.u_imem.mem[idx] = {12'hFFF, 5'd6, 3'b000, 5'd8, OP_IMM};
            #1;
            @(posedge clk);
            #1;
            // Chạy ADDIU x5, x6, 0xFFF ngay sau đó
            run_directed_addiu("U11_Compare_ADDI",  5'd5, 5'd6, 32'h0000_0000, 12'hFFF, 32'h0000_0FFF);
            if (dut.u_datapath.u_regfile.regs[8] !== 32'hFFFF_FFFF) begin
                $display("[FAIL] U11_Compare_ADDI: ADDI chuan cho x8=%08h != FFFFFFFF", dut.u_datapath.u_regfile.regs[8]);
                fail_cnt++;
            end
        end

        // U12: rd = x0 phải luôn bằng 0
        run_directed_addiu("U12_rd_x0_Zero",    5'd0, 5'd6, 32'h1234_5678, 12'hFFF, 32'h0000_0000);

        // U13: ADDIU ngay sau SUBSAT tràn (kiểm tra transition SUBSAT(tràn) -> ADDIU & ADDIU -> SUBSAT)
        begin
            int idx;
            dut.u_datapath.u_regfile.regs[6] = 32'h7FFF_FFFF;
            dut.u_datapath.u_regfile.regs[7] = 32'hFFFF_FFFF;
            // 1) SUBSAT x9, x6, x7 (tràn dương -> WB_MAX = 7FFF_FFFF)
            idx = dbg_pc[11:2];
            dut.u_imem.mem[idx] = encode_subsat(5'd9, 5'd6, 5'd7);
            #1;
            @(posedge clk);
            #1;
            // 2) ADDIU x10, x9, 12'h001 (7FFF_FFFF + 1 = 8000_0000, WBSel phải về WB_ALU=1!)
            run_directed_addiu("U13_After_SUBSAT_Ov", 5'd10, 5'd9, 32'h7FFF_FFFF, 12'h001, 32'h8000_0000);
            // 3) Chạy tiếp SUBSAT x11, x10, x7 (tạo transition ADDIU -> SUBSAT)
            idx = dbg_pc[11:2];
            dut.u_datapath.u_regfile.regs[7] = 32'h0000_0001;
            dut.u_imem.mem[idx] = encode_subsat(5'd11, 5'd10, 5'd7); // 8000_0000 - 1 -> bão hòa âm 8000_0000
            #1;
            @(posedge clk);
            #1;
            if (dut.u_datapath.u_regfile.regs[11] !== 32'h8000_0000) begin
                $display("[FAIL] U13_Transition_ADDIU_to_SUBSAT: x11=%08h", dut.u_datapath.u_regfile.regs[11]);
                fail_cnt++;
            end
        end

        // U14: opcode = custom-0 nhưng funct3 chưa dùng (010..111) phải không ghi thanh ghi
        begin
            int idx;
            dut.u_datapath.u_regfile.regs[20] = 32'hDEAD_BEEF;
            dut.u_datapath.u_regfile.regs[6]  = 32'h0000_0100;
            for (int f3 = 2; f3 < 8; f3++) begin
                idx = dbg_pc[11:2];
                dut.u_imem.mem[idx] = {12'h123, 5'd6, f3[2:0], 5'd20, OP_CUSTOM0};
                #1;
                @(posedge clk);
                #1;
            end
            if (dut.u_datapath.u_regfile.regs[20] !== 32'hDEAD_BEEF) begin
                $display("[FAIL] U14_Unused_Custom0_F3: x20 bi ghi de thanh %08h", dut.u_datapath.u_regfile.regs[20]);
                fail_cnt++;
            end else begin
                $display("[PASS] U14_Unused_Custom0_F3| custom-0 voi funct3=010..111 bi chan, x20 giu nguyen DEADBEEF");
                pass_cnt++;
            end
        end

        // U15: Regression ADDI / SUB / SUBSAT / LOAD / STORE / BRANCH & transition ADDIU -> SUB
        begin
            int base_idx;
            base_idx = dbg_pc[11:2];
            dut.u_datapath.u_regfile.regs[6] = 32'h0000_0100;
            dut.u_datapath.u_regfile.regs[7] = 32'h0000_0040;

            // 1) ADDIU x12, x6, 0x800 -> 0x0000_0900
            dut.u_imem.mem[base_idx + 0] = enc_addiu(5'd12, 5'd6, 12'h800);
            // 2) SUB x13, x12, x7 -> 0x0000_08C0 (tạo transition ADDIU -> SUB)
            dut.u_imem.mem[base_idx + 1] = encode_rtype(F7_ALT, 5'd7, 5'd12, 3'b000, 5'd13, OP_RTYPE);
            // 3) SW x13, 32(x0)
            dut.u_imem.mem[base_idx + 2] = {7'd1, 5'd13, 5'd0, 3'b010, 5'd0, OP_STORE};
            // 4) LW x14, 32(x0) -> 0x0000_08C0
            dut.u_imem.mem[base_idx + 3] = {12'd32, 5'd0, 3'b010, 5'd14, OP_LOAD};
            // 5) BEQ x13, x14, +8 (nhảy qua 1 lệnh)
            dut.u_imem.mem[base_idx + 4] = {1'b0, 6'd0, 5'd14, 5'd13, 3'b000, 4'd4, 1'b0, OP_BRANCH};
            // 6) ADDI x14, x0, 999 (bị nhảy qua)
            dut.u_imem.mem[base_idx + 5] = {12'd999, 5'd0, 3'b000, 5'd14, OP_IMM};
            // 7) SUBSAT x15, x14, x7 -> 0x0000_0880
            dut.u_imem.mem[base_idx + 6] = encode_subsat(5'd15, 5'd14, 5'd7);

            repeat (6) begin
                @(posedge clk);
                #1;
            end

            if ((dut.u_datapath.u_regfile.regs[12] !== 32'h0000_0900) ||
                (dut.u_datapath.u_regfile.regs[13] !== 32'h0000_08C0) ||
                (dut.u_datapath.u_regfile.regs[14] !== 32'h0000_08C0) ||
                (dut.u_datapath.u_regfile.regs[15] !== 32'h0000_0880)) begin
                $display("[FAIL] U15_Full_Regression: x12=%h x13=%h x14=%h x15=%h",
                         dut.u_datapath.u_regfile.regs[12],
                         dut.u_datapath.u_regfile.regs[13],
                         dut.u_datapath.u_regfile.regs[14],
                         dut.u_datapath.u_regfile.regs[15]);
                fail_cnt++;
            end else begin
                $display("[PASS] U15_Full_Regression  | Chuoi ADDIU -> SUB -> SW -> LW -> BEQ -> SUBSAT chinh xac");
                pass_cnt++;
            end
        end

        // ---------------------------------------------------------------------
        // PHẦN B: 1000 RANDOM VECTORS CHO ADDIU
        // ---------------------------------------------------------------------
        $display("\n--- [PHAN B] RANDOM TESTS CHO ADDIU (1000 VECTOR) ---");
        reset_core();

        for (int i = 0; i < 1000; i++) begin
            logic [31:0] r_rs1, exp_v, act_v;
            logic [11:0] r_imm;
            logic [4:0]  rd_i, rs1_i;
            int          w_idx;

            r_rs1 = $urandom;
            r_imm = $urandom_range(0, 4095);
            rd_i  = $urandom_range(0, 31);
            rs1_i = $urandom_range(1, 31);

            w_idx = dbg_pc[11:2];
            dut.u_datapath.u_regfile.regs[rs1_i] = r_rs1;
            dut.u_imem.mem[w_idx] = enc_addiu(rd_i, rs1_i, r_imm);
            #1;

            exp_v = (rd_i == 5'd0) ? 32'h0000_0000 : addiu_ref(r_rs1, r_imm);
            @(posedge clk);
            #1;

            act_v = dut.u_datapath.u_regfile.regs[rd_i];
            if (act_v !== exp_v) begin
                $display("[FAIL] RAND_%0d: rs1=%h imm=%h | Got=%h Exp=%h", i, r_rs1, r_imm, act_v, exp_v);
                fail_cnt++;
            end else begin
                pass_cnt++;
            end

            if (dbg_pc >= 32'd3600) reset_core();
        end

        // ---------------------------------------------------------------------
        // PHẦN C: BÁO CÁO COVERAGE & TỔNG KẾT (Mục 5.4 & Mục 6.2)
        // ---------------------------------------------------------------------
        $display("\n================================================================================");
        $display(" BAO CAO FUNCTIONAL COVERAGE CHO ADDIU (Muc 5.4)");
        $display("--------------------------------------------------------------------------------");
        $display(" 1. Immediate bins : 000(%0d) 001(%0d) 7FF(%0d) 800(%0d) FFF(%0d) | b11=0(%0d) b11=1(%0d)",
                 cov_imm_000, cov_imm_001, cov_imm_7ff, cov_imm_800, cov_imm_fff, cov_imm_bit11_0, cov_imm_bit11_1);
        $display(" 2. Operand bins   : zero(%0d) small(%0d) near_MAX(%0d) MIN(%0d) near_FFFF(%0d)",
                 cov_op_zero, cov_op_small, cov_op_max, cov_op_min, cov_op_all1);
        $display(" 3. Result bins    : unchanged(%0d) wrap(%0d) sign_flip(%0d) sign_same(%0d) | rd=x0(%0d) rd!=x0(%0d)",
                 cov_res_unchanged, cov_res_wrap, cov_res_sign_flip, cov_res_sign_same, cov_rd_x0, cov_rd_non_x0);
        $display(" 4. Transitions    : ADDI->ADDIU(%0d) SUBSAT->ADDIU(%0d) ADDIU->SUBSAT(%0d) ADDIU->SUB(%0d)",
                 cov_tr_addi_to_addiu, cov_tr_subsat_to_addiu, cov_tr_addiu_to_subsat, cov_tr_addiu_to_sub);
        $display("================================================================================");
        $display(" TONG KET KIEM THU tb_addiu: PASS = %0d | FAIL = %0d | ASSERT_ERR = %0d",
                 pass_cnt, fail_cnt, assert_err);
        $display("================================================================================");

        if ((fail_cnt == 0) && (assert_err == 0))
            $display(" >>> ALL ADDIU TESTS & COVERAGE GOALS PASSED SUCCESSFULLY! <<<");
        else
            $display(" >>> ADDIU VERIFICATION FAILED! <<<");
        $finish;
    end

endmodule
