`timescale 1ns / 1ns
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/06/12 17:14:52
// Design Name: 
// Module Name: tb_apb_uart
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
 

module apb_uart_tb(

    );
reg         pclk ;    
reg         prstn ;
reg         pwrite ;
reg         psel ;
reg  [31:0] pwdata ;
reg  [31:0] paddr ;
reg  [3:0]  pstrb ;
reg         penable ;
reg  [2:0]  pprot ;
reg         dma_tx_acka ;
reg         dma_rx_acka ;
reg         serial_in ;

wire        pready ;
wire [31:0] prdata ;
wire        pslverr ;
wire [7:0]  tx_ram_out ;
wire [7:0]  rx_ram_out ;
wire        serial_out ;
wire        dma_tx_req ;
wire        dma_rx_req ;
wire [7:0]  shift_rxd ;

parameter BASE_ADDR  =  32'hC3000000 ;


    initial begin
        pclk = 0;
        forever 
            # (5) pclk = ~pclk;
    end


initial begin
    prstn   =  0 ;
#15 psel    =  1 ;
    pwrite  =  1 ;
    pstrb   =  4'h1 ;
    pprot   =  3'b000 ;
    pwdata  =  32'h00000089;
    paddr   =  BASE_ADDR + 32'h00000044;
    penable =  0 ;
#10 prstn   =  1;
    penable = 1;
#39050 ;  //  single tx
#10 psel    =  0 ;
#20 psel    =  1 ;
    pwrite  =  0 ;
    pstrb   =  4'h1 ;
    pprot   =  3'b000 ;
    paddr   =  BASE_ADDR + 32'h00000034;
    penable =  0 ;
#10 penable =  1 ;
    serial_in = 0 ;
#4340
    serial_in = 1 ;
#4340
    serial_in = 0 ;
#4340
    serial_in = 1 ;
#4340
    serial_in = 0 ;
#4340
    serial_in = 1 ;
#4340
    serial_in = 0 ;
#4340
    serial_in = 1 ;
#4340
    serial_in = 0 ;
#4340
    serial_in = 1 ;    
#4360
    psel = 0 ;
    end

apb_uart  #(.BASE_ADDR(BASE_ADDR)) u1
            (
            .pclk(pclk),
            .prstn(prstn),
            .pwrite(pwrite),
            .pwdata(pwdata),
            .psel(psel),
            .paddr(paddr),
            .pstrb(pstrb),
            .penable(penable),
            .pprot(pprot),
            .dma_tx_acka(dma_tx_acka),
            .dma_rx_acka(dma_rx_acka),
            .serial_in(serial_in),
            .pready(pready),
            .prdata(prdata),
            .pslverr(pslverr),
            .tx_ram_out(tx_ram_out),
            .rx_ram_out(rx_ram_out),
            .serial_out(serial_out),
            .dma_tx_req(dma_tx_req),
            .dma_rx_req(dma_rx_req),
            .shift_rxd(shift_rxd) 
            ) ;


endmodule
