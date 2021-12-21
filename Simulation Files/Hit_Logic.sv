`timescale 1ns / 1ps

module Hit_Logic();

parameter opcode_width = 5;
parameter func3_width = 3;
parameter tag_width = 18;
parameter index_width = 10;
parameter offset_width = 4;
parameter total_width = 32;
parameter N = 4;

logic hit;
logic [N - 1 : 0] hit_vector;
logic [tag_width + index_width + offset_width - 1 : 0] data;
logic [tag_width + index_width + offset_width - 1 : 0] data_mux [N];
logic [N - 1 : 0] comp;
logic [tag_width + 1 : 0] tag[N]; 
logic [$clog2(N) - 1 : 0] encoder;
logic [N - 1 : 0] valid_bit_vector, dirty_bit_vector;
logic dirty_bit, valid_bit;
genvar i;

logic [total_width - 1 : 0] address_i;
logic [N * (tag_width + 2) - 1 : 0] rdata_tag;
logic [N * total_width - 1 : 0] rdata_data;

function logic [total_width - 1 : 0] random_address();

    int rnd;
    logic [total_width - 1 : 0] temp;
    
    for(int i = 0; i < total_width; i++) begin
        temp[i] = ($urandom_range(100) % 2 == 0) ? 1 : 0;
    end
    
    return temp;

endfunction

function logic [N * total_width - 1 : 0] random_data();

    int rnd;
    logic [N * total_width - 1 : 0] temp;
    
    for(int i = 0; i < N * total_width; i++) begin
        temp[i] = ($urandom_range(100) % 2 == 0) ? 1 : 0;
    end
    
    return temp;

endfunction

function logic [N * (tag_width + 2) - 1 : 0] random_tag();

    int rnd;
    logic [N * (tag_width + 2) - 1 : 0] temp;
    
    for(int i = 0; i < N * (tag_width + 2); i++) begin
        temp[i] = ($urandom_range(100) % 2 == 0) ? 1 : 0;
    end
    
    return temp;

endfunction

initial begin

    address_i = random_address();
    rdata_tag = random_tag();
    rdata_data = random_data();
    
    #300ns;
    
    address_i = 0;
    rdata_tag = 0;
    rdata_data = 0;
    
    #300ns;
    
    // Forsirani hit
    address_i = random_address();
    rdata_tag = random_tag();
    rdata_tag[2 * (tag_width + 2) - 3 -: tag_width] = address_i[total_width - 1 -: tag_width];
    rdata_tag[2 * (tag_width + 2) - 1 -: 2] = 3;
    rdata_data = random_data();

end

generate
    for(i = 0; i < N; i++) begin
        always_comb begin
                tag[i] = rdata_tag[(i + 1) * (tag_width + 2) - 1 : i * (tag_width + 2)]; 
                comp[i] = logic'(tag[i][tag_width - 1 : 0] == address_i[(total_width - 1) -: tag_width]);
                hit_vector[i] = tag[i][tag_width] & comp[i];
                data_mux[i] = rdata_data[(i + 1) * (total_width) - 1 -: total_width];
                dirty_bit_vector[i] = tag[i][tag_width + 1];
                valid_bit_vector[i] = tag[i][tag_width];
        end
    end 
endgenerate;

// Hit Logic
always_comb begin
    logic or_gate;
    or_gate = hit_vector[0];
    for(int j = 1; j < N; j++) begin
        or_gate |= hit_vector[j];
    end
    
    hit = or_gate;
end

// Encoder and Mux
always_comb begin
    encoder = 0;
    for(int i = N - 1; i >= 0; i--) begin
        if(hit_vector[i]) begin
            encoder = i;
        end
    end
end

// Ovde moze mozda mux umesto LUT(RTL_ROM)
assign data = data_mux[encoder];
assign dirty_bit = dirty_bit_vector[encoder];
assign valid_bit = valid_bit_vector[encoder];

endmodule
