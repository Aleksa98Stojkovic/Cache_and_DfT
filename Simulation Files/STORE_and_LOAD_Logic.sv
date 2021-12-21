`timescale 1ns / 1ps

module STORE_and_LOAD_Logic();

parameter LOAD_opcode = 11;
parameter STORE_opcode = 12;
parameter STORE_WORD = logic'(3'b010);
parameter STORE_HALF_WORD = logic'(3'b011);
parameter STORE_BYTE = logic'(3'b100);

parameter opcode_width = 5;
parameter func3_width = 3;
parameter tag_width = 18;
parameter index_width = 10;
parameter offset_width = 4;
parameter total_width = 32;
parameter N = 4;

logic [N * total_width - 1 : 0] store_data_comb;
logic [N * (tag_width + 2) - 1 : 0] store_tag_comb;
logic [total_width - 1 : 0] load_data_comb;
logic sel; // input
logic load_miss; // input
logic [total_width - 1 : 0] axi_data_reg; // input
logic [total_width - 1 : 0] data_comb_reg; // input
logic valid_bit_reg, dirty_bit_reg; // input
logic [N * total_width - 1 : 0] backup_data_reg; // input
logic [N * (tag_width + 2) - 1 : 0] backup_tag_reg; // input
logic [$clog2(N) - 1 : 0] encoder_reg; // input
logic [opcode_width - 1 : 0] opcode_i; // input
logic [func3_width - 1 : 0] func3_i; // input
logic [total_width - 1 : 0] address_i; // input
logic [total_width - 1 : 0] data_i; // input
logic [$clog2(N) - 1 : 0] lru_set; // input

function logic [total_width - 1 : 0] gen_data();
    logic [total_width - 1 : 0] data;
    
    for(int i = 0; i < total_width; i++)
        data[i] = ($urandom_range(100) % 2 == 0) ? 1 : 0;
    return data;
    
endfunction

initial begin
    sel = 0;
    load_miss = 0;
    axi_data_reg = gen_data();
    data_comb_reg = gen_data();
    valid_bit_reg = 1;
    dirty_bit_reg = 1;
    
end

always_comb begin
    logic [total_width - 1 : 0] store_temp, write_data;
    logic [tag_width + 1 : 0] tag_temp;
    logic [$clog2(N) - 1 : 0] store_encoder;
    
    // sel = 1 -> miss
    
    // LOAD
    load_data_comb = sel ? axi_data_reg : data_comb_reg;
    
    // STORE
    case(func3_i)
        STORE_WORD: begin
            store_temp = data_i;
        end
        STORE_HALF_WORD: begin
            store_temp = {load_data_comb[total_width - 1 : 16], data_i[15 : 0]};
        end
        default: begin
            store_temp = {load_data_comb[total_width - 1 : 8], data_i[7 : 0]};
        end
    endcase
    
    // Ovde treba dodati za LRU
    store_encoder = sel ? lru_set : encoder_reg;
    
    // Dirty bit
    tag_temp[tag_width + 1] =  sel ? ((opcode_i == STORE_opcode) ? 1 : 0) : 
                                     ((opcode_i == STORE_opcode) ? 1 : dirty_bit_reg);
    // Valid bit
    tag_temp[tag_width] = sel ? 1 : valid_bit_reg;
    // Tag value
    tag_temp[tag_width - 1 : 0] = address_i[total_width - 1 -: tag_width];
    
    store_data_comb = backup_data_reg;
    store_tag_comb = backup_tag_reg;
    
    write_data = load_miss ? load_data_comb : store_temp;
    
    for(int j = 0; j < N; j++) begin
        if(j == store_encoder) begin
            store_data_comb[((j + 1) * total_width - 1) -: total_width] = write_data;
            store_tag_comb[((j + 1) * (tag_width + 2) - 1) -: (tag_width + 2)] = tag_temp;
        end
    end 
    
end


endmodule
