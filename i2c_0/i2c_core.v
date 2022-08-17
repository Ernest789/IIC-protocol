
module i2c_core (
    input rstn,  
    input clk,
    input start,  // start communicate
    input high_addr,  // memory address is signal-byte(0) or two-byte(1)   
    input [6:0] dev_addr,  // slave device address [101_0000]
    input [15:0] mem_addr,  // memory adress 
    input rd_wr_en,  // enable read(H) or write(L) 
    input [7:0] data_wr,  // writting in eeprom or reading from eeprom
    output [7:0] data_rd,
    inout scl,
    inout sda );

/************************register*****************************/
    reg [7:0] data_rd_r;
    assign data_rd = data_rd_r;

/*************************status*****************************/
// status:偏重过程中的某个状态  state：偏重长久的状态
    // 4-bit Gray code for status codes
    localparam 
        IDLE = 4'b0000,  //0 idling status
        START = 4'b0001,  //1 start status
        DEV_ADDR = 4'b0011,  //3 send slave divice adress 
        ACK_0 = 4'b0010,  //2 reciever aknowledge 
        MEM_ADDR_H = 4'b0110,  //6 send high eight bits memory adress 
        ACK_1 = 4'b0111,  // 7
        MEM_ADDR_L = 4'b0101,  //5 send low eight bits memory adress
        ACK_2 = 4'b0100,  //4 
        // Read Status
        STATRT_RD = 4'b1100,  //12 send start signal agian
        DEV_ADDR_RD = 4'b1101,  // 13
        ACK_RD = 4'b1111,  // 15
        DATA_RD = 4'b1110,  //14 read data from slave device
        ACK_NOT = 4'b1010,  //10 not acknowladge 
        // Write Status
        DATA_WR = 4'b1011,  //11 write data to slave device
        ACK_WR = 4'b1001,  // 9
        STOP = 4'b1000;  //8 stop status 

