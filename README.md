# Triển khai 2 lệnh tùy chỉnh `SUBSAT` và `ADDIU` cho CPU RISC-V (RV32I Single-Cycle)

Dự án thiết kế RTL và kiểm thử (Verification) hai lệnh mở rộng trong vùng `custom-0` (`opcode = 7'b0001011`) trên kiến trúc vi xử lý **RV32I Single-Cycle**:
1. **`SUBSAT rd, rs1, rs2`** (*Signed Saturating Subtraction* — Phép trừ có dấu bão hòa 32-bit, định dạng R-type).
2. **`ADDIU rd, rs1, imm12`** (*Unsigned Zero-Extended Immediate Addition* — Cộng thanh ghi với hằng số 12-bit không dấu mở rộng 0, định dạng I-type; lưu ý khác với MIPS `ADDIU` là sign-extend).

---

## 1. Đặc tả kiến trúc & Bảng phân biệt lệnh (ISA Contract)

| Lệnh | Định dạng | `opcode[6:0]` | `funct3[14:12]` | Trường `[31:20]` / `funct7` | Ngữ nghĩa toán học |
|---|---|---|---|---|---|
| **`SUBSAT`** | R-type | `7'b0001011` (`custom-0`) | `3'b000` | `funct7 = 7'b0100001` | `rd = clamp_int32(signed64(R[rs1]) - signed64(R[rs2]))` |
| **`ADDIU`** | I-type | `7'b0001011` (`custom-0`) | `3'b001` | `imm[11:0]` tùy ý (KHÔNG dùng `funct7`) | `rd = (R[rs1] + {20'b0, imm12}) mod 2^32` (không bão hòa) |
| **`ADDI` chuẩn** | I-type | `7'b0010011` (`OP_IMM`) | `3'b000` | `imm[11:0]` (sign-extend) | `rd = (R[rs1] + {{20{imm[11]}}, imm12}) mod 2^32` |
| **`SUB` chuẩn** | R-type | `7'b0110011` (`OP_RTYPE`) | `3'b000` | `funct7 = 7'b0100000` | `rd = (R[rs1] - R[rs2]) mod 2^32` (wrap-around) |

- **Ví dụ mã máy**:
  - `SUBSAT x5, x6, x7` $\rightarrow$ `32'h4273_028B`
  - `ADDIU x5, x6, 0xFFF` $\rightarrow$ `32'hFFF3_128B`
- Tất cả hằng số được định nghĩa tập trung tại [isa_defs.sv](rtl/isa_defs.sv).

---

## 2. Xác nhận độ rộng và cách nối dây (Theo Góp ý 2)

| Module | Nội dung xác nhận | Trạng thái trong RTL |
|---|---|---|
| [isa_defs.sv](rtl/isa_defs.sv) | `ImmSel` và `WBSel` có được khai báo 3-bit không? | **ĐÃ ĐẢM BẢO**: `typedef enum logic [2:0] imm_sel_e` (có `IMM_I_ZERO = 3'b101`) và `typedef enum logic [2:0] wb_sel_e` (có `WB_MAX = 3'b011`, `WB_MIN = 3'b100`). |
| [control_logic.sv](rtl/control_logic.sv) | Có xuất đúng `ImmSel[2:0]` và tách biệt `is_addiu` / `is_subsat` không? | **ĐÃ ĐẢM BẢO**: Cổng `output imm_sel_e imm_sel` rộng 3-bit; khi `is_addiu = 1` xuất `imm_sel = IMM_I_ZERO (3'b101)`, `b_sel = 1'b1`, `alu_sel = ALU_ADD`, `wb_sel = WB_ALU (3'b001)`. |
| [imm_gen.sv](rtl/imm_gen.sv) | Input instruction là 32-bit hay chỉ `inst[31:7]`? | **ĐÃ ĐẢM BẢO**: Cổng `input logic [31:0] inst` nhận đủ 32-bit, do đó nhánh `IMM_I_ZERO` trích xuất trực tiếp `{20'b0, inst[31:20]}`. |
| [datapath.sv](rtl/datapath.sv) | Đã nối đầy đủ 3-bit `ImmSel` và `WBSel` chưa? | **ĐÃ ĐẢM BẢO**: `input imm_sel_e imm_sel` (3-bit) nối thẳng vào `u_imm_gen`, `input wb_sel_e wb_sel` (3-bit) điều khiển MUX 5:1. |
| [top.sv](rtl/top.sv) | Các kết nối có thống nhất độ rộng không? | **ĐÃ ĐẢM BẢO**: Kiểm tra bằng `vlog -sv -lint` báo **`Errors: 0, Warnings: 0`** trên toàn bộ 10 file RTL và 6 Testbench. |

---

## 3. Cấu trúc thư mục dự án

```text
BTN_CTMT/
├── rtl/
│   ├── isa_defs.sv         # Package hằng số ISA, SUBSAT, ADDIU, ALUSel, WBSel[2:0], ImmSel[2:0]
│   ├── alu.sv              # ALU 32-bit với logic phát hiện tràn pos_ov / neg_ov cho SUBSAT
│   ├── imm_gen.sv          # Bộ tạo immediate 6 chế độ (thêm IMM_I_ZERO = 3'b101 cho ADDIU)
│   ├── control_logic.sv    # Giải mã is_addiu, is_subsat, điều khiển ImmSel[2:0] & WBSel[2:0]
│   ├── regfile.sv          # Tập thanh ghi 32x32-bit (x0 cứng bằng 0)
│   ├── branch_comp.sv      # Bộ so sánh nhánh (signed/unsigned)
│   ├── imem.sv             # Bộ nhớ lệnh (Instruction Memory)
│   ├── dmem.sv             # Bộ nhớ dữ liệu (Data Memory)
│   ├── datapath.sv         # Datapath RV32I với ImmGen 6 chế độ & Write-Back MUX 5:1
│   └── top.sv              # Top-level tích hợp Datapath + Control + IMEM + DMEM
├── tb/
│   ├── tb_alu.sv           # Unit testbench cho ALU (Directed + 1000 Random)
│   ├── tb_imm_gen.sv       # Unit testbench cho ImmGen (Quét vét cạn 4096 giá trị imm12)
│   ├── tb_control.sv       # Unit testbench cho Control Logic (SUBSAT + ADDIU + Illegal)
│   ├── tb_top.sv           # System testbench cho SUBSAT (T01..T14 + 1000 Random + Coverage)
│   ├── tb_addiu.sv         # System testbench cho ADDIU (U01..U15 + 1000 Random + Coverage)
│   └── tb_sub_vs_subsat.sv # Testbench đối chiếu trực tiếp SUB vs SUBSAT
├── sim/
│   ├── run_all.do          # Script TCL chạy toàn bộ 6 testbench trên QuestaSim / ModelSim
│   ├── verify_and_wave.py  # Script chạy mô phỏng chu kỳ, xuất log, VCD và SVG waveforms
│   └── check_sub_regression.py # Công cụ đối chiếu nhanh SUB vs SUBSAT, ADDI vs ADDIU & RV32I
└── README.md               # Tài liệu bàn giao dự án
```
