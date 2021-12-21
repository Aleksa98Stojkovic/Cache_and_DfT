`timescale 1ns / 1ps

module Cache_tb();

// Opcodes and subinstructions
parameter LOAD_opcode = 11;
parameter STORE_opcode = 12;
parameter STORE_WORD = 3'b010;
parameter STORE_HALF_WORD = 3'b011;
parameter STORE_BYTE = 3'b100;

parameter opcode_width = 5;
parameter func3_width = 3;
parameter tag_width = 18;
parameter index_width = 10;
parameter offset_width = 4;
parameter total_width = 32;
parameter N = 4;

logic clk_i;
logic rst_i;
logic start_i;
logic [opcode_width - 1 : 0] opcode_i;
logic [func3_width - 1 : 0] func3_i;
logic [total_width - 1 : 0] address_i;
logic [total_width - 1 : 0] data_i;
logic rdy_o;
logic [total_width - 1 : 0] data_o;
logic axi_rdy_i;
logic [total_width - 1 : 0] axi_data_i;
logic [total_width - 1 : 0] axi_address_o;
logic axi_start_o;

Cache
#(
    .LOAD_opcode(LOAD_opcode),
    .STORE_opcode(STORE_opcode),
    .STORE_WORD(STORE_WORD),
    .STORE_HALF_WORD(STORE_HALF_WORD),
    .STORE_BYTE(STORE_BYTE), 
    .opcode_width(opcode_width),
    .func3_width(func3_width),
    .tag_width(tag_width),
    .index_width(index_width),
    .offset_width(offset_width),
    .total_width(total_width),
    .N(N)
)
Cache_inst
(
    .clk_i(clk_i),
    .rst_i(rst_i),
    
    // First FSM
    .start_i(start_i),
    .opcode_i(opcode_i),
    .func3_i(func3_i),
    .address_i(address_i),
    .data_i(data_i),
    .rdy_o(rdy_o), 
    .data_o(data_o),
    
    // Second FSM
    .axi_rdy_i(axi_rdy_i),
    .axi_data_i(axi_data_i),
    .axi_address_o(axi_address_o),
    .axi_start_o(axi_start_o)
);

// Reset and Clock
initial begin
    clk_i = 0;
    rst_i = 1;
    #30ns rst_i = 0;  
end

always #10ns clk_i = ~clk_i;

// -------------------------- First FSM -------------------------- //
// FSM states
typedef enum logic [1 : 0] {GEN_INPUT, START, WAIT_RDY, CHECK} fsm1_state;
fsm1_state current_state1, next_state1;
// Registers for inputs
logic [opcode_width - 1 : 0] opcode_reg, opcode_next;
logic [func3_width - 1 : 0] func3_reg, func3_next;
logic [total_width - 1 : 0] address_reg, address_next;
logic [total_width - 1 : 0] data_reg, data_next, load_reg, load_next;
logic expect_hit_reg, expect_hit_next;

// Functions
function logic [total_width - 1 : 0] gen_data();
    logic [total_width - 1 : 0] data;
    
    for(int i = 0; i < total_width; i++)
        data[i] = ($urandom_range(100) % 2 == 0) ? 1 : 0;
    return data;
    
endfunction

function logic check_data(input logic [total_width - 1 : 0] data, input logic [index_width - 1 : 0] index, output logic [$clog2(N) - 1 : 0] place);
    logic [N * total_width - 1 : 0] line;
    logic hit;
    
    hit = 0;
    line = Cache_inst.memory_data[index];
    for(int i = 0; i < N; i++) begin
        if(line[(i + 1) * total_width - 1 -: total_width] == data) begin
            hit = 1;
            place = i;
        end   
    end
    
    return hit;
endfunction

function logic check_store_data(input logic [total_width - 1 : 0] data, input logic [index_width - 1 : 0] index, 
                                input logic [func3_width - 1 : 0] func3, output logic [$clog2(N) - 1 : 0] place);
    logic [N * total_width - 1 : 0] line;
    logic [total_width - 1 : 0] subline;
    logic hit;
    
    hit = 0;
    line = Cache_inst.memory_data[index];
    for(int i = 0; i < N; i++) begin
        
        subline = line[(i + 1) * total_width - 1 -: total_width];
        
        if(func3 == STORE_WORD) begin
            if(subline == data) begin
                hit = 1;
                place = i;
            end
        end
        
        if(func3 == STORE_HALF_WORD) begin
            if(subline[15 : 0] == data[15 : 0]) begin
                hit = 1;
                place = i;
            end
        end   
        
        if(func3 == STORE_BYTE) begin
            if(subline[7 : 0] == data[7 : 0]) begin
                hit = 1;
                place = i;
            end
        end  
    end
    
    return hit;
endfunction

function logic check_tag(input logic [tag_width - 1 : 0] tag, input logic [index_width - 1 : 0] index, output logic [$clog2(N) - 1 : 0] place);
    logic [N * (tag_width + 2) - 1 : 0] line;
    logic [tag_width + 1 : 0] subline;
    logic [tag_width - 1 : 0] temp_tag;
    logic hit;
    
    hit = 0;
    line = Cache_inst.memory_tag[index];
    for(int i = 0; i < N; i++) begin
        subline = line[(i + 1) * (tag_width + 2) - 1 -: tag_width + 2];
        temp_tag = subline[tag_width - 1 : 0];
        if(temp_tag == tag) begin
            hit = 1;
            place = i;
        end   
    end
    
    return hit;
endfunction

assign opcode_i = opcode_reg;
assign func3_i = func3_reg;
assign address_i = address_reg;
assign data_i = data_reg;

always_ff@(posedge clk_i) begin
    if(rst_i) begin
        opcode_reg <= 0;
        func3_reg <= 0;
        address_reg <= 0;
        data_reg <= 0;
        load_reg <= 0;
        expect_hit_reg <= 0;
    end
    else begin
        opcode_reg <= opcode_next;
        func3_reg <= func3_next;
        address_reg <= address_next;
        data_reg <= data_next;
        load_reg <= load_next;
        expect_hit_reg <= expect_hit_next;
    end
end

always_ff@(posedge clk_i) begin
    if(rst_i)
        current_state1 <= GEN_INPUT;
    else
        current_state1 <= next_state1;
end

always_comb begin

    opcode_next = opcode_reg;
    func3_next = func3_reg;
    address_next = address_reg;
    data_next = data_reg;
    load_next = load_reg;
    expect_hit_next = expect_hit_reg;
    start_i = 0;

    case(current_state1)
        GEN_INPUT: begin
            next_state1 = START;
            
            data_next = gen_data();
            
            // Generating HIT or a MISS
            expect_hit_next = 0;
            address_next = gen_data();
            if($urandom_range(100) % 2) begin
                // HIT
                logic [index_width - 1 : 0] index;
                index = gen_data();
                address_next[total_width - 1 -: tag_width] = Cache_inst.memory_tag[index][tag_width - 1 : 0];
                expect_hit_next = Cache_inst.memory_tag[index][tag_width]; // valid bit
            end
            
            if($urandom_range(100) % 2)
                opcode_next = LOAD_opcode;
            else
                opcode_next = STORE_opcode;
                
            case($urandom_range(100) % 3)
                0 : func3_next = STORE_WORD;
                1 : func3_next = STORE_HALF_WORD;
                2 : func3_next = STORE_BYTE;
                default : func3_next = STORE_WORD; 
            endcase    
            
            $display("STATE GEN_INPUT!\n %d", $time);
                
        end
        START: begin
            next_state1 = WAIT_RDY;
            start_i = 1;
            $display("STATE START!\n %d", $time);
        end
        WAIT_RDY: begin
            next_state1 = rdy_o ? CHECK : WAIT_RDY;
            load_next = data_o;
            $display("STATE WAIT_RDY!\n %d", $time);
        end
        CHECK: begin
            logic [index_width - 1 : 0] index;
            logic [$clog2(N) - 1 : 0] place_tag, place_data;
            logic match_data, match_tag;
            index = address_reg[index_width + offset_width - 1 -: index_width];
            
            $display("STATE CHECK!\n %d", $time);
            
            next_state1 = GEN_INPUT;
            // Checking if the operation has been successfuly acomplished
            if(opcode_reg == LOAD_opcode) begin
                if(Cache_inst.hit != expect_hit_reg) begin
                    $display("ERROR : Hit signal and expected hit signal do not match!\n %d", $time);
                end
                else begin
                    match_data = check_data(load_reg, index, place_data);
                    match_tag = check_tag(address_reg[total_width - 1 -: tag_width], index, place_tag);
                    if(!match_data || !match_tag) begin
                        $display("ERROR : Loaded data or tag does not exist in memory!\n %d", $time);
                    end
                    else begin
                        if(place_data != place_tag) begin
                            $display("ERROR : Tag and loaded data are not aligned!\n %d", $time);
                        end
                        else begin
                            $display("CORRECT : Loaded data is correct!\n %d", $time);
                        end
                    end
                end
            end
            
            if(opcode_reg == STORE_opcode) begin
                if(Cache_inst.hit != expect_hit_reg) begin
                    $display("ERROR : Hit signal and expected hit signal do not match!\n %d", $time);
                end
                else begin
                    match_data = check_store_data(data_reg, index, func3_reg, place_data);
                    match_tag = check_tag(address_reg[total_width - 1 -: tag_width], index, place_tag);
                    if(!match_data || !match_tag) begin
                        $display("ERROR : Stored data or tag does not exist in memory!\n %d", $time);
                    end
                    else begin
                        if(place_data != place_tag) begin
                            $display("ERROR : Tag and stored data are not aligned!\n %d", $time);
                        end
                        else begin
                            $display("CORRECT : Stored data is correct!\n %d", $time);
                        end
                    end
                end
            end
            
        end
        default: 
            next_state1 = GEN_INPUT;
    endcase

end

// -------------------------- Second FSM -------------------------- //
// FSM states
typedef enum logic [1 : 0] {START_S, DELAY_S, RDY_S} fsm2_state;
fsm2_state current_state2, next_state2;
// Register and Counters
logic [3 : 0] counter_16;
logic en_16;
logic [total_width - 1 : 0] axi_data_reg, axi_data_next;

assign axi_data_i = axi_data_reg;

always_ff@(posedge clk_i) begin
    if(rst_i) begin
        counter_16 <= 0;
        axi_data_reg <= 0;
    end
    else begin
        axi_data_reg <= axi_data_next;
        counter_16 <= counter_16;
        if(en_16) 
            counter_16 <= counter_16 + 1;
    end
end

always_ff@(posedge clk_i) begin
    if(rst_i)
        current_state2 <= START_S;
    else
        current_state2 <= next_state2;
end

always_comb begin
    
    en_16 = 0;
    axi_data_next = axi_data_reg;
    axi_rdy_i = 0;
    
    case(current_state2)
        START_S: begin
            next_state2 = axi_start_o ? DELAY_S : START_S;
            axi_data_next = gen_data();
        end
        DELAY_S: begin
            next_state2 = (counter_16 == 15) ? RDY_S : DELAY_S;
            en_16 = 1;
        end
        RDY_S: begin
            next_state2 = START_S;
            axi_rdy_i = 1;
        end
    endcase
end

endmodule
