`timescale 1ns / 1ps

module Cache
    #(
        // Opcodes and subinstructions
        parameter LOAD_opcode = 11,
        parameter STORE_opcode = 12,
        parameter STORE_WORD = logic'(3'b010),
        parameter STORE_HALF_WORD = logic'(3'b011),
        parameter STORE_BYTE = logic'(3'b100), 
    
        parameter opcode_width = 5,
        parameter func3_width = 3,
        parameter tag_width = 18,
        parameter index_width = 10,
        parameter offset_width = 4,
        parameter total_width = 32,
        parameter N = 4
    )
    (
        input clk_i,
        input rst_i,
        
        // Processor-Cache Interface
        input start_i,
        input [opcode_width - 1 : 0] opcode_i,
        input [func3_width - 1 : 0] func3_i,
        input [total_width - 1 : 0] address_i,
        input [total_width - 1 : 0] data_i, // samo za store
        output logic rdy_o, // Izbaciti done_o, pa onda procesor gleda rdy ciklus nakon postavljanja starta
        output logic done_o, // Ciklus kasnije moze da se uzme podatak
        output logic [total_width - 1 : 0] data_o, // samo za load
        
        // AXI-Cache Interface
        input axi_rdy_i,
        input [total_width - 1 : 0] axi_data_i,
        output logic [total_width - 1 : 0] axi_address_o,
        output logic axi_start_o
    );

// FSM
typedef enum logic[3 : 0] {IDLE, READ1, READ2, READ3, HIT, LRU_UPDATE, MISS1, MISS2, MISS3} fsm_state;
fsm_state next_state, current_state;
    
// Registers for inputs from the processor
logic [opcode_width - 1 : 0] opcode_reg, opcode_next;
logic [func3_width - 1 : 0] func3_reg, func3_next; 
logic [total_width - 1 : 0] address_reg, address_next;
logic [total_width - 1 : 0] store_data_reg, store_data_next;
logic [total_width - 1 : 0] axi_data_reg, axi_data_next;

// Memories for tags and data
logic [N * (tag_width + 2) - 1 : 0] memory_tag [2 ** index_width];
logic [N * total_width - 1 : 0] memory_data [2 ** index_width];
logic [index_width - 1 : 0] addr_tag, addr_data;
logic we_tag, we_data;
logic [N * (tag_width + 2) - 1 : 0] rdata_tag, wdata_tag;
logic [N * total_width - 1 : 0] rdata_data, wdata_data;

// Additional Registers
logic [total_width - 1 : 0] wdata_data_reg, wdata_data_next;
logic [tag_width + 1 : 0] wdata_tag_reg, wdata_tag_next;
logic [total_width - 1 : 0] data_comb_reg, data_comb_next;
logic hit_reg, hit_next, valid_bit_reg, valid_bit_next, dirty_bit_reg, dirty_bit_next;
logic [total_width - 1 : 0] load_data_reg, load_data_next;
logic [N * total_width - 1 : 0] backup_data_reg, backup_data_next;
logic [N * (tag_width + 2) - 1 : 0] backup_tag_reg, backup_tag_next;
logic [$clog2(N) - 1 : 0] encoder_reg, encoder_next;

// Logic for reading the memories
// Outputs : hit, data, valid_bit, dirty_bit
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

// Logic for LOAD and STORE
logic [N * total_width - 1 : 0] store_data_comb;
logic [N * (tag_width + 2) - 1 : 0] store_tag_comb;
logic [total_width - 1 : 0] load_data_comb;
logic sel;
logic load_miss;

// LRU unit signals
logic we_lru;
logic [index_width - 1 : 0] lru_address;
logic [$clog2(N) - 1 : 0] lru_set;

// ------------------------------------------------------- //

// Assigments
assign axi_address_o = address_reg;
assign data_o = load_data_reg;
assign axi_data_next = axi_data_i;

// ------------------------------------------------------- //
// LRU Unit
LRU_Unit 
#(
    .num_of_sets_sqrt($clog2(N)),
    .index_width(index_width)
)
LRU
(
    .clk_i(clk_i),
    .write_en_i(we_lru),
    .reg_address_i(lru_address),
    .set_num_i(encoder_reg),
    .lru_set_o(lru_set)
);

assign lru_address = address_reg[index_width + offset_width - 1 : offset_width];

// ------------------------------------------------------- //
// Registers

always_ff@(posedge clk_i) begin
    if(rst_i) begin
       opcode_reg <= 0;
       func3_reg <= 0;
       address_reg <= 0;
       store_data_reg <= 0;
       axi_data_reg <= 0;
       wdata_tag_reg <= 0;
       wdata_data_reg <= 0;
       data_comb_reg <= 0;
       hit_reg <= 0;
       valid_bit_reg <= 0;
       dirty_bit_reg <= 0;
       load_data_reg <= 0;
       backup_data_reg <= 0;
       backup_tag_reg <= 0;
       encoder_reg <= 0;
    end
    else begin
       opcode_reg <= opcode_next;
       func3_reg <= func3_next;
       address_reg <= address_next;
       store_data_reg <= store_data_next;
       axi_data_reg <= axi_data_next;
       wdata_tag_reg <= wdata_tag_next;
       wdata_data_reg <= wdata_data_next;
       data_comb_reg <= data_comb_next;
       hit_reg <= hit_next;
       valid_bit_reg <= valid_bit_next;
       dirty_bit_reg <= dirty_bit_next;
       load_data_reg <= load_data_next;
       backup_data_reg <= backup_data_next;
       backup_tag_reg <= backup_tag_next;
       encoder_reg <= encoder_next;
    end
end

// ------------------------------------------------------- //

// Memories
always_ff@(posedge clk_i) begin
    // Tag
    rdata_tag <= memory_tag[addr_tag];
    if(we_tag)
        memory_tag[addr_tag] <= wdata_tag;
    // Data
    rdata_data <= memory_data[addr_data];
    if(we_data)
        memory_data[addr_data] <= wdata_data;
end

assign addr_tag = address_reg[index_width + offset_width - 1 : offset_width];
assign addr_data = address_reg[index_width + offset_width - 1 : offset_width];
assign wdata_data = wdata_data_reg;
assign wdata_tag = wdata_tag_reg;

// ------------------------------------------------------- //

// Logic for reading the memories
// Comparators
// Tag Memory layout: Dirty_bit | Valid_bit | Tag

generate
    for(i = 0; i < N; i++) begin
        always_comb begin
                tag[i] = rdata_tag[(i + 1) * (tag_width + 2) - 1 : i * (tag_width + 2)]; 
                comp[i] = logic'(tag[i][tag_width - 1 : 0] == address_reg[(total_width - 1) -: tag_width]);
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

// ------------------------------------------------------- //

// Logic for determening LOAD and STORE data
// Outputs: store_data_comb, store_tag_comb, load_data_comb
// This is the most critical part
always_comb begin
    logic [total_width - 1 : 0] store_temp, write_data;
    logic [tag_width + 1 : 0] tag_temp;
    logic [$clog2(N) - 1 : 0] store_encoder;
    
    // sel = 1 -> miss
    
    // LOAD
    load_data_comb = sel ? axi_data_reg : data_comb_reg;
    
    // STORE
    case(func3_reg)
        STORE_WORD: begin
            store_temp = store_data_reg;
        end
        STORE_HALF_WORD: begin
            store_temp = {load_data_comb[total_width - 1 : 16], store_data_reg[15 : 0]};
        end
        default: begin
            store_temp = {load_data_comb[total_width - 1 : 8], store_data_reg[7 : 0]};
        end
    endcase
    
    // Ovde treba dodati za LRU
    store_encoder = sel ? lru_set : encoder_reg;
    
    // Dirty bit
    tag_temp[tag_width + 1] =  sel ? ((opcode_reg == STORE_opcode) ? 1 : 0) : 
                                     ((opcode_reg == STORE_opcode) ? 1 : dirty_bit_reg);
    // Valid bit
    tag_temp[tag_width] = sel ? 1 : valid_bit_reg;
    // Tag value
    tag_temp[tag_width - 1 : 0] = address_reg[total_width - 1 -: tag_width];
    
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

// ------------------------------- FSM ------------------------------- //
always_ff@(posedge clk_i) begin
    if(rst_i) begin
        current_state <= IDLE;
    end
    else begin
        current_state <= next_state;
    end
end

always_comb begin

    // Processor
    rdy_o = 0;
    done_o = 0;
    opcode_next = opcode_reg;
    func3_next = func3_reg;
    address_next = address_reg;
    store_data_next = store_data_reg;
    load_data_next = load_data_reg;
    // AXI
    axi_start_o = 0;
    // Memory
    wdata_tag_next = wdata_tag_reg;
    wdata_data_next = wdata_data_reg;
    we_tag = 0;
    we_data = 0;
    // Hit Logic/Read data from memory logic
    data_comb_next = data_comb_reg;
    hit_next = hit_reg;
    valid_bit_next = valid_bit_reg;
    dirty_bit_next = dirty_bit_reg;
    backup_data_next = backup_data_reg;
    backup_tag_next = backup_tag_reg;
    encoder_next = encoder_reg;
    // STORE and LOAD logic
    sel = 0;
    load_miss = 0;
    // LRU
    we_lru = 0;
    
    case(current_state)
        IDLE: begin
            next_state = IDLE;
            rdy_o = 1;
            opcode_next = opcode_i;
            func3_next = func3_i;
            address_next = address_i;
            store_data_next = data_i;
            if(start_i) begin
                next_state = READ1;
            end
        end
        READ1: begin
            // The right address is on the address port of both memories
            next_state = READ2;
        end
        READ2: begin
            // hit, data, dirty and valid bits are ready
            next_state = READ3;
            data_comb_next = data;
            hit_next = hit;
            valid_bit_next = valid_bit;
            dirty_bit_next = dirty_bit;
            encoder_next = encoder;
            // These two are needed in case of a miss
            backup_data_next = rdata_data;
            backup_tag_next = rdata_tag;
        end
        READ3: begin
            // next_state depends on the hit_reg 
            // LRU unit has valid address
            if(hit_reg) begin
                next_state = HIT;
            end
            else begin
                next_state = MISS1;
                axi_start_o = 1; 
            end
        end
        HIT: begin
            next_state = LRU_UPDATE;
            load_data_next = load_data_comb;
            wdata_data_next = store_data_comb;
            wdata_tag_next = store_tag_comb;
        end
        LRU_UPDATE: begin
            // Mogu registri na ove signale, pa nemamo ovo stanje
            next_state = IDLE;
            done_o = 1;
            we_tag = (opcode_reg == STORE_opcode) ? 1 : 0;
            we_data = (opcode_reg == STORE_opcode) ? 1 : 0;
            we_lru = 1;
        end
        MISS1: begin
            // This Circuit assumes that axi_rdy_i will not be 1 for at least 3 cycles
            next_state = MISS1;
            if(axi_rdy_i) begin
                next_state = MISS2;
                // We have to update axi_data
                encoder_next = lru_set;
            end;
            
            sel = 1;
            load_miss = (opcode_reg == LOAD_opcode) ? 1 : 0;
            load_data_next = load_data_comb;
            wdata_data_next = store_data_comb;
            wdata_tag_next = store_tag_comb;
        end
        MISS2: begin
            // New data is being written in memories
            next_state = MISS3;
            we_tag = 1;
            we_data = 1;
        end
        MISS3: begin
            // In this cycle LRU_Unit has to be updated
            next_state = IDLE;
            we_lru = 1;
            done_o = 1;
        end
        default:
            next_state = IDLE;
    endcase

end
    
endmodule