// =============================================================================
// File: rtl/dmem.sv
// Description: Bộ nhớ dữ liệu (Data Memory) đọc bất đồng bộ, ghi đồng bộ.
// =============================================================================

module dmem #(
    parameter int DEPTH = 1024
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        mem_rw,    // 1: Write, 0: Read/Idle
    input  logic [31:0] addr,
    input  logic [31:0] data_w,
    output logic [31:0] data_r
);

    logic [31:0] mem [0:DEPTH-1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < DEPTH; i++) begin
                mem[i] <= 32'h0000_0000;
            end
        end else if (mem_rw) begin
            mem[addr[11:2]] <= data_w;
        end
    end

    assign data_r = mem[addr[11:2]];

endmodule