/**********************Counters**********************/
// Demultiplier，50MHz -> 200KHz
    reg i2c_clk; 
    reg [7:0] cnt_clk; 
    always @(posedge clk, negedge rstn) begin
        if(!rstn) begin
            i2c_clk <= 0;
            cnt_clk <= 0;
        end
        else begin
            if(cnt_clk == 8'd249)
                cnt_clk <= 0;
            else begin
                cnt_clk <= cnt_clk + 1'b1;
                if(cnt_clk <= 7'd124)
                    i2c_clk <= 1'b1; 
                else 
                    i2c_clk <= 1'b0;
            end
        end
    end

// 8-base data counter
    wire cnt_data_en;  // enable condition  
    assign cnt_data_en = (current_state == DEV_ADDR || current_state == MEM_ADDR_H || current_state == MEM_ADDR_L || current_state == DATA_WR || current_state == DEV_ADDR_RD || current_state == DATA_RD) ? 1'b1 : 1'b0;
    
    reg [2:0] cnt_data;
    always @(posedge i2c_clk, negedge rstn) begin
        if(!rstn) begin
            cnt_data <= 0;
        end   
        else begin
            if(cnt_i2c_clk == 2'd2 && cnt_data_en == 1'b1) begin
                if(cnt_data == 3'd7)
                    cnt_data <= 0;
                else
                    cnt_data <= cnt_data + 1'b1;
                end
            else if(cnt_i2c_clk == 2'd2 && cnt_data_en == 1'b0)
                cnt_data <= 0;
            else
                cnt_data <= cnt_data;
        end
    end

// 4-base clock counter
    wire cnt_i2c_clk_en;
    assign cnt_i2c_clk_en = (current_state != IDLE) ? 1'b1 : 1'b0;
    reg [1:0] cnt_i2c_clk;  
    always @(posedge i2c_clk, negedge rstn) begin
        if(!rstn) begin
            cnt_i2c_clk <= 0;
        end   
        else begin
            if(cnt_i2c_clk_en == 1'b1) begin
                if(cnt_i2c_clk == 2'd3)
                    cnt_i2c_clk <= 0;
                else 
                    cnt_i2c_clk <= cnt_i2c_clk + 1'b1;
            end
            else
                cnt_i2c_clk <= 0;
        end
    end

// bus clock
    reg scl_clk;
    reg scl_clk_en;  // enable condition
    always @(posedge i2c_clk, negedge rstn) begin
        if(!rstn)
            scl_clk_en <= 1'b0;
        else begin
            if(next_state == START && cnt_i2c_clk == 2'd0)
                scl_clk_en <= 1'b1;
            else if(next_state == STOP && cnt_i2c_clk == 2'd0)
                scl_clk_en <= 1'b0;
            else
                scl_clk_en <= scl_clk_en;
        end    
    end  
    always @(posedge i2c_clk, negedge rstn) begin
        if(!rstn) begin
            scl_clk <= 1'b1;
            scl_clk_en <= 1'b0;
        end
        else begin
            if(scl_clk_en == 1'b1) begin
                if(cnt_i2c_clk == 2'd0)
                    scl_clk <= 1'b1;
                else if(cnt_i2c_clk == 2'd2)
                    scl_clk <= 1'b0;
                else 
                    scl_clk <= scl_clk;
            end
            else begin
                scl_clk <= 1;
            end
        end
    end


/************************FSM************************/
// state transit
    reg [3:0] current_state;
    reg [3:0] next_state;
    always @(posedge i2c_clk ,negedge rstn) begin
        if(!rstn) begin
            next_state <= IDLE;
            current_state <= IDLE;
        end
        else begin
            current_state <= next_state;
        end
    end

// state transition condition
reg sda_in_r;  // keep sda_in for one i2c_clk to handle ack-status
    always @(posedge i2c_clk ,negedge rstn) begin
         if(!rstn) begin
            sda_in_r <= 1'b0;
        end
        else begin
            sda_in_r <= sda_in;
        end
    end

    always @(*) begin
        case (current_state)
        // common status
            IDLE:begin
                if(start_r == 1'b1)
                    next_state = START;
                else 
                    next_state = next_state;        
            end
            START:begin
                if(cnt_i2c_clk == 2'd3)
                    next_state = DEV_ADDR;
                else
                    next_state = next_state;
            end
            DEV_ADDR:begin
                if(cnt_i2c_clk == 2'd3 && cnt_data == 3'd0) 
                    next_state = ACK_0;
                else
                    next_state = next_state;
            end
            ACK_0:begin
                if(cnt_i2c_clk == 2'd3)begin
                    if(sda_in_r == 1'b0) begin
                        if(high_addr == 1'b1) 
                            next_state = MEM_ADDR_H;
                        else
                            next_state = MEM_ADDR_L;
                    end
                    else
                        next_state = STOP;
                end
                else
                    next_state = next_state; 
            end
            MEM_ADDR_H:begin
                if(cnt_i2c_clk == 2'd3 && cnt_data == 3'd0) 
                    next_state = ACK_1;
                else
                    next_state = next_state;  
            end
            ACK_1:begin
                if(cnt_i2c_clk == 2'd3) begin
                    if(sda_in_r == 1'b0) begin 
                        next_state = MEM_ADDR_L;
                    end
                    else begin
                        next_state = STOP;
                    end
                end
                else
                    next_state = next_state; 
            end
            MEM_ADDR_L:begin
                if(cnt_i2c_clk == 2'd3 && cnt_data == 3'd0)
                    next_state = ACK_2;
                else
                    next_state = next_state;
            end
            ACK_2:begin
                if(cnt_i2c_clk == 2'd3) begin
                    if(sda_in_r == 1'b0 ) begin
                        if(rd_wr_en == 1'b0)
                            next_state = DATA_WR;
                        else
                            next_state = STATRT_RD;
                    end
                    else
                        next_state = STOP;
                end
                else
                    next_state = next_state;
            end
            STOP:begin
                if(cnt_i2c_clk == 2'd3)
                    next_state = IDLE;
                else 
                    next_state = next_state;
            end
        // read status
            STATRT_RD:begin
                if(cnt_i2c_clk == 2'd3)
                    next_state = DEV_ADDR_RD;
                else
                    next_state = next_state;
            end
            DEV_ADDR_RD:begin
                if(cnt_i2c_clk == 2'd3 && cnt_data == 3'd0)
                    next_state = ACK_RD;
                else
                    next_state = next_state;
            end
            ACK_RD:begin
                if(cnt_i2c_clk == 2'd3) begin
                    if(sda_in_r == 1'b0)
                        next_state = DATA_RD;
                    else
                        next_state = STOP;
                end
                else
                    next_state = next_state;
            end
            DATA_RD:begin
                if(cnt_i2c_clk == 2'd3 && cnt_data == 3'd0)
                    next_state = ACK_NOT;
                else
                    next_state = next_state;
            end
            ACK_NOT:begin
                if(cnt_i2c_clk == 2'd3) 
                    next_state <= STOP;
                else
                    next_state = next_state;
            end
        // write status
            DATA_WR:begin
                if(cnt_i2c_clk == 2'd3 && cnt_data == 3'd0)
                    next_state = ACK_WR;
                else
                    next_state = next_state;
            end
            ACK_WR:begin
                if(cnt_i2c_clk == 2'd3) begin
                    if(sda_in_r == 1'd0)
                        next_state = STOP;
                    else
                        next_state = STOP;
                end
                else 
                    next_state = next_state;
            end
        endcase
    end

// actions in each state
    reg sda_r;
    reg start_r;
    always @(posedge i2c_clk ,negedge rstn) begin
         if(!rstn) begin
            start_r <= 1'b0;
        end
        else begin
            start_r <= start;
        end
    end

    always @(posedge i2c_clk ,negedge rstn) begin
        if(!rstn) begin
            sda_r <= 1'b1;
        end
        else begin
            case (next_state)
            IDLE:begin
                sda_r <= 1'b1;
            end
            START:begin
                if(cnt_i2c_clk == 2'd0 && cnt_i2c_clk_en == 1'b1) 
                    sda_r <= 1'b0;
                else
                    sda_r <= sda_r;
            end
            DEV_ADDR:begin
                if(cnt_data <= 3'd6)
                    sda_r <= dev_addr[6 - cnt_data];
                else
                    sda_r <= 1'b0; 
            end
            ACK_0:begin
                sda_r <= 1'b1; 
            end
            MEM_ADDR_H:begin 
                sda_r <= mem_addr[15 - cnt_data];
            end
            ACK_1:begin
                sda_r <= 1'b1;  // host device put sda at high
            end
            MEM_ADDR_L:begin
                sda_r <= mem_addr[7 - cnt_data];
            end
            ACK_2:begin
                sda_r <= 1'b1;
            end
            DATA_WR:begin
                sda_r <= data_wr[7 - cnt_data];
            end
            ACK_WR:begin
                sda_r <= 1'b0;
            end
            STATRT_RD:begin
                if(cnt_i2c_clk == 2'd1)
                    sda_r <= 1'b0; 
                else
                    sda_r <= sda_r; 
            end
            DEV_ADDR_RD: begin
                if(cnt_data <= 3'd6)
                    sda_r <= dev_addr[6 - cnt_data];
                else
                    sda_r <= 1'b1;
            end
            ACK_RD:begin
                sda_r <= 1'b1;
            end
            DATA_RD:begin
                data_rd_r[7 - cnt_data] <= sda_in;
            end
            ACK_NOT:begin
                sda_r <= 1'b1;
            end
            STOP:
                if(cnt_i2c_clk == 2'd3)
                    sda_r <= 1'b0;
                else if(cnt_i2c_clk == 2'd2)
                    sda_r <= 1'b1;
                else
                    sda_r <= sda_r;    
            endcase
        end
    end
// tri_gates and other enable wire
    wire ack_en;
    wire sda_in;
    assign ack_en = (current_state == DATA_RD || current_state == ACK_0 || current_state == ACK_1 || current_state == ACK_2 || current_state == ACK_RD || current_state == ACK_WR) ? 1'b1 : 1'b0;  // not include non-acknowledge status
    assign sda = (ack_en == 1'b1) ? 1'bz : sda_r;  // tri-gate
    assign sda_in = sda;
    assign scl = scl_clk;

endmodule

