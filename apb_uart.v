`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/06/12 16:49:39
// Design Name: 
// Module Name: apb_uart
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
//参考cmsdk的apb_uart接口和design ware 的databook
///波特率默认115200 ， 时钟频率50Mhz
//地址分配有些问题 一般情况paddr低两位不做分配，可以重新修改一下
//tb已验证single transfer的正确性，dma和fifo的部分待验证

module apb_uart   #( parameter BASE_ADDR = 32'hC3000000 )
                  (
                  input   wire          pclk ,
                  input   wire          prstn ,
                  input   wire          pwrite ,
                  input   wire          psel ,
                  input   wire  [31:0]  pwdata ,
                  input   wire  [31:0]  paddr ,
                  input   wire  [3:0]   pstrb ,
                  input   wire          penable ,
                  input   wire  [2:0]   pprot ,
                  
                  input   wire          dma_tx_acka ,
                  input   wire          dma_rx_acka ,
                  input   wire          serial_in ,
                  
                  output  wire          pready ,
                  output  wire  [31:0]  prdata ,
                  output  wire          pslverr ,
                  
                  output  wire  [7:0]   tx_ram_out ,
                  output  wire  [7:0]   rx_ram_out ,
                  output  wire          serial_out ,
                  output  wire          dma_tx_req ,
                  output  wire          dma_rx_req ,
                  output        [7:0]   shift_rxd
                 );
///----------------------参数定义------------------------------------------///
          localparam    FIFO_MODE_SET        =      32'h0 ;
          localparam    DMA_MODE_SET         =      32'h000000004 ;
          localparam    BAUD_SET             =      32'h000000008 ;
          //localparam    TX_FIFO_DEPTH_SET    =      32'h00000000C ;//没用
          //localparam    RX_FIFO_DEPTH_SET    =      32'h000000010 ;
          localparam    TX_FIFO_ADDR         =      32'h000000014 ;
          localparam    RX_FIFO_ADDR         =      32'h000000024 ;
          localparam    RBR_ADDR             =      32'h000000034 ;
          localparam    THR_ADDR             =      32'h000000044 ;
          localparam    TX_FIFO_DEPTH        =      8 ;
          localparam    RX_FIFO_DEPTH        =      8 ;

///-----------------------信号定义-----------------------------------------///
//----------------------寄存器--------------------------------------------//
          reg                                       fifo_mode ;
          reg                                       dma_mode  ;
          reg           [13:0]                      baud_rate ;
          reg           [7:0]                       tx_fifo  [TX_FIFO_DEPTH - 1 : 0] ;
          reg           [7:0]                       rx_fifo  [RX_FIFO_DEPTH - 1 : 0] ;
          reg           [7:0]                       receive_buffer_register ;
          reg           [7:0]                       transmit_holding_register ;
          reg           [3:0]                       next_state_tx ;
          reg           [3:0]                       next_state_rx ;

          reg           [7:0]                       reg_rdata ;
          reg                                       tx_reg    ;
          reg           [7:0]                       tx_shift  ;
          reg           [7:0]                       rx_shift  ;
          reg                                       shift_dff2 ;
          reg                                       shift_dff1 ;
//-----------------------fifo相关------------------------------------------//
          reg           [3:0]                       tx_fifo_addr ;  //地址
          reg           [3:0]                       rx_fifo_addr ;
          reg           [3:0]                       tx_fifo_paddr ; //指针
          reg           [3:0]                       rx_fifo_paddr ;
          reg                                       tx_fifo_empty ;
          reg                                       rx_fifo_full  ;
          reg           [3:0]                       state_tx      ;
          reg           [3:0]                       state_rx      ;

//----------------------------------波特率产生信号-----------------------------------------
          reg           [9:0]                       counter_integer_tx;
          reg           [9:0]                       counter_franction_tx ;
          reg           [9:0]                       counter_integer_rx ;
          reg           [9:0]                       counter_franction_rx ;
          reg                                       integer_baud_tick_tx ;
          reg                                       franction_baud_tick_tx ;
          reg                                       integer_baud_tick_rx ;
          reg                                       franction_baud_tick_rx ;
          reg           [3:0]                       counter_16_tx ;
          reg           [3:0]                       counter_16_rx ;

//----------------------------------buf传输信号-------------------------------------------
          reg                                       rx_buf_done ; //信号传输完成信号
          reg                                       tx_buf_done ;
//----------------------------------dma---------------------------------------------------
          reg                                       dma_tx_req_reg ;
          reg                                       dma_rx_req_reg ; 
      
//----------------------------------控制信号---------------------------------------------//
          wire                                      write_enable ;
          wire                                      read_enable ;
          wire                                      tx_fifo_enable ;
          wire                                      rx_fifo_enable ;
          reg                                       next_tx_reg ;     
          wire                                      start_serial_rx ;
          wire                                      start_serial_tx ;
          integer                                   i ;
///----------------------组合电路-----------------------------------------///
          assign        pslverr         =        1'b0 ;
          assign        tx_ram_out      =        tx_fifo[tx_fifo_paddr] ;
          assign        rx_ram_out      =        rx_fifo[rx_fifo_addr] ;
          assign        pready          =        (rx_buf_done || tx_buf_done || (next_state_rx==4'b0000 && next_state_tx==4'b0000) || dma_tx_req || dma_rx_req || ~psel || ~penable) ? 1'b1 : 1'b0 ;
          assign        serial_out      =        next_tx_reg ;
          assign        prdata          =        {24'b0 , reg_rdata} ;

          assign        write_enable    =         penable & psel & pwrite ;
          assign        read_enable     =         psel & ~pwrite ;
          assign        rx_fifo_enable  =         dma_mode & fifo_mode & ~rx_fifo_full ;
          assign        tx_fifo_enable  =         dma_mode & fifo_mode & ~tx_fifo_empty ;
          assign        start_serial_rx =         (read_enable & (paddr == BASE_ADDR + 32'h000000034) & ~fifo_mode & ~dma_mode) | rx_fifo_enable ;
          assign        start_serial_tx =         (write_enable & (paddr == BASE_ADDR + 32'h00000044) & ~fifo_mode & ~dma_mode & pstrb[0]) | tx_fifo_enable ;
          assign        dma_tx_req      =         tx_fifo_empty ;
          assign        dma_rx_req      =         rx_fifo_full ;
          
          assign        shift_rxd       =         rx_shift ;
///----------------------状态机-------------------------------------------///

          always@(posedge pclk or negedge prstn) begin
                if(~prstn)
                    state_tx   <=   4'b0 ;
                    else
                        state_tx   <=   next_state_tx ; 
                        end
          
          always@(*) begin
                case(state_tx)
                0:begin next_state_tx   =   (start_serial_tx) ? 4'b0001 : 4'b0000 ; end 
                1,2,3,4,5,6,7,8,9:begin next_state_tx   =  (counter_16_tx==4'b1111) ? (next_state_tx + integer_baud_tick_tx) : next_state_tx ;  end
                10:begin next_state_tx    =    ((counter_16_rx==4'b1111) && (integer_baud_tick_tx)) ? ((start_serial_tx) ? 4'b0001 :4'b0000) : next_state_tx ;  end                          
                11,12,13,14,15:next_state_tx <=  4'b0000 ;
                default: next_state_tx <=  4'b0000 ;
                endcase
                end
           
          always@(*) begin
                case(state_tx) 
                0:begin next_tx_reg     =   1'b1 ; end
                1:begin next_tx_reg     =   1'b0 ; end
                2,3,4,5,6,7,8,9:begin
                        next_tx_reg     =   tx_shift[0] ; end
                10:begin next_tx_reg    =   1'b1; end
                11,12,13,14,15: next_tx_reg    =   1'b1 ;
                default: next_tx_reg    =   1'b1 ;
                endcase
                end




          always@(posedge pclk or negedge prstn) begin
                if(~prstn)
                    state_rx   <=   4'b0 ;
                    else
                        state_rx   <=   next_state_rx ; 
                        end
          
          always@(*) begin
                case(state_rx)
                0:begin next_state_rx   =   (start_serial_rx) ? 4'b0001 : 4'b0000 ; end 
                1:begin next_state_rx   =   ((counter_16_rx==4'b0111) && (integer_baud_tick_rx || franction_baud_tick_rx)) ? (next_state_rx + 1) : next_state_rx; end
                2,3,4,5,6,7,8,9:begin next_state_rx   =  (counter_16_rx==4'b0111) ? (next_state_rx + (integer_baud_tick_rx||franction_baud_tick_rx)) : next_state_rx ;  end
                10:begin next_state_rx    =    ((counter_16_rx==4'b1111) && (integer_baud_tick_rx || franction_baud_tick_rx)) ? (next_state_rx+1) : next_state_rx ; end
                11:begin next_state_rx    =    ((counter_16_rx==4'b1111) && integer_baud_tick_rx) ? ((start_serial_rx) ? 4'b0001 :4'b0000) : next_state_rx ; end           
                12,13,14,15: next_state_rx <=  4'b0000 ;
                default ;
                endcase
                end
 
          always@(posedge pclk or negedge prstn) begin
                if(~prstn)
                    tx_buf_done    <=    1'b0 ;
                    else if((state_tx==4'b1010) && (counter_16_tx==4'b1111) && integer_baud_tick_tx)
                        tx_buf_done   <=    1'b1 ;
                        else if(tx_buf_done)
                            tx_buf_done    <=    1'b0 ;
                            end

          always@(posedge pclk or negedge prstn) begin
                if(~prstn)
                    rx_buf_done    <=    1'b0 ;
                    else if((state_rx==4'b1011) && (counter_16_rx==4'b1111) && (integer_baud_tick_rx || franction_baud_tick_rx) )
                        rx_buf_done   <=    1'b1 ;
                        else if(rx_buf_done)
                            rx_buf_done    <=    1'b0 ;
                            end
         
///--------------------------------移位寄存器-----------------------------------------------------------------------///
         //------------------------tx_shift---------------------------------------------//
          always@(posedge pclk or negedge prstn) begin
                if(~prstn) 
                    tx_shift    <=    8'b11111111 ;
                    else if(state_tx==4'b0001 )
                        tx_shift   <=   transmit_holding_register ;
                    else if(((state_tx[3] && ~state_tx[1]) || (~state_tx[3] && state_tx[2]) || (state_tx[3:1]==3'b001)) && ((counter_16_tx==4'b1111) && integer_baud_tick_tx)) //状态2-9需要移位
                        tx_shift   <=   {1'b1,tx_shift[7:1]} ;
                        else 
                          tx_shift    <=    tx_shift ;
                          end
         //------------------------rx_shift---------------------------------------------//
          always@(posedge pclk or negedge prstn) begin
                if(~prstn)  begin
                    receive_buffer_register  <=  8'b0 ;
                    rx_shift    <=    8'b11111111 ; end
                    else if(state_rx==4'b1011 && (&counter_16_rx) && (integer_baud_tick_rx ||franction_baud_tick_rx))
                        receive_buffer_register   <=    rx_shift ;
                    else if(((state_rx[3:1]==3'b100) || (state_rx[3:2]==2'b01) ||(state_rx[3:1]==3'b001)) && (counter_16_rx==4'b0111) && (integer_baud_tick_rx || franction_baud_tick_rx)) //状态2-9需要移位
                        rx_shift   <=   {shift_dff2,rx_shift[7:1]};
                        else 
                          rx_shift    <=    rx_shift ;
                          end

          

///--------------------------------信号同步-----------------------------------------------///
          always@(posedge pclk or negedge prstn) begin
                    if(~prstn) begin
                        shift_dff2    <=    1'b0 ;
                        shift_dff1    <=    1'b0 ;
                        end else if(start_serial_rx)
                        shift_dff2    <=    shift_dff1 ;
                        shift_dff1    <=    serial_in ;
                        end

///----------------------寄存器配置---------------------------------------///
          always@(posedge pclk or negedge prstn) begin
                if(~prstn) 
                    fifo_mode   <=   1'b0 ;
                    else if(write_enable && (paddr == BASE_ADDR + 32'h0) && pstrb[0])
                        fifo_mode   <=   pwdata[0] ;
                        end


          always@(posedge pclk or negedge prstn) begin
                if(~prstn)
                    dma_mode   <=   1'b0 ;
                    else if(write_enable && (paddr == BASE_ADDR + 32'h00000004) && pstrb[0])
                        dma_mode    <=    pwdata[0] ;
                        end
           

          always@(posedge pclk or negedge prstn) begin
                if(~prstn)
                    baud_rate    <=    14'b0000110110001 ;  //前十位表示一个bit周期数的整数部分（27），后四位表示小数部分（franctional counter）（0.126）
                    else if(write_enable && (paddr == BASE_ADDR + 32'h00000008) && pstrb[0] && pstrb[1])
                        baud_rate    <=    pwdata[13:0] ;
                        end
          

         // always@(posedge pclk or negedge prstn) begin
         //       if(~prstn)

///------------------------------------------波特率产生---------------------------------------///
//-------给你列一个式子你就懂了 设整数部分为N，分数部分为a/16，那传输1bit需要的周期数为N*16+a；传输一位要分频27.126个周期
//===========================即（N+1）*a + N*（16-a）=======================================//要做两个分频器，N和N+1
          always@(posedge pclk or negedge prstn) begin
                if(~prstn ||( ~(start_serial_tx) ))
                    counter_integer_tx    <=   baud_rate[13:4] - 1 ;        
                     else if(~(|counter_integer_tx) || (counter_16_tx[3:0] <= baud_rate[3:0]))  //整数tick计数器为0或者记满了a个周期了
                        counter_integer_tx    <=    baud_rate[13:4] - 1;
                        else 
                            counter_integer_tx    <=    counter_integer_tx - 1'b1 ;
                            end
                      
          always@(posedge pclk or negedge prstn) begin
                if(~prstn  || (~(start_serial_tx) ))
                    counter_franction_tx  <=   baud_rate[13:4]  ;
                    else if(~(|counter_franction_tx) || (counter_16_tx[3:0] > baud_rate[3:0])) // 刚开始a个周期分频27+1
                        counter_franction_tx    <=    baud_rate[13:4] ;
                        else 
                            counter_franction_tx    <=    counter_franction_tx - 1'b1 ;
                            end                    

   //-----------------tick产生--------------------------//
          always@(posedge pclk or negedge prstn) begin 
                if(~prstn  || (~(start_serial_tx) ))
                    integer_baud_tick_tx    <=    1'b0 ;
                    else if((counter_integer_tx==10'b0000000001))
                        integer_baud_tick_tx    <=    1'b1 ;
                        else if(integer_baud_tick_tx)
                            integer_baud_tick_tx    <=    1'b0 ;
                            end
          
          always@(posedge pclk or negedge prstn) begin
                if(~prstn  || (~(start_serial_tx) ))
                    franction_baud_tick_tx    <=    1'b0 ;
                    else if((counter_franction_tx==10'b0000000001))
                        franction_baud_tick_tx    <=    1'b1 ;
                        else if(franction_baud_tick_tx)
                            franction_baud_tick_tx    <=    1'b0 ;
                            end
 
//---------------------------tick计数----------------------------------//
          always@(posedge pclk or negedge prstn) begin
                if(~prstn  || (~(start_serial_tx) ))
                    counter_16_tx   <=   4'b0 ;
                     else if((integer_baud_tick_tx)||(franction_baud_tick_tx))
                        counter_16_tx   <=   counter_16_tx + 1'b1 ;
                            end


     
///-------------------------------rx产生----------------------------------
                            
          always@(posedge pclk or negedge prstn) begin
                if(~prstn ||(~(start_serial_rx)))
                    counter_integer_rx    <=   baud_rate[13:4] - 1 ;        
                     else if(~(|counter_integer_rx) || (counter_16_rx <= baud_rate[3:0]))  //整数tick计数器为0或者记满了a个周期了
                        counter_integer_rx    <=    baud_rate[13:4] - 1 ;
                        else
                            counter_integer_rx    <=    counter_integer_rx - 1'b1 ;
                            end
                      
          always@(posedge pclk or negedge prstn) begin
                if(~prstn  || (~(start_serial_rx)))
                    counter_franction_rx  <=   10'b000011010 ;
                    else if(~(|counter_franction_rx) || counter_16_rx > baud_rate[3:0]) // 刚开始a个周期分频27+1
                        counter_franction_rx    <=    baud_rate[13:4] ;
                        else 
                            counter_franction_rx    <=    counter_franction_rx - 1'b1 ;
                            end
         always@(posedge pclk or negedge prstn) begin 
                if(~prstn  || (~(start_serial_rx) ))
                    integer_baud_tick_rx    <=    1'b0 ;
                    else if(counter_integer_rx==10'b0000000001)
                        integer_baud_tick_rx    <=    1'b1 ;
                        else if(integer_baud_tick_rx)
                            integer_baud_tick_rx    <=    1'b0 ;
                            end
          
          always@(posedge pclk or negedge prstn) begin
                if(~prstn  || (~(start_serial_rx)))
                    franction_baud_tick_rx    <=    1'b0 ;
                    else if(counter_franction_rx==10'b0000000001)
                        franction_baud_tick_rx    <=    1'b1 ;
                        else if(franction_baud_tick_rx)
                            franction_baud_tick_rx    <=    1'b0 ;
                            end
                            
           always@(posedge pclk or negedge prstn) begin
                if(~prstn  || ( ~(start_serial_rx)))
                    counter_16_rx   <=   4'b0 ;  
                    else if((integer_baud_tick_rx)|| (franction_baud_tick_rx))
                        counter_16_rx   <=   counter_16_rx + 1'b1 ;
                            end

///------------------------------------------读写fifo-----------------------------------------///
   //----------------------------------------rx_fifo-------------------------------------------//       
          always@(posedge pclk or negedge prstn) begin
                if(~prstn) begin
                    for(i=0;i<RX_FIFO_DEPTH-1;i=i+1)
                        rx_fifo[i]    <=     8'b0 ; end
                    else if(fifo_mode && dma_mode && rx_buf_done && ~rx_fifo_full) 
                       rx_fifo[rx_fifo_addr]    <=     rx_shift ;
                       end

          always@(posedge pclk or negedge prstn) begin
                if(~prstn) 
                    rx_fifo_addr    <=    4'b0 ; 
                    else if(fifo_mode && dma_mode && rx_buf_done && ~rx_fifo_full ) 
                       rx_fifo_addr    <=     rx_fifo_addr + 1'b1 ;
                       end

          always@(posedge pclk or negedge prstn) begin
                if(~prstn)
                    rx_fifo_full    <=    1'b0 ;
                    else if((rx_fifo_addr==RX_FIFO_DEPTH) && rx_buf_done && ~dma_rx_acka)
                        rx_fifo_full    <=    1'b1 ;
                        else if(dma_rx_acka && rx_fifo_full)
                            rx_fifo_full    <=    1'b0 ;
                        end
   //----------------------------------------tx_fifo-------------------------------------------//
          always@(posedge pclk or negedge prstn) begin
                if(~prstn) 
                    tx_fifo_empty    <=    1'b0 ;
                    else if((tx_fifo_paddr==4'b0) && tx_buf_done && ~dma_tx_req)
                        tx_fifo_empty    <=    1'b1 ;
                        else if(dma_tx_acka && tx_fifo_empty)
                            tx_fifo_empty    <=    1'b0 ;
                            end
          
          always@(posedge pclk or negedge prstn) begin
                if(~prstn) 
                    tx_fifo_paddr    <=    TX_FIFO_DEPTH ;
                    else if(fifo_mode && dma_mode && tx_buf_done && ~tx_fifo_empty )
                        tx_fifo_paddr    <=    tx_fifo_paddr - 1'b1 ;
                        end

///------------------------------------------输入输出-----------------------------------///
          always@(posedge pclk or negedge prstn) begin
                if(~prstn)
                    transmit_holding_register    <=    8'b0 ;
                    else if(write_enable && (paddr == BASE_ADDR + 32'h00000044) && ~fifo_mode && ~dma_mode && pstrb[0])
                        transmit_holding_register    <=   pwdata[7:0] ;
                        end

          always@(posedge pclk or negedge prstn) begin
                if(~prstn || ~start_serial_rx)
                    reg_rdata    <=    8'b0 ;
                    else if(read_enable && (paddr == BASE_ADDR + 32'h00000034) && ~fifo_mode && ~dma_mode &&((state_rx==4'b1011)&&(counter_16_rx==4'b1111) && (integer_baud_tick_rx || franction_baud_tick_rx)))
                       reg_rdata    <=     rx_shift ;  
                       end

          
///----------------------------------------dma模式-------------------------------------------///

          always@(posedge pclk or negedge prstn) begin
                if(~prstn) 
                    rx_fifo_paddr    <=    4'b0 ;
                    else if(rx_fifo_full && read_enable) begin
                    rx_fifo_paddr    <=    rx_fifo_paddr + 1'b1 ;
                       reg_rdata    <=     rx_fifo[rx_fifo_paddr] ; 
                       end
                       end

          always@(posedge pclk or negedge prstn) begin
                if(~prstn) begin
                    tx_fifo_addr    <=    4'b0 ;
                    begin
                    for(i=0;i<TX_FIFO_DEPTH-1;i=i+1)
                        tx_fifo[i]    <=    8'b0 ;
                        end
                        end
                    else if(write_enable && tx_fifo_empty) begin
                    tx_fifo_addr    <=    tx_fifo_addr + 1'b1 ;
                    tx_fifo[tx_fifo_addr]    <=    pwdata[7:0] ;
                    end
                    end
endmodule
