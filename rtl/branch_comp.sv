// =============================================================================
// File: rtl/branch_comp.sv
// Description: Bộ so sánh nhánh (Branch Comparator) hỗ trợ có dấu / không dấu.
// =============================================================================

module branch_comp (
    input  logic [31:0] data_r1,
    input  logic [31:0] data_r2,
    input  logic        br_un,
    output logic        br_eq,
    output logic        br_lt
);

    always_comb begin
        br_eq = (data_r1 == data_r2);
        if (br_un) begin
            br_lt = (data_r1 < data_r2);
        end else begin
            br_lt = ($signed(data_r1) < $signed(data_r2));
        end
    end

endmodule
