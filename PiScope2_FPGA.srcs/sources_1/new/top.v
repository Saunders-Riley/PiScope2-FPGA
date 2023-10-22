`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/10/2023 08:45:19 PM
// Design Name: 
// Module Name: top
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


module top(
    // Raspberry Pi Interface
    input   wire        pi_rst_b,       // Pi reset input
    input   wire        pi_strb,        // Pi read/write strobe
    input   wire        pi_we_b,        // Pi write enable (neg)
    input   wire        pi_oe_b,        // Pi output enable (neg
    input   wire        pi_ad_b,        // Pi address/data select
    inout   wire[7:0]   pi_data,        // Pi data bus
    
    // ADC Interface
    output  wire        adc_oe_b,       // ADC data output enable
    input   wire        adc_dclk_p,     // ADC dclk (LVDS pos leg)
    input   wire        adc_dclk_n,     // ADC dclk (LVDS neg leg)
    input   wire[7:0]   adc_data_p,     // ADC data (LVDS pos leg)
    input   wire[7:0]   adc_data_n      // ADC data (LVDS neg leg)
    );
    
    ////////INTERNAL WIRES
    
    // Pi Interface
    wire[7:0]   pi_rd_data;         // pi interface read data
    wire[7:0]   pi_wr_data;         // pi interface write data
    
    // ADC Interface
    wire[7:0]   adc_data;           // adc interface write data
    wire        adc_dclk;           // adc data clk
    
    // BRAM Interface
    wire[15:0]  bram_wr_data;       // bram write data - out of scope.v
    wire        bram_wclk;          // bram write clock - out of scope.v
    wire        bram_we;            // bram write enable - out of scope.v
    wire[11:0]  bram_wr_addr;       // bram write address - out of scope.v
    wire[15:0]  bram_rd_data;       // bram read data - into regs.v
    wire        bram_rstrb;         // bram read strobe - out of regs.v
    wire        bram_re;            // bram read enable - out of regs.v
    wire[11:0]  bram_rd_addr;       // bram read address - out of regs.v
    
    ////////IP BLOCK INSTANTIATION
    //trace memory - 4096 captures of both channels
    blk_mem_gen_0 inst_trace_mem(
      .clka(bram_wclk),             // input wire clka
      .ena(bram_we),                // input wire ena
      .wea(bram_we),                // input wire [0 : 0] wea
      .addra(bram_wr_addr),         // input wire [11 : 0] addra
      .dina(bram_wr_data),          // input wire [15 : 0] dina
      .clkb(bram_rstrb),            // input wire clkb
      .enb(bram_re),                // input wire enb
      .addrb(bram_rd_addr),         // input wire [11 : 0] addrb
      .doutb(bram_rd_data)          // output wire [15 : 0] doutb
    );
    //Buffer primitives
    genvar i;
    generate
        for(i = 0; i < 8; i = i + 1) begin
            //pi_data IO buffers
            IOBUF #(
               .DRIVE(8),                   // Specify the output drive strength
               .IBUF_LOW_PWR("TRUE"),       // Low Power - "TRUE", High Performance = "FALSE"
               .IOSTANDARD("LVCMOS33"),     // Specify the I/O standard
               .SLEW("SLOW")                // Specify the output slew rate
            ) IOBUF_inst_pi_data (
               .O(pi_wr_data[i]),           // Buffer output
               .IO(pi_data[i]),             // Buffer inout port (connect directly to top-level port)
               .I(pi_rd_data[i]),           // Buffer input
               .T(pi_oe_n)                  // 3-state enable input, high=input, low=output
            );
            //adc_data input buffers
            IBUFDS #(
               .DIFF_TERM("TRUE"),          // Differential Termination
               .IBUF_LOW_PWR("TRUE"),       // Low power="TRUE", Highest performance="FALSE"
               .IOSTANDARD("LVDS")          // Specify the input I/O standard
            ) IBUFDS_inst_adc_data (
               .O(adc_data[i]),             // Buffer output
               .I(adc_data_p[i]),           // Diff_p buffer input (connect directly to top-level port)
               .IB(adc_data_n[i])           // Diff_n buffer input (connect directly to top-level port)
            );
        end
    endgenerate
    //adc_dclk input buffer
    IBUFDS #(
       .DIFF_TERM("TRUE"),          // Differential Termination
       .IBUF_LOW_PWR("TRUE"),       // Low power="TRUE", Highest performance="FALSE"
       .IOSTANDARD("LVDS")          // Specify the input I/O standard
    ) IBUFDS_inst_adc_data (
       .O(adc_dclk),                // Buffer output
       .I(adc_dclk_p),              // Diff_p buffer input (connect directly to top-level port)
       .IB(adc_dclk_n)              // Diff_n buffer input (connect directly to top-level port)
    );
    
    ////////MODULE INSTANTIATION
    scope inst_scope(
        // global
        .rst_b(pi_rst_b),               // hardware reset
        .ext_trig(),                    // external trigger input
        .ready_out(),                   // ready state indicator output
        .trig_out(),                    // trigger state indicator output
        
        // adc interface
        .adc_data_in(adc_data),                 // adc data input
        .adc_dclk(adc_dclk),                    // adc data clock
        .adc_oe_b(adc_oe_b),                    // adc output enable
        
        // bram interface
        .bram_wr_data(bram_wr_data),                // bram write data
        .bram_wclk(bram_wclk),                   // bram write clock
        .bram_we(bram_we),                     // bram write enable
        .bram_wr_addr(bram_wr_addr),                // bram write address
        
        // register interface
        .scope_ctl(),                   // control register
        .sample_rate(),                 // sample rate divider register - range [1 : 1/(2^15)]
        .trig_msk(),                    // channel A/B trigger mask register
        .trig_thresh(),                 // trigger threshold
        .obvs_state()                   // state observation
    );
endmodule
