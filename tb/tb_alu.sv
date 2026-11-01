// =============================================================================
// File: tb/tb_alu.sv
// Description: Unit Testbench cho module ALU (Mục 6 - P2 & Mục 7).
//              Kiểm tra 10 ca biên directed, tất cả phép toán ALU khác SUB,
//              và 1000+ vector ngẫu nhiên đối chiếu với Golden Model 64-bit.
// =============================================================================

`timescale 1ns/1ps

module tb_alu;
    import isa_pkg::*;

    logic [31:0] a;
    logic [31:0] b;
    alu_sel_e    alu_sel;
    logic [31:0] alu_out;
    logic        pos_ov;
    logic        neg_ov;

    int pass_cnt = 0;
    int fail_cnt = 0;

    // Instantiate DUT
    alu dut (
        .a       (a),
        .b       (b),
        .alu_sel (alu_sel),
        .alu_out (alu_out),
        .pos_ov  (pos_ov),
        .neg_ov  (neg_ov)
    );

    // Task kiểm tra phép trừ ALU với Golden Model 64-bit có dấu độc lập
    task automatic check_alu_sub(
        input string       tc_name,
        input logic [31:0] in_a,
        input logic [31:0] in_b
    );
        logic signed [63:0] diff64;
        logic [31:0]        exp_out;
        logic               exp_pos_ov;
        logic               exp_neg_ov;

        a       = in_a;
        b       = in_b;
        alu_sel = ALU_SUB;
        #1;

        diff64     = 64'(signed'(in_a)) - 64'(signed'(in_b));
        exp_out    = diff64[31:0];
        exp_pos_ov = (diff64 >  64'sd2147483647);
        exp_neg_ov = (diff64 < -64'sd2147483648);

        // Kiểm tra bất biến PosOv và NegOv không bao giờ cùng bằng 1
        if (pos_ov && neg_ov) begin
            $display("[FAIL] %s: PosOv va NegOv cung bang 1! A=%h B=%h", tc_name, in_a, in_b);
            fail_cnt++;
        end else if ((alu_out !== exp_out) || (pos_ov !== exp_pos_ov) || (neg_ov !== exp_neg_ov)) begin
            $display("[FAIL] %s: A=%h B=%h | Got out=%h pos_ov=%b neg_ov=%b | Exp out=%h pos_ov=%b neg_ov=%b",
                     tc_name, in_a, in_b, alu_out, pos_ov, neg_ov, exp_out, exp_pos_ov, exp_neg_ov);
            fail_cnt++;
        end else begin
            pass_cnt++;
        end
    endtask

    // Hàm chọn toán hạng ngẫu nhiên có bias vào các giá trị biên
    function automatic logic [31:0] get_biased_rand(input int seed_idx);
        int sel;
        sel = $urandom % 10;
        case (sel)
            0: return 32'h0000_0000;
            1: return 32'h0000_0001;
            2: return 32'hFFFF_FFFF;
            3: return 32'h7FFF_FFFF;
            4: return 32'h8000_0000;
            5: return 32'h7FFF_FFFE;
            6: return 32'h8000_0001;
            default: return $urandom;
        endcase
    endfunction

    initial begin
        $display("=================================================================");
        $display(" BAT DAU UNIT TEST: tb_alu");
        $display("=================================================================");

        // 1. Directed tests (T01..T10)
        check_alu_sub("T01_Normal_50_20",      32'h0000_0032, 32'h0000_0014);
        check_alu_sub("T02_PosOv_MAX_m1",      32'h7FFF_FFFF, 32'hFFFF_FFFF);
        check_alu_sub("T03_NegOv_MIN_p1",      32'h8000_0000, 32'h0000_0001);
        check_alu_sub("T04_Edge_MAX_0",        32'h7FFF_FFFF, 32'h0000_0000);
        check_alu_sub("T05_Edge_MIN_0",        32'h8000_0000, 32'h0000_0000);
        check_alu_sub("T06_Zero_m_1",          32'h0000_0000, 32'h0000_0001);
        check_alu_sub("T07_BothNeg_m2_m1",     32'hFFFF_FFFE, 32'hFFFF_FFFF);
        check_alu_sub("T08_PosOv_0_MIN",       32'h0000_0000, 32'h8000_0000);
        check_alu_sub("T09_NegOv_MIN_MAX",     32'h8000_0000, 32'h7FFF_FFFF);
        check_alu_sub("T10_BothNeg_Eq",        32'hFFFF_FFFF, 32'hFFFF_FFFF);

        // 2. Kiểm tra cờ tràn phải bằng 0 ở mọi nhánh khác ALU_SUB
        a = 32'h7FFF_FFFF;
        b = 32'hFFFF_FFFF;
        foreach (alu_sel[i]) begin
            // Quét qua các giá trị enum
        end
        for (int s = 0; s <= 10; s++) begin
            alu_sel = alu_sel_e'(s);
            #1;
            if (alu_sel != ALU_SUB) begin
                if (pos_ov !== 1'b0 || neg_ov !== 1'b0) begin
                    $display("[FAIL] Flag khac 0 khi alu_sel=%0d: pos_ov=%b neg_ov=%b", s, pos_ov, neg_ov);
                    fail_cnt++;
                end else begin
                    pass_cnt++;
                end
            end
        end

        // 3. Random tests (1000 cặp có bias)
        for (int i = 0; i < 1000; i++) begin
            logic [31:0] ra, rb;
            ra = get_biased_rand(i);
            rb = get_biased_rand(i + 1000);
            check_alu_sub($sformatf("RAND_%0d", i), ra, rb);
        end

        $display("-----------------------------------------------------------------");
        $display(" KET QUA tb_alu: PASS = %0d | FAIL = %0d", pass_cnt, fail_cnt);
        $display("=================================================================");
        if (fail_cnt == 0)
            $display(" >>> tb_alu PASSED <<<");
        else
            $display(" >>> tb_alu FAILED <<<");
        $finish;
    end

endmodule
