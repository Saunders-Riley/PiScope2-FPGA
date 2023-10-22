`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/16/2023 06:03:17 PM
// Design Name: 
// Module Name: scope
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module scope(
    // global
    input   wire        rst_b,              // hardware reset
    input   wire        ext_trig,           // external trigger input
    output  wire        ready_out,          // ready state indicator output
    output  wire        trig_out,           // trigger state indicator output
    
    // adc interface
    input   wire[7:0]   adc_data_in,        // adc data input
    input   wire        adc_dclk,           // adc data clock
    output  wire        adc_oe_b,           // adc output enable
    
    // bram interface
    output  wire[15:0]  bram_wr_data,       // bram write data
    output  wire        bram_wclk,          // bram write clock
    output  wire        bram_we,            // bram write enable
    output  wire[11:0]  bram_wr_addr,       // bram write address
    
    // register interface
    input   wire[7:0]   scope_ctl,          // control register
    input   wire[7:0]   sample_rate,        // sample rate divider register - range [1 : 1/(2^15)]
    input   wire[7:0]   trig_msk,           // channel A/B trigger mask register
    input   wire[7:0]   trig_thresh,        // trigger threshold
    output  wire[7:0]   obvs_state          // state observation
    );
    
    ////////INTERNAL WIRES
    wire        clk_int;                    // internal clock
    reg[15:0]   clk_cntr;                   // internal clock counter
    
    wire        scope_en;                   // scope logic enable
    wire        scope_rst;                  // scope logic reset
    wire        fifo_rst;                   // fifo reset
    wire        fifo_rdy;                   // fifo ready signal
    
    wire[1:0]   trig_src;                   // trigger source
    wire        trig_rising;                // channel edge-trigger - rising edge
    wire        trig_falling;               // channel edge-trigger - falling edge
    wire        trig_ext_hi;                // external digital trigger - high state
    wire        trig_ext_lo;                // external digital trigger - low state
    wire        trig_ext_rise;              // external edge-trigger - rising edge
    wire        trig_ext_fall;              // external edge-trigger - falling edge
    
    reg[7:0]    adc_ch_a_raw;               // channel A raw adc sample - runs at adc_dclk
    reg[7:0]    adc_ch_a_pipe;              // channel A pipelined sample - runs at clk_int
    reg[7:0]    adc_ch_a_last;              // channel A previous sample - runs at clk_int
    reg[7:0]    adc_ch_b_raw;               // channel B raw adc sample - runs at adc_dclk
    reg[7:0]    adc_ch_b_pipe;              // channel B pipelined sample - runs at clk_int
    reg[7:0]    adc_ch_b_last;              // channel B previous sample - runs at clk_int
    reg         ext_trig_pipe;
    reg         ext_trig_last;
    reg[15:0]   adc_data_concat;            // concatenated adc data
    reg         fifo_rst_reg;               // fifo reset register
    reg         fifo_we_reg;                // fifo write enable register
    reg         fifo_re_reg;                // fifo read enable register
    reg         bram_we_reg;                // bram write enable register
    reg[12:0]   bram_waddr_reg;             // bram write address register
    reg[3:0]    cur_state;                  // state machine current state
    reg[3:0]    next_state;                 // state machine next state
    
    ////////STATIC ASSIGNMENT
    assign clk_int = clk_cntr[sample_rate[3:0]];
    assign scope_rst = ~rst_b | scope_ctl[0];
    assign scope_en = scope_ctl[1] & ~scope_rst;
    assign fifo_rst = scope_rst | fifo_rst_reg;
    assign bram_wclk = clk_int;
    
    assign trig_src = trig_msk[7:6];
    assign trig_ext_rise = trig_msk[5];
    assign trig_ext_fall = trig_msk[4];
    assign trig_ext_hi = trig_msk[3];
    assign trig_ext_lo = trig_msk[2];
    assign trig_rising = trig_msk[1];
    assign trig_falling = trig_msk[0];

    integer TRIG_EXT = 2'b00;
    integer TRIG_CHA = 2'b01;
    integer TRIG_CHB = 2'b10;
    integer TRIG_FRC = 2'b11;
    
    integer IDLE = 4'h0;
    integer AWAIT = 4'h1;
    integer READY = 4'h2;
    integer CAPTURE = 4'h3;
    integer POST = 4'h4;
    
    assign obvs_state = {4'b0000, cur_state};
    assign ready_out = (cur_state == READY) ? 1'b1 : 1'b0;
    assign trig_out = (cur_state == CAPTURE) ? 1'b1 : 1'b0;
    assign adc_oe_b = (cur_state != IDLE) ? 1'b0 : 1'b1;
    
    ////////IP INSTANTIATION
    // data capture FIFO 2048x16 - captures data prior to trigger
    fifo_generator_0 inst_scope_fifo (
      .clk(clk_int),                        // input wire clk
      .rst(fifo_rst),                       // input wire rst
      .din(adc_data_concat),                // input wire [15 : 0] din
      .wr_en(fifo_we_reg),                  // input wire wr_en
      .rd_en(fifo_re_reg),                  // input wire rd_en
      .dout(bram_wr_data),                  // output wire [15 : 0] dout
      .full(fifo_rdy),                      // output wire full
      .empty(1'bZ)                          // output wire empty
    );
    
    ////////SAMPLE CAPTURE AND CLOCK DIVIDER
    always @(posedge adc_dclk) begin
        clk_cntr <= clk_cntr + 1;
        if(scope_en == 1'b1) adc_ch_a_raw <= adc_data_in;
    end
    always @(negedge adc_dclk) begin
        if(scope_en == 1'b1) adc_ch_b_raw <= adc_data_in;
    end
        
    ////////STATE MACHINE
    always @(posedge clk_int) begin
        if(scope_en == 1'b1) begin
            adc_ch_a_last <= adc_ch_a_pipe;
            adc_ch_a_pipe <= adc_ch_a_raw;
            adc_ch_b_last <= adc_ch_b_pipe;
            adc_ch_b_pipe <= adc_ch_b_raw;
            adc_data_concat <= (adc_ch_b_pipe << 8) | (adc_ch_a_pipe << 0);
            ext_trig_last <= ext_trig_pipe;
            ext_trig_pipe <= ext_trig;
            case(cur_state)
                IDLE: begin
                    // pre-trigger state - scope is idled and no data is being written to the FIFO
                    fifo_rst_reg <= 1'b1;
                    fifo_re_reg <= 1'b0;
                    fifo_we_reg <= 1'b0;
                    bram_waddr_reg <= 13'h0000;
                    bram_we_reg <= 1'b0;
                    if(scope_ctl[2] == 1'b1) next_state <= AWAIT;
                    else next_state <= IDLE;
                end
                AWAIT: begin
                    // pre-trigger state - waiting for the FIFO to fill prior to enabling trigger logic
                    // this enables a full-width capture with data prior to trigger
                    // How long this state lasts is dependent on the sample rate, but should be ~130us at worst
                    fifo_rst_reg <= 1'b0;
                    fifo_re_reg <= 1'b0;
                    fifo_we_reg <= 1'b1;
                    bram_waddr_reg <= 13'h0000;
                    bram_we_reg <= 1'b0;
                    if(fifo_rdy == 1'b1) next_state <= READY;
                    else next_state <= AWAIT;
                end
                READY: begin
                    // pre-trigger state - waiting for adc_ch_*_pipe and adc_ch_*_last to meet trigger conditions
                    // data is being written to the FIFO and the first samples discarded to maintain a full FIFO
                    // No data is being written to the BRAM just yet
                    fifo_rst_reg <= 1'b0;
                    fifo_re_reg <= 1'b1;
                    fifo_we_reg <= 1'b1;
                    bram_waddr_reg <= 13'h0000;
                    bram_we_reg <= 1'b0;
                    
                    // TRIGGER LOGIC
                    // external trigger
                    if(trig_src == TRIG_EXT) begin
                        if(trig_ext_rise == 1'b1) begin
                            if(ext_trig_pipe == 1'b1 && ext_trig_last == 1'b0) next_state <= CAPTURE;
                        end
                        if(trig_ext_fall == 1'b1) begin
                            if(ext_trig_pipe == 1'b0 && ext_trig_last == 1'b1) next_state <= CAPTURE;
                        end
                        if(trig_ext_hi == 1'b1) begin
                            if(ext_trig_pipe == 1'b1) next_state <= CAPTURE;
                        end
                        if(trig_ext_lo == 1'b1) begin
                            if(ext_trig_pipe == 1'b0) next_state <= CAPTURE;
                        end
                    end
                    // channel A trigger
                    if(trig_src == TRIG_CHA) begin
                        if(trig_rising == 1'b1) begin
                            if((adc_ch_a_pipe > trig_thresh) && (adc_ch_a_pipe > adc_ch_a_last)) next_state <= CAPTURE;
                        end
                        if(trig_falling == 1'b1) begin
                            if((adc_ch_a_pipe < trig_thresh) && (adc_ch_a_pipe < adc_ch_a_last)) next_state <= CAPTURE;
                        end
                    end
                    // channel B trigger
                    if(trig_src == TRIG_CHB) begin
                        if(trig_rising == 1'b1) begin
                            if((adc_ch_b_pipe > trig_thresh) && (adc_ch_b_pipe > adc_ch_b_last)) next_state <= CAPTURE;
                        end
                        if(trig_falling == 1'b1) begin
                            if((adc_ch_b_pipe < trig_thresh) && (adc_ch_b_pipe < adc_ch_b_last)) next_state <= CAPTURE;
                        end
                    end
                    if(trig_src == TRIG_FRC) begin
                        next_state <= CAPTURE;
                    end
                end
                CAPTURE: begin
                    // capture state - data is being transfered from the FIFO into the memory until the memory is full
                    bram_waddr_reg <= bram_waddr_reg + 1;
                    bram_we_reg <= 1'b1;
                    if(bram_waddr_reg[12] == 1'b1) next_state <= POST;
                    else next_state <= CAPTURE;
                end
                POST: begin
                    // post-capture state - FIFO is cleared out and scope awaits a signal to return to idle state
                    fifo_rst_reg <= 1'b1;
                    fifo_re_reg <= 1'b0;
                    fifo_we_reg <= 1'b0;
                    if(scope_ctl[3] == 1'b1) next_state <= IDLE;
                    else next_state <= POST;
                end
            endcase
            cur_state <= next_state;
        end
    end
    
    ////////ASYNC/SYNC RESET
    always @(posedge scope_rst) begin
        adc_ch_a_last <= 8'h00;
        adc_ch_a_pipe <= 8'h00;
        adc_ch_b_last <= 8'h00;
        adc_ch_b_pipe <= 8'h00;
        adc_data_concat <= 16'h0000;
        ext_trig_last <= 1'b0;
        ext_trig_pipe <= 1'b0;
        fifo_rst_reg <= 1'b1;
        fifo_re_reg <= 1'b0;
        fifo_we_reg <= 1'b0;
        bram_waddr_reg <= 13'h0000;
        bram_we_reg <= 1'b0;
        cur_state <= IDLE;
        next_state <= IDLE;
    end
        
endmodule
