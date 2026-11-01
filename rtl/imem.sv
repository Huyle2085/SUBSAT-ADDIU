// =============================================================================
// File: rtl/imem.sv
// Description: Bộ nhớ lệnh (Instruction Memory) đọc bất đồng bộ cho Single-Cycle.
// =============================================================================

module imem #(
    parameter int DEPTH = 1024
) (
    input  logic [31:0] addr,
    output logic [31:0] inst
);

    logic [31:0] mem [0:DEPTH-1];

    initial begin
        for (int i = 0; i < DEPTH; i++) begin
            mem[i] = 32'h0000_0013; // Khởi tạo bằng lệnh NOP (ADDI x0, x0, 0)
        end
    end

    assign inst = mem[addr[11:2]];

endmodule
