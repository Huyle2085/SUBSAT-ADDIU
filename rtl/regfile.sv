// =============================================================================
// File: rtl/regfile.sv
// Description: Tập thanh ghi 32 x 32-bit của RV32I.
//              Thanh ghi x0 luôn cứng bằng 0 (hardwired zero).
// =============================================================================

module regfile (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        reg_w_en,
    input  logic [4:0]  rs1_addr,
    input  logic [4:0]  rs2_addr,
    input  logic [4:0]  rd_addr,
    input  logic [31:0] wb_data,
    output logic [31:0] rs1_data,
    output logic [31:0] rs2_data
);

    logic [31:0] regs [0:31];

    // Ghi đồng bộ theo sườn lên xung nhịp, bỏ qua nếu rd_addr == x0
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 32; i++) begin
                regs[i] <= 32'h0000_0000;
            end
        end else if (reg_w_en && (rd_addr != 5'd0)) begin
            regs[rd_addr] <= wb_data;
        end
    end

    // Đọc bất đồng bộ, đảm bảo x0 luôn trả về 0
    assign rs1_data = (rs1_addr == 5'd0) ? 32'h0000_0000 : regs[rs1_addr];
    assign rs2_data = (rs2_addr == 5'd0) ? 32'h0000_0000 : regs[rs2_addr];

endmodule
