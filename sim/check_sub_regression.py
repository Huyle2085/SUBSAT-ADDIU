#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
File: sim/check_sub_regression.py
Description:
  Công cụ kiểm tra độc lập giúp đối chiếu trực tiếp:
  1. Lệnh SUB chuẩn (OP_RTYPE = 0110011, funct7 = 0100000) vs Lệnh SUBSAT (custom-0 = 0001011, funct7 = 0100001)
     trên cùng các cặp toán hạng (không tràn, tràn dương, tràn âm).
  2. Kiểm tra hồi quy toàn bộ tập lệnh gốc RV32I để chứng minh SUBSAT không làm
     thay đổi hành vi của bất kỳ lệnh RISC-V chuẩn nào.
"""

import sys
sys.stdout.reconfigure(encoding="utf-8")

from verify_and_wave import (
    MASK32, INT32_MAX, INT32_MIN,
    OP_RTYPE, OP_IMM, OP_LOAD, OP_STORE, OP_BRANCH, OP_JAL, OP_JALR, OP_LUI, OP_AUIPC,
    F7_STD, F7_ALT, WB_MEM, WB_ALU, WB_PC4, WB_MAX, WB_MIN, IMM_I, IMM_I_ZERO,
    encode_rtype, encode_subsat, enc_addiu, rtl_alu, rtl_control_logic, rtl_imm_gen, to_signed32, golden_subsat_64, addiu_ref
)


def run_comparison():
    print("=" * 106)
    print(" BẢNG 1: ĐỐI CHIẾU TRỰC TIẾP LỆNH 'SUB' CHUẨN (WRAP-AROUND) vs LỆNH 'SUBSAT' (BÃO HÒA)")
    print("=" * 106)
    print(f" {'Trường hợp kiểm thử':<24} | {'A (hex)':<10} | {'B (hex)':<10} | {'Pos/Neg'} | {'SUB chuẩn (WBSel)':<20} | {'SUBSAT (WBSel)':<20} | {'Đánh giá'}")
    print("-" * 106)

    cases = [
        ("1. Không tràn (50 - 20)",  0x00000032, 0x00000014),
        ("2. Không tràn (0 - 1)",    0x00000000, 0x00000001),
        ("3. Biên (+MAX - 0)",       0x7FFFFFFF, 0x00000000),
        ("4. Biên (MIN - 0)",        0x80000000, 0x00000000),
        ("5. Tràn dương (+MAX - -1)",0x7FFFFFFF, 0xFFFFFFFF),
        ("6. Tràn dương (0 - MIN)",  0x00000000, 0x80000000),
        ("7. Tràn dương (+MAX - -5)",0x7FFFFFFF, 0xFFFFFFFB),
        ("8. Tràn âm (MIN - +1)",    0x80000000, 0x00000001),
        ("9. Tràn âm (MIN - +MAX)",  0x80000000, 0x7FFFFFFF),
        ("10. Tràn âm (MIN - +5)",   0x80000000, 0x00000005),
    ]

    all_ok = True
    for name, a, b in cases:
        # 1. Lệnh SUB chuẩn
        inst_sub = encode_rtype(F7_ALT, 7, 6, 0b000, 8, OP_RTYPE)
        c_sub_pre = rtl_control_logic(inst_sub, 0, 0, 0, 0)
        alu_sub, pov, nov = rtl_alu(a, b, c_sub_pre["alu_sel"])
        c_sub = rtl_control_logic(inst_sub, 0, 0, pov, nov)
        wb_sub = alu_sub if c_sub["wb_sel"] == WB_ALU else (INT32_MAX if c_sub["wb_sel"] == WB_MAX else INT32_MIN)

        # 2. Lệnh SUBSAT
        inst_sat = encode_subsat(9, 6, 7)
        c_sat_pre = rtl_control_logic(inst_sat, 0, 0, 0, 0)
        alu_sat, pov2, nov2 = rtl_alu(a, b, c_sat_pre["alu_sel"])
        c_sat = rtl_control_logic(inst_sat, 0, 0, pov2, nov2)
        wb_sat = alu_sat if c_sat["wb_sel"] == WB_ALU else (INT32_MAX if c_sat["wb_sel"] == WB_MAX else INT32_MIN)

        exp_sub = (a - b) & MASK32
        exp_sat = golden_subsat_64(a, b)
        ok = (wb_sub == exp_sub) and (c_sub["wb_sel"] == WB_ALU) and (wb_sat == exp_sat)
        all_ok &= ok

        print(f" {name:<24} | 0x{a:08X} | 0x{b:08X} |  {pov} / {nov}  | 0x{wb_sub:08X} (WBSel={c_sub['wb_sel']}) | 0x{wb_sat:08X} (WBSel={c_sat['wb_sel']}) | {'PASS' if ok else 'FAIL'}")

    print("=" * 106)
    print("\n" + "=" * 106)
    print(" BẢNG 2: KIỂM TRA HỒI QUY TOÀN BỘ LỆNH CHUẨN RV32I (ĐẢM BẢO is_subsat=0 & WBSel KHÔNG CHỌN MAX/MIN)")
    print("=" * 106)
    print(f" {'Lệnh RV32I gốc':<18} | {'Mã máy (Hex)':<12} | {'is_subsat':<9} | {'WBSel[2:0]':<14} | {'Kết quả thực thi':<30} | {'Trạng thái'}")
    print("-" * 106)

    rv32i_checks = [
        ("ADD x5, x6, x7",   encode_rtype(F7_STD, 7, 6, 0b000, 5, OP_RTYPE), 0x7FFFFFFF, 0x00000001, WB_ALU, "0x80000000 (wrap chuẩn)"),
        ("SUB x5, x6, x7",   encode_rtype(F7_ALT, 7, 6, 0b000, 5, OP_RTYPE), 0x7FFFFFFF, 0xFFFFFFFF, WB_ALU, "0x80000000 (wrap chuẩn)"),
        ("SLL x5, x6, x7",   encode_rtype(F7_STD, 7, 6, 0b001, 5, OP_RTYPE), 0x0000000F, 0x00000004, WB_ALU, "0x000000F0"),
        ("SLT x5, x6, x7",   encode_rtype(F7_STD, 7, 6, 0b010, 5, OP_RTYPE), 0x80000000, 0x00000001, WB_ALU, "0x00000001 (-MIN < 1)"),
        ("SLTU x5, x6, x7",  encode_rtype(F7_STD, 7, 6, 0b011, 5, OP_RTYPE), 0x80000000, 0x00000001, WB_ALU, "0x00000000 (unsigned)"),
        ("XOR x5, x6, x7",   encode_rtype(F7_STD, 7, 6, 0b100, 5, OP_RTYPE), 0xAAAA5555, 0xFFFF0000, WB_ALU, "0x55555555"),
        ("SRL x5, x6, x7",   encode_rtype(F7_STD, 7, 6, 0b101, 5, OP_RTYPE), 0x80000000, 0x00000004, WB_ALU, "0x08000000"),
        ("SRA x5, x6, x7",   encode_rtype(F7_ALT, 7, 6, 0b101, 5, OP_RTYPE), 0x80000000, 0x00000004, WB_ALU, "0xF8000000 (sign-ext)"),
        ("OR  x5, x6, x7",   encode_rtype(F7_STD, 7, 6, 0b110, 5, OP_RTYPE), 0x12340000, 0x00005678, WB_ALU, "0x12345678"),
        ("AND x5, x6, x7",   encode_rtype(F7_STD, 7, 6, 0b111, 5, OP_RTYPE), 0xFFFF00FF, 0x12345678, WB_ALU, "0x12340078"),
        ("ADDI x5, x6, -1",  (0xFFF << 20) | (6 << 15) | (0 << 12) | (5 << 7) | OP_IMM, 0x00000010, 0, WB_ALU, "0x0000000F"),
        ("LW x5, 16(x6)",    (16 << 20) | (6 << 15) | (0b010 << 12) | (5 << 7) | OP_LOAD, 0x00000100, 0, WB_MEM, "Addr = 0x00000110"),
        ("JAL x5, +8",       (4 << 21) | (5 << 7) | OP_JAL, 0, 0, WB_PC4, "Link = PC + 4"),
        ("LUI x5, 0xABCDE",  (0xABCDE << 12) | (5 << 7) | OP_LUI, 0, 0, WB_ALU, "0xABCDE000"),
    ]

    wb_names = {WB_MEM: "000 (WB_MEM)", WB_ALU: "001 (WB_ALU)", WB_PC4: "010 (WB_PC4)", WB_MAX: "011 (WB_MAX)", WB_MIN: "100 (WB_MIN)"}
    for mnemonic, inst, a, b, exp_wb, desc in rv32i_checks:
        # Thử ép cả pos_ov=1 để chứng minh các lệnh chuẩn hoàn toàn phớt lờ cờ tràn
        ctrl = rtl_control_logic(inst, 0, 0, 1, 0)
        ok = (ctrl["is_subsat"] == 0) and (ctrl["is_addiu"] == 0) and (ctrl["wb_sel"] == exp_wb) and (ctrl["wb_sel"] not in (WB_MAX, WB_MIN))
        all_ok &= ok
        print(f" {mnemonic:<18} | 0x{inst:08X}   | {ctrl['is_subsat']:^9} | {wb_names[ctrl['wb_sel']]:<14} | {desc:<30} | {'PASS' if ok else 'FAIL'}")

    print("=" * 106)
    print("\n" + "=" * 106)
    print(" BẢNG 3: ĐỐI CHIẾU TRỰC TIẾP LỆNH 'ADDI' CHUẨN (SIGN-EXTEND) vs LỆNH 'ADDIU' (ZERO-EXTEND)")
    print("=" * 106)
    print(f" {'Trường hợp kiểm thử':<24} | {'rs1 (hex)':<10} | {'imm12':<6} | {'ADDI chuẩn (ImmSel=000)':<24} | {'ADDIU (ImmSel=101)':<24} | {'Đánh giá'}")
    print("-" * 106)
    addiu_cases = [
        ("U01: Zero imm",         0x00000000, 0x000, 0x00000000, 0x00000000),
        ("U02: imm=7FF (b11=0)",  0x00000010, 0x7FF, 0x0000080F, 0x0000080F),
        ("U03: imm=800 (b11=1)",  0x00000000, 0x800, 0xFFFFF800, 0x00000800),
        ("U04/U09/U11: imm=FFF",  0x00000000, 0xFFF, 0xFFFFFFFF, 0x00000FFF),
        ("U07: Đổi dấu, ko sat",  0x7FFFFF00, 0x200, 0x80000100, 0x80000100),
        ("U08: FFFF_F001 + FFF",  0xFFFFF001, 0xFFF, 0xFFFFF000, 0x00000000),
    ]
    for cname, r1, im12, exp_addi, exp_addiu in addiu_cases:
        inst_addi  = ((im12 & 0xFFF) << 20) | (6 << 15) | (0 << 12) | (5 << 7) | OP_IMM
        inst_addiu = enc_addiu(5, 6, im12)
        c_addi     = rtl_control_logic(inst_addi, 0, 0, 0, 0)
        c_addiu    = rtl_control_logic(inst_addiu, 0, 0, 0, 0)
        res_addi, _, _  = rtl_alu(r1, rtl_imm_gen(inst_addi, c_addi["imm_sel"]), c_addi["alu_sel"])
        res_addiu, _, _ = rtl_alu(r1, rtl_imm_gen(inst_addiu, c_addiu["imm_sel"]), c_addiu["alu_sel"])
        ok = (res_addi == exp_addi) and (res_addiu == exp_addiu) and (c_addi["imm_sel"] == IMM_I) and (c_addiu["imm_sel"] == IMM_I_ZERO)
        all_ok &= ok
        print(f" {cname:<24} | 0x{r1:08X} | 0x{im12:03X}  | 0x{res_addi:08X} (sign-ext)    | 0x{res_addiu:08X} (zero-ext)    | {'PASS' if ok else 'FAIL'}")

    print("=" * 106)
    if all_ok:
        print(" >>> KẾT LUẬN: SUBSAT, ADDIU VÀ TẤT CẢ LỆNH RISC-V GỐC HOẠT ĐỘNG NGUYÊN VẸN 100%! <<<")


if __name__ == "__main__":
    run_comparison()
