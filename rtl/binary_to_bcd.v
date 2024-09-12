`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Digilent Inc.
// Engineer: Josh Sackos
// 
// Create Date:    07/11/2012
// Module Name:    Binary_To_BCD
// Project Name:   PmodGYRO_Demo
// Target Devices: Nexys3
// Tool versions:  ISE 14.1
// Description: This module receives a 16 bit binary value and converts it to
//              a packed binary coded decimal (BCD) using the shift add 3
//              algorithm.
//
//              The output consists of 4 BCD digits as follows:
//
//                      BCDOUT[15:12]  - Thousands place
//                      BCDOUT[11:8]   - Hundreds place
//                      BCDOUT[7:4]    - Tens place
//                      BCDOUT[3:0]    - Ones place
//
// Revision History: 
//                   Revision 0.01 - File Created (Josh Sackos)
//////////////////////////////////////////////////////////////////////////////////


// ==============================================================================
//                                 Define Module
// ==============================================================================
module binary_to_bcd(
         CLK,
         RST,
         START,
         BIN,
         BCDOUT
   );


   // ===========================================================================
   //                               Port Declarations
   // ===========================================================================
         input CLK;                 // 100Mhz CLK
         input RST;                 // Reset
         input START;               // Signal to initialize conversion
         input [15:0] BIN;          // Binary value to be converted
         output [15:0] BCDOUT;      // 4 digit binary coded decimal output


   // ===========================================================================
   //                        Parameters, Regsiters, and Wires
   // ===========================================================================
         reg [15:0] BCDOUT = 16'h0000;    // Output BCD values, contains 4 digits
         
         reg [4:0] shiftCount = 5'd0;     // Stores number of shifts executed
         reg [31:0] tmpSR;                // Temporary shift regsiter

         reg [2:0] STATE = Idle;          // Present state
         
         // FSM States
         parameter [2:0] Idle = 3'b000,
                         Init = 3'b001,
                         Shift = 3'b011,
                         Check = 3'b010,
                         Done = 3'b110;


   // ===========================================================================
   //                               Implementation
   // ===========================================================================


         //------------------------------
         //      Binary to BCD FSM
         //------------------------------
         always @(posedge CLK) begin
               if(RST == 1'b1) begin
                     // Reset/clear values
                     BCDOUT <= 16'h0000;
                     tmpSR <= 31'h00000000;
                     STATE <= Idle;
               end
               else begin

                     case (STATE)
                     
                           // Idle State
                           Idle : begin
                                 BCDOUT <= BCDOUT;                         // Output does not change
                                 tmpSR <= 32'h00000000;                    // Temp shift reg empty
                                 
                                 if(START == 1'b1) begin
                                       STATE <= Init;
                                 end
                                 else begin
                                       STATE <= Idle;
                                 end
                           end

                           // Init State
                           Init : begin
                                 BCDOUT <= BCDOUT;                         // Output does not change
                                 tmpSR <= {16'b0000000000000000, BIN};     // Copy input to lower 16 bits

                                 STATE <= Shift;
                           end

                           // Shift State
                           Shift : begin
                                 BCDOUT <= BCDOUT;                   // Output does not change
                                 tmpSR <= {tmpSR[30:0], 1'b0};       // Shift left 1 bit

                                 shiftCount <= shiftCount + 1'b1;    // Count the shift
                                 
                                 STATE <= Check;                     // Check digits

                           end

                           // Check State
                           Check : begin
                                 BCDOUT <= BCDOUT;                   // Output does not change

                                 // Not done converting
                                 if(shiftCount != 5'd16) begin

                                       // Add 3 to thousands place
                                       if(tmpSR[31:28] >= 3'd5) begin
                                             tmpSR[31:28] <= tmpSR[31:28] + 2'd3;
                                       end

                                       // Add 3 to hundreds place
                                       if(tmpSR[27:24] >= 3'd5) begin
                                             tmpSR[27:24] <= tmpSR[27:24] + 2'd3;
                                       end
                                       
                                       // Add 3 to tens place
                                       if(tmpSR[23:20] >= 3'd5) begin
                                             tmpSR[23:20] <= tmpSR[23:20] + 2'd3;
                                       end
                                       
                                       // Add 3 to ones place
                                       if(tmpSR[19:16] >= 3'd5) begin
                                             tmpSR[19:16] <= tmpSR[19:16] + 2'd3;
                                       end

                                       STATE <= Shift;   // Shift again

                                 end
                                 // Done converting
                                 else begin
                                       STATE <= Done;
                                 end
                                 
                           end
                           
                           // Done State
                           Done : begin
                           
                                 BCDOUT <= tmpSR[31:16]; // Assign output the new BCD values
                                 tmpSR <= 32'h00000000;  // Clear temp shift register
                                 shiftCount <= 5'b00000; // Clear shift count

                                 STATE <= Idle;

                           end
                     endcase
               end
         end

endmodule
