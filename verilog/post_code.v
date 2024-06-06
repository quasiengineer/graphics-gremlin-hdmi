`default_nettype none
module post_code(
    input clk,
    input isa_addr_en,
    input isa_io_write,
    input[19:0] isa_addr,
    input[7:0] isa_data,

    output reg post_code_present = 1,
    output reg[7:0] post_code_high_digit = 8'h30,
    output reg[7:0] post_code_low_digit = 8'h30
);
    localparam POST_CODE_BASE_ADDR_0 = 20'h80;
    localparam CYCLES_TO_SHOW_POST_CODE = 28'd143180000; // 5 seconds with clk frequency = 28.636MHz
    localparam ASCII_SYMBOL_0 = 8'h30;
    localparam ASCII_SYMBOL_A_MINUS_10 = 8'h37;

    wire post_code_cs;
    reg[27:0] clk_counter = 28'd0;

    assign post_code_cs = (isa_addr == POST_CODE_BASE_ADDR_0) & ~isa_addr_en & ~isa_io_write;

    always @ (posedge clk)
    begin
        if (post_code_cs) begin
            if (isa_data[3:0] > 9) begin
                post_code_low_digit <= ASCII_SYMBOL_A_MINUS_10 + isa_data[3:0];
            end else begin
                post_code_low_digit <= ASCII_SYMBOL_0 + isa_data[3:0];
            end

            if (isa_data[7:4] > 9) begin
                post_code_high_digit <= ASCII_SYMBOL_A_MINUS_10 + isa_data[7:4];
            end else begin
                post_code_high_digit <= ASCII_SYMBOL_0 + isa_data[7:4];
            end

            post_code_present <= 1;
            clk_counter <= 28'd0;
        end else begin
            if (post_code_present) begin
                if (clk_counter == CYCLES_TO_SHOW_POST_CODE) begin
                    clk_counter <= 28'd0;
                    post_code_present <= 0;
                end else begin
                    clk_counter <= clk_counter + 28'd1;
                end
            end
        end
    end

endmodule
