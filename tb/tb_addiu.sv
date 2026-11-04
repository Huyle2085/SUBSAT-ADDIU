// =============================================================================
// File: tb/tb_addiu.sv
// Description: System-Level Self-Checking Testbench chuyên biệt cho
//              RV32I + ADDIU (tương xứng với tb_subsat.sv cho RV32I + SUBSAT).
//              Bao gồm:
//              - 15 ca kiểm thử Directed cho RV32I + ADDIU (U01..U15)
//              - Golden Reference Model độc lập addiu_ref(rs1, imm12)
//              - Assertions kiểm tra bất biến phần cứng cho RV32I + ADDIU
//              - 1000+ cặp kiểm thử ngẫu nhiên có bias vào các điểm biên
//              - Kiểm thử hồi quy (Regression) cho các lệnh chuẩn RV32I
//              - Báo cáo Functional Coverage đầy đủ cho RV32I + ADDIU
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

    // Bộ đếm kết quả kiểm thử
    int pass_cnt   = 0;
    int fail_cnt   = 0;
    int assert_err = 0;

    // Bộ đếm Functional Coverage cho RV32I + ADDIU
    int cov_imm_000       = 0;
    int cov_imm_001       = 0;
    int cov_imm_7ff       = 0;
    int cov_imm_800       = 0;
    int cov_imm_fff       = 0;
    int cov_imm_bit11_0   = 0;
    int cov_imm_bit11_1   = 0;

    int cov_op_zero       = 0;
    int cov_op_small      = 0;
    int cov_op_max        = 0;
    int cov_op_min        = 0;
    int cov_op_all1       = 0;

    int cov_res_unchanged = 0;
    int cov_res_wrap      = 0;
    int cov_res_sign_flip = 0;
    int cov_res_sign_same = 0;
    int cov_rd_x0         = 0;
    int cov_rd_non_x0     = 0;
    int cov_wbsel [0:2]   = '{default: 0};
    int cov_illegal_enc   = 0;

    // Khởi tạo xung nhịp 100MHz (chu kỳ 10ns)
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
    // 1. GOLDEN REFERENCE MODEL ĐỘC LẬP CHO ADDIU
    // =========================================================================
    function automatic logic [31:0] addiu_ref(
        input logic [31:0] rs1,
        input logic [11:0] imm12
    );
        logic [31:0] imm_zext;
        imm_zext = {20'b0, imm12};
        return rs1 + imm_zext; // Cắt về 32-bit, modulo 2^32 (không bão hòa)
    endfunction

    // =========================================================================
    // 2. ASSERTIONS & COVERAGE SAMPLING TẠI MỖI CHU KỲ LỆNH
    // =========================================================================
    always @(negedge clk) begin
        if (rst_n) begin
            // A1 (ap_addiu_ctrl): Khi là ADDIU, các tín hiệu điều khiển phải đúng chuẩn I-type Zero-Extend
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

                // A2 (ap_addiu_imm): Ngõ ra ImmGen phải được mở rộng 0 (Zero-Extend)
                if (dbg_imm_out !== {20'b0, dbg_inst[31:20]}) begin
                    $display("[ASSERT FAIL] ap_addiu_imm tai PC=%h: imm_out=%h != {20'b0, %h}",
                             dbg_pc, dbg_imm_out, dbg_inst[31:20]);
                    assert_err++;
                end
            end

            // A3: Khi KHÔNG phải ADDIU, tuyệt đối không chọn IMM_I_ZERO
            if (!dbg_is_addiu && (dbg_imm_sel == IMM_I_ZERO)) begin
                $display("[ASSERT FAIL] !is_addiu nhung ImmSel=IMM_I_ZERO tai PC=%h", dbg_pc);
                assert_err++;
            end

            // A4: Thanh ghi x0 luôn cứng bằng 0
            if (dut.u_datapath.u_regfile.regs[0] !== 32'h0000_0000) begin
                $display("[ASSERT FAIL] x0 bi thay doi gia tri: %h", dut.u_datapath.u_regfile.regs[0]);
                assert_err++;
            end

            // A5: Không có X/Z trên các tín hiệu điều khiển chính
            if ($isunknown(dbg_imm_sel) || $isunknown(dbg_wb_sel) || $isunknown(dbg_reg_w_en) || $isunknown(dbg_wb_data)) begin
                $display("[ASSERT FAIL] Phat hien X/Z tren tin hieu dieu khien/WB tai PC=%h", dbg_pc);
                assert_err++;
            end

            // Thu thập Functional Coverage
            if (dbg_wb_sel <= WB_PC4) begin
                cov_wbsel[dbg_wb_sel]++;
            end
            if (dbg_illegal_inst) begin
                cov_illegal_enc++;
            end
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
            end
        end
    end

    // =========================================================================
    // 3. CÁC TASK HỖ TRỢ THỰC THI LỆNH TRÊN TOP-LEVEL CORE
    // =========================================================================
    task automatic reset_core();
        rst_n = 1'b0;
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

        // Kiểm tra tín hiệu tổ hợp trước sườn lên xung nhịp
        if ((dbg_is_addiu !== 1'b1) || (dbg_imm_sel !== IMM_I_ZERO) ||
            (dbg_imm_out !== {20'b0, imm12}) || (dbg_wb_sel !== WB_ALU)) begin
            $display("[FAIL] %-20s (Comb) | is_addiu=%b ImmSel=%0d imm_out=%08h WBSel=%0d",
                     tc_id, dbg_is_addiu, dbg_imm_sel, dbg_imm_out, dbg_wb_sel);
            fail_cnt++;
        end

        @(posedge clk);
        #1;

        actual_rd = dut.u_datapath.u_regfile.regs[rd];
        if ((actual_rd !== exp_rd_val) || (actual_rd !== gold_val) || (dbg_pc !== (pc_before + 32'd4))) begin
            $display("[FAIL] %-20s (Seq)  | rs1=%08h imm12=%03h | Got rd(x%0d)=%08h Exp=%08h Gold=%08h",
                     tc_id, rs1_val, imm12, rd, actual_rd, exp_rd_val, gold_val);
            fail_cnt++;
        end else begin
            $display("[PASS] %-20s | rs1=%08h imm12=%03h -> rd(x%0d)=%08h (imm_out=%08h, ImmSel=%0d, WBSel=%0d)",
                     tc_id, rs1_val, imm12, rd, actual_rd, {20'b0, imm12}, IMM_I_ZERO, WB_ALU);
            pass_cnt++;
        end
    endtask

    function automatic logic [31:0] get_biased_rs1();
        int r;
        r = $urandom % 10;
        case (r)
            0: return 32'h0000_0000;
            1: return 32'h0000_0010;
            2: return 32'h7FFF_FF00;
            3: return 32'h7FFF_FFFF;
            4: return 32'h8000_0000;
            5: return 32'hFFFF_F000;
            6: return 32'hFFFF_F001;
            7: return 32'hFFFF_FFFF;
            default: return $urandom;
        endcase
    endfunction

    function automatic logic [11:0] get_biased_imm12();
        int r;
        r = $urandom % 10;
        case (r)
            0: return 12'h000;
            1: return 12'h001;
            2: return 12'h7FF;
            3: return 12'h800;
            4: return 12'hFFF;
            5: return 12'h200;
            default: return $urandom_range(0, 4095);
        endcase
    endfunction

    // =========================================================================
    // 4. KỊCH BẢN KIỂM THỬ CHÍNH (MAIN TEST SEQUENCE CHO RV32I + ADDIU)
    // =========================================================================
    initial begin
        $dumpfile("sim/wave_addiu.vcd");
        $dumpvars(0, dut);

        $display("================================================================================");
        $display(" BAT DAU KIEM THU HE THONG: RV32I + ADDIU (tb_addiu)");
        $display(" Opcode ADDIU = 7'b%07b (custom-0), funct3 = 3'b%03b, ImmSel = 3'b%03b (IMM_I_ZERO)",
                 OP_CUSTOM0, ADDIU_F3, IMM_I_ZERO);
        $display(" Vi du ma may ADDIU x5, x6, 0xFFF = 0x%08h", enc_addiu(5'd5, 5'd6, 12'hFFF));
        $display("================================================================================");

        reset_core();

        // ---------------------------------------------------------------------
        // PHẦN A: 15 CA KIỂM THỬ DIRECTED CHO RV32I + ADDIU (U01 -> U15)
        // ---------------------------------------------------------------------
        $display("\n--- [PHAN A] 15 CA KIEM THU DIRECTED CHO RV32I + ADDIU (U01..U15) ---");

        // U01: Zero immediate
        run_directed_addiu("U01_Zero_Imm",       5'd5, 5'd6, 32'h0000_0000, 12'h000, 32'h0000_0000);
        // U02: Immediate dương nhỏ (0x7FF = +2047)
        run_directed_addiu("U02_Small_Pos_Imm",  5'd5, 5'd6, 32'h0000_0010, 12'h7FF, 32'h0000_080F);
        // U03: Bit imm[11]=1 (0x800), mở rộng 0 thành +2048 (KHÔNG mở rộng dấu)
        run_directed_addiu("U03_Bit11_ZeroExt",  5'd5, 5'd6, 32'h0000_0000, 12'h800, 32'h0000_0800);
        // U04: Max immediate 12-bit không dấu (0xFFF = +4095)
        run_directed_addiu("U04_Max_Imm_4095",   5'd5, 5'd6, 32'h0000_0000, 12'hFFF, 32'h0000_0FFF);
        // U05: Gần ngưỡng 32-bit (0xFFFF_F000 + 0xFFF = 0xFFFF_FFFF)
        run_directed_addiu("U05_Near_32b_Edge",  5'd5, 5'd6, 32'hFFFF_F000, 12'hFFF, 32'hFFFF_FFFF);
        // U06: Wrap-around 32-bit (0xFFFF_FFFF + 0x001 = 0x0000_0000)
        run_directed_addiu("U06_Wrap_32b",       5'd5, 5'd6, 32'hFFFF_FFFF, 12'h001, 32'h0000_0000);
        // U07: Đổi dấu từ dương sang âm (0x7FFF_FF00 + 0x200 = 0x8000_0100), KHÔNG bão hòa
        run_directed_addiu("U07_SignFlip_NoSat", 5'd5, 5'd6, 32'h7FFF_FF00, 12'h200, 32'h8000_0100);
        // U08: Wrap-around với imm=0xFFF (0xFFFF_F001 + 0xFFF = 0x0000_0000)
        run_directed_addiu("U08_Fixed_rs1_Wrap", 5'd5, 5'd6, 32'hFFFF_F001, 12'hFFF, 32'h0000_0000);
        // U09: Kiểm tra độc lập 0x0000_0000 + 0xFFF = 0x0000_0FFF
        run_directed_addiu("U09_Fixed_Exp_0FFF", 5'd5, 5'd6, 32'h0000_0000, 12'hFFF, 32'h0000_0FFF);
        // U10: Toán hạng âm (INT32_MIN) cộng immediate dương (0x800)
        run_directed_addiu("U10_Neg_Plus_Imm",   5'd5, 5'd6, 32'h8000_0000, 12'h800, 32'h8000_0800);

        // U11: Đối chiếu trực tiếp ADDI chuẩn (sign-extend -> FFFF_FFFF) vs ADDIU (zero-extend -> 0000_0FFF)
        begin
            int idx;
            dut.u_datapath.u_regfile.regs[6] = 32'h0000_0000;
            idx = dbg_pc[11:2];
            dut.u_imem.mem[idx] = {12'hFFF, 5'd6, 3'b000, 5'd8, OP_IMM}; // ADDI x8, x6, 0xFFF
            #1;
            @(posedge clk);
            #1;
            run_directed_addiu("U11_Compare_ADDI", 5'd5, 5'd6, 32'h0000_0000, 12'hFFF, 32'h0000_0FFF);
            if (dut.u_datapath.u_regfile.regs[8] !== 32'hFFFF_FFFF) begin
                $display("[FAIL] U11_Compare_ADDI: ADDI chuan cho x8=%08h != FFFFFFFF", dut.u_datapath.u_regfile.regs[8]);
                fail_cnt++;
            end
        end

        // U12: Ghi vào thanh ghi rd = x0 (với cả imm12=0x800 và imm12=0xFFF) -> x0 luôn bằng 0
        run_directed_addiu("U12a_rd_x0_Imm800",  5'd0, 5'd6, 32'h1234_5678, 12'h800, 32'h0000_0000);
        run_directed_addiu("U12b_rd_x0_ImmFFF",  5'd0, 5'd6, 32'h1234_5678, 12'hFFF, 32'h0000_0000);

        // U13: Chuỗi lệnh ADDIU phụ thuộc dữ liệu liên tiếp (Back-to-Back RAW Chain)
        begin
            dut.u_datapath.u_regfile.regs[6] = 32'h0000_1000;
            // x9 = x6 + 0x800 = 0x0000_1800
            run_directed_addiu("U13a_Chain_Step1", 5'd9,  5'd6, 32'h0000_1000, 12'h800, 32'h0000_1800);
            // x10 = x9 + 0x7FF = 0x0000_1FFF
            run_directed_addiu("U13b_Chain_Step2", 5'd10, 5'd9, 32'h0000_1800, 12'h7FF, 32'h0000_1FFF);
            // x11 = x10 + 0x001 = 0x0000_2000
            run_directed_addiu("U13c_Chain_Step3", 5'd11, 5'd10,32'h0000_1FFF, 12'h001, 32'h0000_2000);
        end

        // U14: Mã lệnh custom-0 nhưng funct3 chưa dùng (010..111) bị từ chối (illegal_inst=1, RegWEn=0)
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

        // U15: Kiểm thử hồi quy (Regression) chuỗi lệnh RV32I + ADDIU (ADDIU, ADD, SUB, SW, LW, BEQ, JAL, LUI)
        begin
            int base_idx;
            logic [31:0] base_pc;
            base_pc  = dbg_pc;
            base_idx = base_pc[11:2];
            dut.u_datapath.u_regfile.regs[6] = 32'h0000_0100;
            dut.u_datapath.u_regfile.regs[7] = 32'h0000_0040;

            // 1) ADDIU x12, x6, 0x800 -> 0x0000_0900
            dut.u_imem.mem[base_idx + 0] = enc_addiu(5'd12, 5'd6, 12'h800);
            // 2) SUB x13, x12, x7 -> 0x0000_08C0
            dut.u_imem.mem[base_idx + 1] = encode_rtype(F7_ALT, 5'd7, 5'd12, 3'b000, 5'd13, OP_RTYPE);
            // 3) SW x13, 32(x0) -> DMEM[8] = 0x0000_08C0
            dut.u_imem.mem[base_idx + 2] = {7'd1, 5'd13, 5'd0, 3'b010, 5'd0, OP_STORE};
            // 4) LW x14, 32(x0) -> x14 = 0x0000_08C0 (kiểm tra WB_MEM)
            dut.u_imem.mem[base_idx + 3] = {12'd32, 5'd0, 3'b010, 5'd14, OP_LOAD};
            // 5) JAL x15, +8 -> x15 = PC+4, nhảy qua 1 lệnh (kiểm tra WB_PC4)
            dut.u_imem.mem[base_idx + 4] = {1'b0, 10'd4, 1'b0, 8'd0, 5'd15, OP_JAL};
            // 6) ADDI x14, x0, 999 (lệnh bị nhảy qua)
            dut.u_imem.mem[base_idx + 5] = {12'd999, 5'd0, 3'b000, 5'd14, OP_IMM};
            // 7) LUI x16, 0xABCDE -> x16 = 0xABCDE000
            dut.u_imem.mem[base_idx + 6] = {20'hABCDE, 5'd16, OP_LUI};

            repeat (6) begin
                @(posedge clk);
                #1;
            end

            if ((dut.u_datapath.u_regfile.regs[12] !== 32'h0000_0900) ||
                (dut.u_datapath.u_regfile.regs[13] !== 32'h0000_08C0) ||
                (dut.u_datapath.u_regfile.regs[14] !== 32'h0000_08C0) ||
                (dut.u_datapath.u_regfile.regs[15] !== (base_pc + 32'd20)) ||
                (dut.u_datapath.u_regfile.regs[16] !== 32'hABCD_E000)) begin
                $display("[FAIL] U15_RV32I_Regression: x12=%h x13=%h x14=%h x15=%h x16=%h",
                         dut.u_datapath.u_regfile.regs[12],
                         dut.u_datapath.u_regfile.regs[13],
                         dut.u_datapath.u_regfile.regs[14],
                         dut.u_datapath.u_regfile.regs[15],
                         dut.u_datapath.u_regfile.regs[16]);
                fail_cnt++;
            end else begin
                $display("[PASS] U15_RV32I_Regression | Chuoi ADDIU -> SUB -> SW -> LW(WB_MEM) -> JAL(WB_PC4) -> LUI chinh xac");
                pass_cnt++;
            end
        end

        // ---------------------------------------------------------------------
        // PHẦN B: 1000 BIASED RANDOM VECTORS CHO RV32I + ADDIU
        // ---------------------------------------------------------------------
        $display("\n--- [PHAN B] RANDOM TESTS CHO RV32I + ADDIU (1000 VECTOR CO BIAS) ---");
        reset_core();

        for (int i = 0; i < 1000; i++) begin
            logic [31:0] r_rs1, exp_v, act_v, pc_prev;
            logic [11:0] r_imm;
            logic [4:0]  rd_i, rs1_i;
            int          w_idx;

            r_rs1   = get_biased_rs1();
            r_imm   = get_biased_imm12();
            rd_i    = $urandom_range(0, 31);
            rs1_i   = $urandom_range(1, 31);
            pc_prev = dbg_pc;
            w_idx   = pc_prev[11:2];

            dut.u_datapath.u_regfile.regs[rs1_i] = r_rs1;
            dut.u_imem.mem[w_idx] = enc_addiu(rd_i, rs1_i, r_imm);
            #1;

            exp_v = (rd_i == 5'd0) ? 32'h0000_0000 : addiu_ref(r_rs1, r_imm);
            @(posedge clk);
            #1;

            act_v = dut.u_datapath.u_regfile.regs[rd_i];
            if ((act_v !== exp_v) || (dbg_pc !== (pc_prev + 32'd4))) begin
                $display("[FAIL] RAND_%0d: rd=x%0d rs1=%08h imm=%03h | Got=%08h Exp=%08h",
                         i, rd_i, r_rs1, r_imm, act_v, exp_v);
                fail_cnt++;
            end else begin
                pass_cnt++;
            end

            if (dbg_pc >= 32'd3600) reset_core();
        end

        // ---------------------------------------------------------------------
        // PHẦN C: BÁO CÁO COVERAGE & TỔNG KẾT (tb_addiu)
        // ---------------------------------------------------------------------
        $display("\n================================================================================");
        $display(" BAO CAO FUNCTIONAL COVERAGE CHO RV32I + ADDIU (tb_addiu)");
        $display("--------------------------------------------------------------------------------");
        $display(" 1. Immediate bins : 000(%0d) 001(%0d) 7FF(%0d) 800(%0d) FFF(%0d) | b11=0(%0d) b11=1(%0d)",
                 cov_imm_000, cov_imm_001, cov_imm_7ff, cov_imm_800, cov_imm_fff, cov_imm_bit11_0, cov_imm_bit11_1);
        $display(" 2. Operand bins   : zero(%0d) small(%0d) near_MAX(%0d) MIN(%0d) near_FFFF(%0d)",
                 cov_op_zero, cov_op_small, cov_op_max, cov_op_min, cov_op_all1);
        $display(" 3. Result bins    : unchanged(%0d) wrap(%0d) sign_flip(%0d) sign_same(%0d) | rd=x0(%0d) rd!=x0(%0d)",
                 cov_res_unchanged, cov_res_wrap, cov_res_sign_flip, cov_res_sign_same, cov_rd_x0, cov_rd_non_x0);
        $display(" 4. Write-Back MUX : WB_MEM(%0d) WB_ALU(%0d) WB_PC4(%0d) | Illegal Encoding(%0d)",
                 cov_wbsel[0], cov_wbsel[1], cov_wbsel[2], cov_illegal_enc);
        $display("================================================================================");
        $display(" TONG KET KIEM THU tb_addiu: PASS = %0d | FAIL = %0d | ASSERT_ERR = %0d",
                 pass_cnt, fail_cnt, assert_err);
        $display("================================================================================");

        if ((fail_cnt == 0) && (assert_err == 0) &&
            (cov_imm_000 > 0) && (cov_imm_7ff > 0) && (cov_imm_800 > 0) && (cov_imm_fff > 0) &&
            (cov_rd_x0 > 0) && (cov_rd_non_x0 > 0) && (cov_illegal_enc > 0))
            $display(" >>> ALL RV32I + ADDIU TESTS & COVERAGE GOALS PASSED SUCCESSFULLY! <<<");
        else
            $display(" >>> RV32I + ADDIU VERIFICATION FAILED OR COVERAGE INCOMPLETE! <<<");
        $finish;
    end

endmodule
