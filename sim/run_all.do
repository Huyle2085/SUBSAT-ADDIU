# =============================================================================
# File: sim/run_all.do
# Description: Script TCL cho QuestaSim / ModelSim biên dịch toàn bộ RTL + TB
#              và chạy kiểm thử tự động tb_alu, tb_imm_gen, tb_control,
#              tb_subsat (RV32I+SUBSAT), tb_addiu (RV32I+ADDIU),
#              tb_top (RV32I+ADDIU+SUBSAT), tb_sub_vs_subsat và tb_addi_vs_addiu.
# =============================================================================

if {[file exists work]} {
    vdel -lib work -all
}
vlib work

# Biên dịch RTL và Testbench với kiểm tra lint/width chặt chẽ
vlog -sv -lint \
    rtl/isa_defs.sv \
    rtl/alu.sv \
    rtl/regfile.sv \
    rtl/imm_gen.sv \
    rtl/branch_comp.sv \
    rtl/imem.sv \
    rtl/dmem.sv \
    rtl/control_logic.sv \
    rtl/datapath.sv \
    rtl/top.sv \
    tb/tb_alu.sv \
    tb/tb_imm_gen.sv \
    tb/tb_control.sv \
    tb/tb_subsat.sv \
    tb/tb_addiu.sv \
    tb/tb_top.sv \
    tb/tb_sub_vs_subsat.sv \
    tb/tb_addi_vs_addiu.sv

# 1. Chạy Unit Test ALU
vsim -c -voptargs="+acc" work.tb_alu -do "run -all; quit -f"

# 2. Chạy Unit Test ImmGen (4096 giá trị imm12)
vsim -c -voptargs="+acc" work.tb_imm_gen -do "run -all; quit -f"

# 3. Chạy Unit Test Control Logic
vsim -c -voptargs="+acc" work.tb_control -do "run -all; quit -f"

# 4. Chạy System Test RV32I + SUBSAT (T01..T14 + 1000 Random + Coverage)
vsim -c -voptargs="+acc" work.tb_subsat -do "run -all; quit -f"

# 5. Chạy System Test RV32I + ADDIU (U01..U15 + 1000 Random + Coverage)
vsim -c -voptargs="+acc" work.tb_addiu -do "run -all; quit -f"

# 6. Chạy System Test tích hợp RV32I + ADDIU + SUBSAT
vsim -c -voptargs="+acc" work.tb_top -do "run -all; quit -f"

# 7. Chạy Differential Test SUB vs SUBSAT
vsim -c -voptargs="+acc" work.tb_sub_vs_subsat -do "run -all; quit -f"

# 8. Chạy Differential Test ADDI vs ADDIU
vsim -c -voptargs="+acc" work.tb_addi_vs_addiu -do "run -all; quit -f"

quit -f
