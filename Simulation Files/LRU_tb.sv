`timescale 1ns / 1ps

module LRU_tb();

parameter num_of_sets_sqrt = 2;
parameter index_width = 4;

logic clk, write_en;
logic [index_width - 1 : 0] address;
logic [num_of_sets_sqrt - 1 : 0] set_num;
logic [num_of_sets_sqrt - 1 : 0] lru_set;


LRU
#(
    .num_of_sets_sqrt(num_of_sets_sqrt),
    .index_width(index_width)
)
LRU_instance
(
    .clk_i(clk),
    .write_en_i(write_en),
    .reg_address_i(address),
    .set_num_i(set_num),
    .lru_set_o(lru_set)
);

initial begin
    clk = 0;
    write_en = 0;
    address = 0;
    set_num = 0;
    repeat (5) @(posedge clk);
    address = 12;
    set_num = 2;
    @(posedge clk);
    write_en = 1;
    @(posedge clk);
    write_en = 0;
    address = 10;
    set_num = 0;
    @(posedge clk);
    write_en = 1;
    @(posedge clk);
    write_en = 0;
end

// Clock generator
always begin
    #10ns clk = !clk;
end
 
endmodule
