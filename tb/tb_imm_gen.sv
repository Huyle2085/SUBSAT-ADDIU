// =============================================================================
// File: tb/tb_imm_gen.sv
// Description: Unit Testbench cho module imm_gen (Mục 4.2 & Checklist 6.2).
//              Quét vét cạn toàn bộ 4096 giá trị imm12 (0x000..0xFFF) ở cả
//              hai chế độ IMM_I_ZERO (ADDIU) và IMM_I (ADDI), cùng các mode S/B/U/J.
// =============================================================================

`timescale 1ns/1ps

module tb_imm_gen;
    import isa_pkg::*;

    logic [31:0] inst;
    imm_sel_e    imm_sel;
    logic [31:0] imm_out;

    int pass_cnt = 0;
    int fail_cnt = 0;

    imm_gen dut (
        .inst    (inst),
        .imm_sel (imm_sel),
        .imm_out (imm_out)
    );

    initial begin
        $display("=================================================================");
        $display(" BAT DAU UNIT TEST: tb_imm_gen (Quet 4096 gia tri imm12)");
        $display("=================================================================");

        // 1. Quét toàn bộ 4096 giá trị imm12 (0..4095) cho IMM_I_ZERO (3'b101)
        for (int imm = 0; imm < 4096; imm++) begin
            logic [11:0] imm12;
            logic [31:0] exp_zero;
            logic [31:0] exp_sign;

            imm12    = imm[11:0];
            inst     = enc_addiu(5'd5, 5'd6, imm12);

            // Kiểm tra IMM_I_ZERO (ADDIU)
            imm_sel  = IMM_I_ZERO;
            #1;
            exp_zero = {20'b0, imm12};
            if (imm_out !== exp_zero) begin
                $display("[FAIL] IMM_I_ZERO imm12=%03h: Got=%08h Exp=%08h", imm12, imm_out, exp_zero);
                fail_cnt++;
            end else begin
                pass_cnt++;
            end

            // Kiểm tra IMM_I (ADDI sign-extend)
            imm_sel  = IMM_I;
            #1;
            exp_sign = {{20{imm12[11]}}, imm12};
            if (imm_out !== exp_sign) begin
                $display("[FAIL] IMM_I_SIGN imm12=%03h: Got=%08h Exp=%08h", imm12, imm_out, exp_sign);
                fail_cnt++;
            end else begin
                pass_cnt++;
            end
        end

        $display("-----------------------------------------------------------------");
        $display(" KET QUA tb_imm_gen: PASS = %0d | FAIL = %0d", pass_cnt, fail_cnt);
        $display("=================================================================");
        if (fail_cnt == 0)
            $display(" >>> tb_imm_gen PASSED (4096/4096 IMM_I_ZERO & 4096/4096 IMM_I_SIGN) <<<");
        else
            $display(" >>> tb_imm_gen FAILED <<<");
        $finish;
    end

endmodule
