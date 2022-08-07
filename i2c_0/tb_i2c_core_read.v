`timescale  1ns/1ps
`include "i2c_core.v"

module tb_i2c_core ();
    integer T = 20;  // clk:50MHz
    integer B = 20*1000;  // baud rate:50KHz

    reg rstn;
    reg clk;
    reg start;
    reg high_addr;
    reg [6:0] dev_addr;
    reg [15:0] mem_addr;
    reg rd_wr_en;
    reg [7:0] data_wr; 
    reg ack_en;
    reg [7:0] mem_data;
    reg mem_data_en;
    reg sda_r;

    wire scl;
    wire sda;
    wire sda_in;
    reg sda_out;
    wire [7:0] data_rd;
    
    initial begin
        clk = 1'b0;
        rstn = 1'b0;
        start = 1'b0;
        high_addr = 1'b0;
        rd_wr_en = 1'b1;
        dev_addr = 7'b0;
        data_wr = 8'b0;
        mem_addr = 8'b0;
        ack_en = 1'b0;
        sda_out = 1'b0;
        mem_data = 8'b0;
        mem_data_en = 1'b0;
    end

    always begin
            #(T/2) clk = ~clk;
    end
    integer i;
    initial begin
        #(2*B) 
            rstn = 1'b1; 
        #(B)
            start = 1'b1;
            dev_addr = 7'b101_0001;
            mem_addr = 16'b0000_0000_1011_1011;
            data_wr = 8'b1111_1111;
            mem_data = 8'b1100_1100;
        #(B/2)
            start = 1'b0;
        #(8.75*B)
            ack_en = 1'b1;
        #(B)
            ack_en = 1'b0;
        #(8*B)
            ack_en = 1'b1;
        #(B)
            ack_en = 1'b0;
        #(9*B)
            ack_en = 1'b1;
        #(B)
            ack_en = 1'b0;
            mem_data_en = 1'b1;
            sda_r = mem_data[7];
        for (i=0;i<=6;i+=1) begin
            #(B) sda_r = mem_data[6 - i];
        end
        #(B)
            mem_data_en = 1'b0;
        #(10*B)
            $finish;
    end
    
    assign sda = (ack_en == 1'b1 || mem_data_en == 1'b1) ? ((ack_en == 1'b1) ? 1'b0 : sda_r) : 1'bz;
    assign sda_in = sda;
      
    i2c_core      i2c_core_ins(
        .rstn       (rstn),
        .clk        (clk),
        .start      (start),
        .high_addr  (high_addr),
        .dev_addr   (dev_addr),
        .mem_addr   (mem_addr),
        .rd_wr_en   (rd_wr_en),
        .data_wr    (data_wr),
        .scl        (scl),
        .sda        (sda),
        .data_rd    (data_rd)
    );


    initial begin
        $dumpfile("wave_read.vcd");
        $dumpvars(0,tb_i2c_core);
    end

endmodule
