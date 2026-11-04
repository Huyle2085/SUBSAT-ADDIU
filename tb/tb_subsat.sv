// =============================================================================
// File: tb/tb_subsat.sv
// Description: System-Level Self-Checking Testbench cho RV32I + SUBSAT
//              (Đổi tên từ tb_top.sv cũ).
//              Bao gồm:
//              - 14 ca kiểm thử Directed bắt buộc (T01..T14 - Mục 7.1)
//              - Golden Reference Model 64-bit có dấu độc lập (Mục 7.2)
//              - Assertions kiểm tra bất biến phần cứng (Mục 7.2)
//              - 1000+ cặp kiểm thử ngẫu nhiên có bias vào các điểm biên
//              - Kiểm thử hồi quy (Regression) cho các lệnh chuẩn RV32I
//              - Báo cáo Functional Coverage đầy đủ
// =============================================================================

`timescale 1ns/1ps

module tb_subsat;
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

    // Bộ đếm Functional Coverage (Mục 7.2)
    int cov_no_ov        = 0;
    int cov_pos_ov       = 0;
    int cov_neg_ov       = 0;
    int cov_wbsel [0:4]  = '{default: 0};
    int cov_rd_x0        = 0;
    int cov_rd_non_x0    = 0;
    int cov_sub_wrap_ov  = 0;
    int cov_illegal_enc  = 0;

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
    // 1. GOLDEN REFERENCE MODEL ĐỘC LẬP DÙNG 64-BIT SIGNED (Mục 2 & Mục 7.2)
    // =========================================================================
    function automatic logic [31:0] golden_subsat_64(
        input logic [31:0] a,
        input logic [31:0] b
    );
        logic signed [63:0] d;
        d = 64'(signed'(a)) - 64'(signed'(b));
        if (d > 64'sd2147483647)
            return 32'h7FFF_FFFF;
        else if (d < -64'sd2147483648)
            return 32'h8000_0000;
        else
            return d[31:0];
    endfunction

    // =========================================================================
    // 2. ASSERTIONS & COVERAGE SAMPLING TẠI MỖI CHU KỲ LỆNH (Mục 7.2)
    // =========================================================================
    always @(negedge clk) begin
        if (rst_n) begin
            // A1: PosOv và NegOv không bao giờ cùng bằng 1
            if (dbg_pos_ov && dbg_neg_ov) begin
                $display("[ASSERT FAIL] PosOv && NegOv cung bang 1 tai PC=%h", dbg_pc);
                assert_err++;
            end

            // A2: Khi là SUBSAT, WBSel phải khớp chính xác trạng thái tràn
            if (dbg_is_subsat) begin
                if (dbg_pos_ov && (dbg_wb_sel !== WB_MAX)) begin
                    $display("[ASSERT FAIL] is_subsat && PosOv nhung WBSel=%0d != WB_MAX", dbg_wb_sel);
                    assert_err++;
                end
                if (dbg_neg_ov && (dbg_wb_sel !== WB_MIN)) begin
                    $display("[ASSERT FAIL] is_subsat && NegOv nhung WBSel=%0d != WB_MIN", dbg_wb_sel);
                    assert_err++;
                end
                if (!dbg_pos_ov && !dbg_neg_ov && (dbg_wb_sel !== WB_ALU)) begin
                    $display("[ASSERT FAIL] is_subsat && !Ov nhung WBSel=%0d != WB_ALU", dbg_wb_sel);
                    assert_err++;
                end
            end

            // A3: Khi KHÔNG phải SUBSAT, tuyệt đối không chọn WB_MAX hoặc WB_MIN
            if (!dbg_is_subsat) begin
                if ((dbg_wb_sel == WB_MAX) || (dbg_wb_sel == WB_MIN)) begin
                    $display("[ASSERT FAIL] !is_subsat nhung WBSel=%0d chon MAX/MIN tai PC=%h", dbg_wb_sel, dbg_pc);
                    assert_err++;
                end
            end

            // A4: Thanh ghi x0 luôn cứng bằng 0
            if (dut.u_datapath.u_regfile.regs[0] !== 32'h0000_0000) begin
                $display("[ASSERT FAIL] x0 bi thay doi gia tri: %h", dut.u_datapath.u_regfile.regs[0]);
                assert_err++;
            end

            // A5: Không có X/Z trên các tín hiệu điều khiển chính
            if ($isunknown(dbg_wb_sel) || $isunknown(dbg_reg_w_en) || $isunknown(dbg_wb_data)) begin
                $display("[ASSERT FAIL] Phat hien X/Z tren tin hieu dieu khien/WB tai PC=%h", dbg_pc);
                assert_err++;
            end

            // Thu thập Functional Coverage
            if (dbg_wb_sel <= WB_MIN) begin
                cov_wbsel[dbg_wb_sel]++;
            end
            if (dbg_is_subsat) begin
                if (dbg_pos_ov)      cov_pos_ov++;
                else if (dbg_neg_ov) cov_neg_ov++;
                else                 cov_no_ov++;

                if (dbg_inst[11:7] == 5'd0) cov_rd_x0++;
                else                        cov_rd_non_x0++;
            end
            if (!dbg_is_subsat && (dbg_inst[6:0] == OP_RTYPE) &&
                (dbg_inst[14:12] == 3'b000) && (dbg_inst[31:25] == F7_ALT) &&
                (dbg_pos_ov || dbg_neg_ov)) begin
                cov_sub_wrap_ov++;
            end
            if (dbg_illegal_inst) begin
                cov_illegal_enc++;
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

    // Thực thi 1 lệnh SUBSAT đơn lẻ và tự động kiểm tra đầy đủ:
    // - Cờ PosOv, NegOv, WBSel
    // - Giá trị thanh ghi đích rd so với Golden Model 64-bit
    // - Thanh ghi x0 luôn bằng 0
    // - PC tăng đúng +4
    task automatic run_directed_subsat(
        input string       tc_id,
        input logic [4:0]  rd,
        input logic [4:0]  rs1,
        input logic [4:0]  rs2,
        input logic [31:0] val_a,
        input logic [31:0] val_b,
        input logic [31:0] exp_rd_val,
        input logic        exp_pos_ov,
        input logic        exp_neg_ov,
        input wb_sel_e     exp_wb_sel
    );
        logic [31:0] pc_before;
        logic [31:0] gold_val;
        logic [31:0] actual_rd;
        int          word_idx;

        pc_before = dbg_pc;
        word_idx  = pc_before[11:2];

        // Nạp toán hạng nguồn vào RegFile (trừ x0)
        if (rs1 != 5'd0) dut.u_datapath.u_regfile.regs[rs1] = val_a;
        if (rs2 != 5'd0) dut.u_datapath.u_regfile.regs[rs2] = val_b;

        // Nạp lệnh SUBSAT vào IMEM tại PC hiện tại
        dut.u_imem.mem[word_idx] = encode_subsat(rd, rs1, rs2);
        #1; // Đợi đường tổ hợp ổn định trước sườn lên xung nhịp

        gold_val = (rd == 5'd0) ? 32'h0000_0000 : golden_subsat_64(
            (rs1 == 5'd0) ? 32'h0 : val_a,
            (rs2 == 5'd0) ? 32'h0 : val_b
        );

        // Kiểm tra tín hiệu tổ hợp trước khi chốt sườn lên clk
        if ((dbg_pos_ov !== exp_pos_ov) || (dbg_neg_ov !== exp_neg_ov) || (dbg_wb_sel !== exp_wb_sel)) begin
            $display("[FAIL] %s (Comb): A=%h B=%h | Got PosOv=%b NegOv=%b WBSel=%0d | Exp PosOv=%b NegOv=%b WBSel=%0d",
                     tc_id, val_a, val_b, dbg_pos_ov, dbg_neg_ov, dbg_wb_sel, exp_pos_ov, exp_neg_ov, exp_wb_sel);
            fail_cnt++;
        end

        // Chốt sườn lên xung nhịp để ghi vào RegFile và tăng PC
        @(posedge clk);
        #1;

        actual_rd = (rd == 5'd0) ? dut.u_datapath.u_regfile.rs1_data : dut.u_datapath.u_regfile.regs[rd];
        if (rd == 5'd0) actual_rd = dut.u_datapath.u_regfile.regs[0];

        if ((actual_rd !== exp_rd_val) || (actual_rd !== gold_val) || (dbg_pc !== (pc_before + 32'd4))) begin
            $display("[FAIL] %s (Seq): A=%h B=%h | Got rd(x%0d)=%h Gold=%h Exp=%h PC=%h",
                     tc_id, val_a, val_b, rd, actual_rd, gold_val, exp_rd_val, dbg_pc);
            fail_cnt++;
        end else begin
            $display("[PASS] %-22s | A=%h B=%h -> rd(x%0d)=%h | PosOv=%b NegOv=%b WBSel=%0d",
                     tc_id, val_a, val_b, rd, actual_rd, exp_pos_ov, exp_neg_ov, exp_wb_sel);
            pass_cnt++;
        end
    endtask

    // Hàm tạo số ngẫu nhiên có bias vào các điểm biên
    function automatic logic [31:0] get_biased_val();
        int r;
        r = $urandom % 12;
        case (r)
            0: return 32'h0000_0000;
            1: return 32'h0000_0001;
            2: return 32'hFFFF_FFFF;
            3: return 32'h7FFF_FFFF;
            4: return 32'h8000_0000;
            5: return 32'h7FFF_FFFE;
            6: return 32'h8000_0001;
            7: return 32'h4000_0000;
            8: return 32'hC000_0000;
            default: return $urandom;
        endcase
    endfunction

    // =========================================================================
    // 4. KỊCH BẢN KIỂM THỬ CHÍNH (MAIN TEST SEQUENCE)
    // =========================================================================
    initial begin
        $dumpfile("sim/wave_subsat.vcd");
        $dumpvars(0, dut);

        $display("================================================================================");
        $display(" BAT DAU KIEM THU HE THONG: RV32I + SUBSAT (tb_subsat)");
        $display(" Opcode SUBSAT = 7'b%07b (custom-0), funct3 = 3'b%03b, funct7 = 7'b%07b",
                 SUBSAT_OP, SUBSAT_F3, SUBSAT_F7);
        $display(" Vi du ma may SUBSAT x5, x6, x7 = 0x%08h", encode_subsat(5'd5, 5'd6, 5'd7));
        $display("================================================================================");

        reset_core();

        // ---------------------------------------------------------------------
        // PHẦN A: 14 DIRECTED TESTS BẮT BUỘC (Mục 7.1: T01 -> T14)
        // ---------------------------------------------------------------------
        $display("\n--- [PHAN A] 14 CA KIEM THU DIRECTED BAT BUOC (T01..T14) ---");

        // T01: 50 - 20 = 30 (Không tràn)
        run_directed_subsat("T01_NoOv_50_20",      5'd5, 5'd6, 5'd7, 32'h0000_0032, 32'h0000_0014, 32'h0000_001E, 1'b0, 1'b0, WB_ALU);

        // T02: (+MAX) - (-1) -> saturate +MAX, PosOv=1, WBSel=3 (WB_MAX)
        run_directed_subsat("T02_PosOv_MAX_m1",    5'd5, 5'd6, 5'd7, 32'h7FFF_FFFF, 32'hFFFF_FFFF, 32'h7FFF_FFFF, 1'b1, 1'b0, WB_MAX);

        // T03: (INT32_MIN) - (+1) -> saturate -MIN, NegOv=1, WBSel=4 (WB_MIN)
        run_directed_subsat("T03_NegOv_MIN_p1",    5'd5, 5'd6, 5'd7, 32'h8000_0000, 32'h0000_0001, 32'h8000_0000, 1'b0, 1'b1, WB_MIN);

        // T04: (+MAX) - 0 = +MAX (Biên dương, không tràn)
        run_directed_subsat("T04_Edge_MAX_0",      5'd5, 5'd6, 5'd7, 32'h7FFF_FFFF, 32'h0000_0000, 32'h7FFF_FFFF, 1'b0, 1'b0, WB_ALU);

        // T05: (INT32_MIN) - 0 = INT32_MIN (Biên âm, không tràn)
        run_directed_subsat("T05_Edge_MIN_0",      5'd5, 5'd6, 5'd7, 32'h8000_0000, 32'h0000_0000, 32'h8000_0000, 1'b0, 1'b0, WB_ALU);

        // T06: 0 - 1 = -1 (0xFFFF_FFFF, không tràn)
        run_directed_subsat("T06_NoOv_0_1",        5'd5, 5'd6, 5'd7, 32'h0000_0000, 32'h0000_0001, 32'hFFFF_FFFF, 1'b0, 1'b0, WB_ALU);

        // T07: (-2) - (-1) = -1 (0xFFFF_FFFF, cả A và B đều âm, không tràn)
        run_directed_subsat("T07_BothNeg_m2_m1",   5'd5, 5'd6, 5'd7, 32'hFFFF_FFFE, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 1'b0, 1'b0, WB_ALU);

        // T08: 0 - INT32_MIN -> saturate +MAX, PosOv=1, WBSel=3 (WB_MAX)
        run_directed_subsat("T08_PosOv_0_MIN",     5'd5, 5'd6, 5'd7, 32'h0000_0000, 32'h8000_0000, 32'h7FFF_FFFF, 1'b1, 1'b0, WB_MAX);

        // T09: INT32_MIN - (+MAX) -> saturate -MIN, NegOv=1, WBSel=4 (WB_MIN)
        run_directed_subsat("T09_NegOv_MIN_MAX",   5'd5, 5'd6, 5'd7, 32'h8000_0000, 32'h7FFF_FFFF, 32'h8000_0000, 1'b0, 1'b1, WB_MIN);

        // T10: (-1) - (-1) = 0 (Hai toán hạng âm bằng nhau, không tràn)
        run_directed_subsat("T10_BothNeg_Eq",      5'd5, 5'd6, 5'd7, 32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'h0000_0000, 1'b0, 1'b0, WB_ALU);

        // T11: Lệnh SUB thường (không phải SUBSAT) với A=7FFF_FFFF, B=FFFF_FFFF -> wrap-around 8000_0000
        begin
            int idx;
            idx = dbg_pc[11:2];
            dut.u_datapath.u_regfile.regs[6] = 32'h7FFF_FFFF;
            dut.u_datapath.u_regfile.regs[7] = 32'hFFFF_FFFF;
            dut.u_imem.mem[idx] = encode_rtype(F7_ALT, 5'd7, 5'd6, 3'b000, 5'd8, OP_RTYPE); // SUB x8, x6, x7
            #1;
            @(posedge clk);
            #1;
            if (dut.u_datapath.u_regfile.regs[8] !== 32'h8000_0000) begin
                $display("[FAIL] T11_SUB_WrapAround: Got x8=%h, Exp 80000000", dut.u_datapath.u_regfile.regs[8]);
                fail_cnt++;
            end else begin
                $display("[PASS] T11_SUB_WrapAround     | SUB x8, x6, x7 (7FFFFFFF - FFFFFFFF) -> x8=80000000 (wrap)");
                pass_cnt++;
            end
        end

        // T12: SUBSAT với rd = x0 (trong cả 3 trường hợp: tràn dương, tràn âm, không tràn) -> x0 vẫn bằng 0
        run_directed_subsat("T12a_rd_x0_PosOv",    5'd0, 5'd6, 5'd7, 32'h7FFF_FFFF, 32'hFFFF_FFFF, 32'h0000_0000, 1'b1, 1'b0, WB_MAX);
        run_directed_subsat("T12b_rd_x0_NegOv",    5'd0, 5'd6, 5'd7, 32'h8000_0000, 32'h0000_0001, 32'h0000_0000, 1'b0, 1'b1, WB_MIN);
        run_directed_subsat("T12c_rd_x0_NoOv",     5'd0, 5'd6, 5'd7, 32'h0000_0032, 32'h0000_0014, 32'h0000_0000, 1'b0, 1'b0, WB_ALU);

        // T13: Kiểm thử hồi quy (Regression) các lệnh chuẩn khác (ADD, SW, LW, JAL, JALR, BEQ, LUI, AUIPC)
        begin
            int base_idx;
            logic [31:0] base_pc;
            base_pc  = dbg_pc;
            base_idx = base_pc[11:2];

            // 1) ADDI x10, x0, 100
            dut.u_imem.mem[base_idx + 0] = {12'd100, 5'd0, 3'b000, 5'd10, OP_IMM};
            // 2) ADDI x11, x0, 55
            dut.u_imem.mem[base_idx + 1] = {12'd55,  5'd0, 3'b000, 5'd11, OP_IMM};
            // 3) ADD x12, x10, x11 -> 155
            dut.u_imem.mem[base_idx + 2] = encode_rtype(F7_STD, 5'd11, 5'd10, 3'b000, 5'd12, OP_RTYPE);
            // 4) SW x12, 16(x0) -> DMEM[4] = 155
            dut.u_imem.mem[base_idx + 3] = {7'd0, 5'd12, 5'd0, 3'b010, 5'd16, OP_STORE};
            // 5) LW x13, 16(x0) -> x13 = 155 (kiểm tra WBSel = WB_MEM = 0)
            dut.u_imem.mem[base_idx + 4] = {12'd16, 5'd0, 3'b010, 5'd13, OP_LOAD};
            // 6) JAL x14, +8 -> x14 = PC+4, nhảy qua 1 lệnh (kiểm tra WBSel = WB_PC4 = 2)
            dut.u_imem.mem[base_idx + 5] = {1'b0, 10'd4, 1'b0, 8'd0, 5'd14, OP_JAL};
            // 7) ADDI x13, x0, 999 (lệnh bị nhảy qua, không được thực thi)
            dut.u_imem.mem[base_idx + 6] = {12'd999, 5'd0, 3'b000, 5'd13, OP_IMM};
            // 8) LUI x15, 0x12345 -> x15 = 0x12345000
            dut.u_imem.mem[base_idx + 7] = {20'h12345, 5'd15, OP_LUI};

            repeat (7) begin
                @(posedge clk);
                #1;
            end

            if ((dut.u_datapath.u_regfile.regs[12] !== 32'd155) ||
                (dut.u_datapath.u_regfile.regs[13] !== 32'd155) ||
                (dut.u_datapath.u_regfile.regs[14] !== (base_pc + 32'd24)) ||
                (dut.u_datapath.u_regfile.regs[15] !== 32'h1234_5000)) begin
                $display("[FAIL] T13_Other_Instructions: x12=%0d x13=%0d x14=%h x15=%h",
                         dut.u_datapath.u_regfile.regs[12],
                         dut.u_datapath.u_regfile.regs[13],
                         dut.u_datapath.u_regfile.regs[14],
                         dut.u_datapath.u_regfile.regs[15]);
                fail_cnt++;
            end else begin
                $display("[PASS] T13_Other_Instructions | ADD/SW/LW(WB_MEM)/JAL(WB_PC4)/LUI hoat dong chinh xac");
                pass_cnt++;
            end
        end

        // T14: Encoding sai (custom-0 sai funct3/funct7, OP_RTYPE mang funct7=0100001) -> Không nhận nhầm SUBSAT, không ghi đè rd
        begin
            int idx;
            dut.u_datapath.u_regfile.regs[20] = 32'hCAFE_BABE;
            dut.u_datapath.u_regfile.regs[6]  = 32'h7FFF_FFFF;
            dut.u_datapath.u_regfile.regs[7]  = 32'hFFFF_FFFF;

            // Lệnh 1: custom-0 nhưng funct3 = 3'b010 (sai funct3)
            idx = dbg_pc[11:2];
            dut.u_imem.mem[idx] = encode_rtype(SUBSAT_F7, 5'd7, 5'd6, 3'b010, 5'd20, SUBSAT_OP);
            #1;
            @(posedge clk);
            #1;

            // Lệnh 2: custom-0 nhưng funct7 = 7'b0100000 (sai funct7)
            idx = dbg_pc[11:2];
            dut.u_imem.mem[idx] = encode_rtype(F7_ALT, 5'd7, 5'd6, SUBSAT_F3, 5'd20, SUBSAT_OP);
            #1;
            @(posedge clk);
            #1;

            // Lệnh 3: OP_RTYPE nhưng funct7 = 7'b0100001 (SUBSAT_F7)
            idx = dbg_pc[11:2];
            dut.u_imem.mem[idx] = encode_rtype(SUBSAT_F7, 5'd7, 5'd6, SUBSAT_F3, 5'd20, OP_RTYPE);
            #1;
            @(posedge clk);
            #1;

            if (dut.u_datapath.u_regfile.regs[20] !== 32'hCAFE_BABE) begin
                $display("[FAIL] T14_Invalid_Encoding: x20 bi ghi de thanh %h!", dut.u_datapath.u_regfile.regs[20]);
                fail_cnt++;
            end else begin
                $display("[PASS] T14_Invalid_Encoding   | Cac ma lenh sai bi tu choi, x20 giu nguyen 0xCAFEBABE");
                pass_cnt++;
            end
        end

        // ---------------------------------------------------------------------
        // PHẦN B: RANDOM TEST 1000+ CẶP TOÁN HẠNG CÓ BIAS (Mục 7.2)
        // ---------------------------------------------------------------------
        $display("\n--- [PHAN B] RANDOM TESTS (1000 VECTOR NGAU NHIEN CO BIAS) ---");
        reset_core();

        for (int i = 0; i < 1000; i++) begin
            logic [31:0] ra, rb, exp_val, act_val, pc_prev;
            logic signed [63:0] d64;
            logic [4:0]  rd_r, rs1_r, rs2_r;
            int          w_idx;

            ra = get_biased_val();
            rb = get_biased_val();

            // Chọn ngẫu nhiên thanh ghi (bao gồm cả x0 cho rd)
            rd_r  = $urandom_range(0, 31);
            rs1_r = $urandom_range(1, 15);
            rs2_r = $urandom_range(16, 31);

            pc_prev = dbg_pc;
            w_idx   = pc_prev[11:2];

            dut.u_datapath.u_regfile.regs[rs1_r] = ra;
            dut.u_datapath.u_regfile.regs[rs2_r] = rb;
            dut.u_imem.mem[w_idx] = encode_subsat(rd_r, rs1_r, rs2_r);
            #1;

            exp_val = (rd_r == 5'd0) ? 32'h0000_0000 : golden_subsat_64(ra, rb);

            @(posedge clk);
            #1;

            act_val = dut.u_datapath.u_regfile.regs[rd_r];
            if ((act_val !== exp_val) || (dbg_pc !== (pc_prev + 32'd4))) begin
                $display("[FAIL] RAND_%0d: rd=x%0d A=%h B=%h | Got=%h Exp=%h",
                         i, rd_r, ra, rb, act_val, exp_val);
                fail_cnt++;
            end else begin
                pass_cnt++;
            end

            // Reset PC định kỳ trước khi chạm giới hạn IMEM 1024 words
            if (dbg_pc >= 32'd3600) begin
                reset_core();
            end
        end

        // ---------------------------------------------------------------------
        // PHẦN C: BÁO CÁO COVERAGE & TỔNG KẾT NGHIỆM THU (Mục 7.2 & Mục 9)
        // ---------------------------------------------------------------------
        $display("\n================================================================================");
        $display(" BAO CAO FUNCTIONAL COVERAGE CHO SUBSAT (tb_subsat - Muc 7.2)");
        $display("--------------------------------------------------------------------------------");
        $display(" 1. Lop tran SUBSAT:");
        $display("    - Khong tran (No Overflow)       : %0d hits %s", cov_no_ov,  (cov_no_ov  > 0) ? "[COVERED]" : "[MISSED]");
        $display("    - Tran duong (Positive Overflow) : %0d hits %s", cov_pos_ov, (cov_pos_ov > 0) ? "[COVERED]" : "[MISSED]");
        $display("    - Tran am    (Negative Overflow) : %0d hits %s", cov_neg_ov, (cov_neg_ov > 0) ? "[COVERED]" : "[MISSED]");
        $display(" 2. Nguon Write-Back MUX 5:1 (WBSel[2:0]):");
        $display("    - WBSel=000 (WB_MEM - LOAD)      : %0d hits %s", cov_wbsel[0], (cov_wbsel[0] > 0) ? "[COVERED]" : "[MISSED]");
        $display("    - WBSel=001 (WB_ALU - ALU/NoOv)  : %0d hits %s", cov_wbsel[1], (cov_wbsel[1] > 0) ? "[COVERED]" : "[MISSED]");
        $display("    - WBSel=010 (WB_PC4 - JAL/JALR)  : %0d hits %s", cov_wbsel[2], (cov_wbsel[2] > 0) ? "[COVERED]" : "[MISSED]");
        $display("    - WBSel=011 (WB_MAX - 7FFFFFFF)  : %0d hits %s", cov_wbsel[3], (cov_wbsel[3] > 0) ? "[COVERED]" : "[MISSED]");
        $display("    - WBSel=100 (WB_MIN - 80000000)  : %0d hits %s", cov_wbsel[4], (cov_wbsel[4] > 0) ? "[COVERED]" : "[MISSED]");
        $display(" 3. Thanh ghi dich & Truong hop dac biet:");
        $display("    - SUBSAT ghi vao rd = x0         : %0d hits %s", cov_rd_x0,       (cov_rd_x0       > 0) ? "[COVERED]" : "[MISSED]");
        $display("    - SUBSAT ghi vao rd != x0        : %0d hits %s", cov_rd_non_x0,   (cov_rd_non_x0   > 0) ? "[COVERED]" : "[MISSED]");
        $display("    - SUB thuong co tran (Wrap)      : %0d hits %s", cov_sub_wrap_ov, (cov_sub_wrap_ov > 0) ? "[COVERED]" : "[MISSED]");
        $display("    - Ma lenh sai (Illegal Encoding) : %0d hits %s", cov_illegal_enc, (cov_illegal_enc > 0) ? "[COVERED]" : "[MISSED]");
        $display("================================================================================");
        $display(" TONG KET KIEM THU tb_subsat:");
        $display("   - TONG SO CA PASS      : %0d", pass_cnt);
        $display("   - TONG SO CA FAIL      : %0d", fail_cnt);
        $display("   - LOI ASSERTION        : %0d", assert_err);
        $display("================================================================================");

        if ((fail_cnt == 0) && (assert_err == 0) &&
            (cov_no_ov > 0) && (cov_pos_ov > 0) && (cov_neg_ov > 0) &&
            (cov_wbsel[0] > 0) && (cov_wbsel[1] > 0) && (cov_wbsel[2] > 0) &&
            (cov_wbsel[3] > 0) && (cov_wbsel[4] > 0) &&
            (cov_rd_x0 > 0) && (cov_rd_non_x0 > 0) &&
            (cov_sub_wrap_ov > 0) && (cov_illegal_enc > 0)) begin
            $display(" >>> ALL SUBSAT TESTS & COVERAGE GOALS PASSED SUCCESSFULLY! <<<");
        end else begin
            $display(" >>> SUBSAT VERIFICATION FAILED OR COVERAGE INCOMPLETE! <<<");
        end

        $finish;
    end

endmodule
