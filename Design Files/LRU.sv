`timescale 1ns / 1ps

module LRU
    #(
        parameter num_of_sets_sqrt = 2, // square root of the number of sets
        parameter index_width = 12
    )
    (
        input clk_i,
        input write_en_i,
        input logic [index_width - 1 : 0] reg_address_i,
        input logic [num_of_sets_sqrt - 1 : 0] set_num_i,
        output logic [num_of_sets_sqrt - 1 : 0] lru_set_o
    );
    
typedef logic [num_of_sets_sqrt ** 4 - 1 : 0] array_type [index_width ** 2 - 1 : 0];

// Fuction for initializing memory
function array_type initialize_memory();
    logic [num_of_sets_sqrt ** 4 - 1 : 0] mem [index_width ** 2 - 1 : 0];
    
    for(int i = 0; i < index_width ** 2; i++) begin
       mem[i] = 0; 
    end
    
    return mem;

endfunction

// memory
logic [num_of_sets_sqrt ** 4 - 1 : 0] memory [index_width ** 2 - 1 : 0] = initialize_memory(); 
logic [num_of_sets_sqrt ** 4 - 1 : 0] value_reg, value_next;
// Comparators
logic comp [num_of_sets_sqrt ** 2 - 1 : 0];
// Comb logic
logic [num_of_sets_sqrt ** 2 - 1 : 0] temp [num_of_sets_sqrt ** 2 - 1 : 0];
// Encoder
logic [num_of_sets_sqrt - 1 : 0] encoder;

// memory description
always_ff@(posedge clk_i) begin

    value_reg = memory[reg_address_i];
    if(write_en_i) begin
        memory[reg_address_i] <= value_next;
    end
end

// Comb logic
genvar i;
generate
    for(i = 0; i < num_of_sets_sqrt ** 2; i++) begin
        always_comb begin
            if(i == set_num_i) begin
                temp[i] = {(num_of_sets_sqrt ** 2){1'b1}};
            end
            else begin
                temp[i] = value_reg[(i + 1) * (num_of_sets_sqrt ** 2) - 1 : i * (num_of_sets_sqrt ** 2)];
            end
            
            temp[i][set_num_i] = 1'b0;
        end
    end
    
    for(i = 0; i < num_of_sets_sqrt ** 2; i++) begin
        assign value_next[(i + 1) * (num_of_sets_sqrt ** 2) - 1 : i * (num_of_sets_sqrt ** 2)] = temp[i];
    end 
endgenerate

// Comparators
generate
    for(i = 0; i < num_of_sets_sqrt ** 2; i++) begin
        
        always_comb begin        
            comp[i] = (value_reg[(i + 1) * (num_of_sets_sqrt ** 2) - 1 : i * (num_of_sets_sqrt ** 2)] == 0);
        end
        
    end
endgenerate

// Priority Encoder
always_comb begin
    encoder = 0;
    for(int i = num_of_sets_sqrt ** 2 - 1; i >= 0; i--) begin
        if(comp[i]) begin
            encoder = i;
        end
    end
end

assign lru_set_o = encoder; 

endmodule
