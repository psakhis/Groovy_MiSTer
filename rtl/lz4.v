`timescale 1ns / 1ps
module lz43 (
      input         lz4_clk,
      input         lz4_reset,
      input         lz4_mode_64,             // 64bits mode enable
      input         lz4_run,                 // continue flag  
      input         lz4_stop,                // stop after long uncompressed_long valid
      input [31:0]  lz4_compressed_bytes,    // bytes of compressed blocks (end condition)  
      input [63:0]  lz4_compressed_long,     // compressed long
      input         lz4_write_long,          // write compressed long      
                
      output        lz4_write_ready,         // fifo is free
      output [7:0]  lz4_uncompressed_byte,   // decodified word            
      output        lz4_byte_valid,          // indicates if uncompressed_byte is valid     
      output [63:0] lz4_uncompressed_long,   // decodified long
      output        lz4_long_valid,          // indicates if uncompressed_long is valid       
      output [31:0] lz4_uncompressed_bytes,  // current uncompressed bytes
      output        lz4_paused,              // needs more input compressed words
      output        lz4_done,                // last state
      output        lz4_error,               // last state error flag
      output [3:0]  lz4_state
/* DEBUG 
      output [31:0] lz4_gravats,
      output [31:0] lz4_llegits,
      output        lz4_read_ready           */
);

parameter BLOCKS_SIZE = 16'd128;  //enough for max ddr_burst
parameter WINDOW_SIZE = 16'd8192;

parameter S_Idle                    = 4'd00; 
parameter S_Read_Token              = 4'd01; 
parameter S_Read_Literals_Length    = 4'd02; 
parameter S_Read_Literals_Length_64 = 4'd03; 
parameter S_Read_Literals           = 4'd04;
parameter S_Read_Literals_64        = 4'd05; 
parameter S_Read_Offset             = 4'd06; 
parameter S_Read_Match_Offset       = 4'd07; 
parameter S_Done                    = 4'd08; 
parameter S_Done_64                 = 4'd09; 
parameter S_Read_Match_Length       = 4'd10;
parameter S_Read_Match_Length_64    = 4'd11;
parameter S_Copy_Matches            = 4'd12;
parameter S_Copy_Matches_64         = 4'd13; 
parameter S_Copy_Matches_64_8       = 4'd14; 

reg [3:0]  state = S_Idle;

 
reg [63:0] blocks[BLOCKS_SIZE];   // input compressed buffer
reg [6:0]  block_read_addr   = 7'd0;
reg [31:0] block_read_total  = 32'd0;
reg [2:0]  block_read_index  = 3'd0;
reg [6:0]  block_write_addr  = 7'd0;
reg [31:0] block_write_total = 32'd0;
reg [7:0]  data;
reg [63:0] data_64;

reg [63:0] window_data;
reg [63:0] window[WINDOW_SIZE];    // Decoded window buffer
reg [15:0] window_addr = 16'd0;
reg [02:0] window_addr3 = 3'd0;
reg [12:0] window_addr13  = 13'd0;

reg [02:0] MP3 = 3'd0;
reg [12:0] MP13 = 13'd0;

reg [31:0] LL = 32'd0, ML = 32'd0; // Token: Literal length / Match length 
reg [15:0] MP = 16'd0;             // Match pointer from decoded buffer (window) to copy literals
reg [31:0] LL_W = 32'd0, ML_W = 32'd0; // Token: Literal length / Match length writed
reg [15:0] offset = 16'd0;         // Match Offset (little endian)

reg [7:0] uncompressed_byte = 8'd0;
reg [63:0] uncompressed_long = 64'd0;
reg [31:0] uncompressed_bytes = 32'd0;
reg byte_valid = 1'b0;
reg long_valid = 1'b0;
reg paused = 1'b0;
reg done = 1'b0;
reg error = 1'b0;



//write new compressed bytes
always @(posedge lz4_clk) begin             
                 
       if (lz4_reset) begin
         block_write_addr  <= 7'd0;                     
         block_write_total <= 32'd0;
       end                                       

       // 8-byte write mode  
       if (lz4_write_ready && lz4_write_long) begin    
         blocks[block_write_addr] <= lz4_compressed_long;   
         block_write_addr         <= block_write_addr + 1'b1;
         block_write_total        <= block_write_total + 32'd8;           
       end                              
end

//read next byte from input compressed buffer
task next_word;
  begin    
    data_64          <= lz4_mode_64 && read_ready_64 && block_read_index == 0 ? blocks[block_read_addr] : 64'd0;
    data             <= blocks[block_read_addr][8*block_read_index +: 8];
    block_read_index <= block_read_index + 1'b1;    
    block_read_total <= block_read_total + 1'b1; 
    if (block_read_index == 3'd7) block_read_addr <= block_read_addr + 1'b1;
  end
endtask

//read next long from input compressed buffer
task next_long;
  begin    
    data_64          <= blocks[block_read_addr];
    block_read_addr  <= block_read_addr + 1'b1;   
    block_read_total <= block_read_total + 16'd8;       
  end
endtask

//fetch next long from input compressed buffer
task fetch_long;
  begin    
    block_read_index <= 2'd0;
    block_read_addr  <= block_read_addr + 1'b1;   
    block_read_total <= block_read_total + 16'd7;    
  end
endtask

//read bytes 
always @(posedge lz4_clk) begin

       if (lz4_reset) begin
         state              <= S_Idle;
         ML                 <= 32'd0;
         LL                 <= 32'd0;                    
         MP                 <= 16'd0;                    
         offset             <= 16'd0;                                                                           
         window_addr        <= 16'd0;  
         window_addr3       <= 3'd0;
         window_addr13      <= 13'd0;
         uncompressed_bytes <= 16'd0;                              
         block_read_addr    <= 7'd0; 
         block_read_index   <= 3'd0;                    
         block_read_total   <= 32'd0;       
         byte_valid         <= 1'b0; 
         long_valid         <= 1'b0;                  
         done               <= 1'b0;
         error              <= 1'b0;
       end                                   
                       
       paused        <= 1'b0; 

       if (lz4_run && (!long_valid || !lz4_stop)) begin                    
                    
         byte_valid    <= 1'b0; 
         long_valid    <= 1'b0;                      
                                                                  
         case (state)
                 S_Idle: 
                   begin           
                     if (read_ready) begin             
                       state <= S_Read_Token;                      
                       next_word();                       
                     end else paused <= 1'b1;                    
                   end 
                 
                 S_Read_Token: 
                   begin         
                     if (read_ready) begin      
                       ML    <= data[3:0];  // Match length        
                       LL    <= data[7:4];  // Literal length    
                       ML_W  <= 32'd0;      // ML writed
                       LL_W  <= 32'd0;      // LL writed                            
                       state <= data[7:4] == 15 ? S_Read_Literals_Length : S_Read_Literals; // Literal length add bytes ?                                 
                       next_word();   
                     end else paused <= 1'b1;                                  
                   end        
                   
                 S_Read_Literals_Length:                            
                   begin                         
                     if (read_ready) begin                       
                       if (data_64 == {64'b1}) begin
                         LL <= LL + 32'd2040;
                         fetch_long();
                         state <= S_Read_Literals_Length_64;
                       end else begin
                         LL <= LL + data;                                  
                         next_word();
                       end
                       if (data != 255) state <= S_Read_Literals;  // Literal length add bytes ?                                                                                                                                          
                     end else paused <= 1'b1;  
                   end                  
                 
                 S_Read_Literals_Length_64:                            
                   begin  
                     next_word(); 
                     state <= S_Read_Literals_Length;
                   end

                 S_Read_Literals: 
                   begin                 
                     if (read_ready || blocks_readed) begin          // Last Block miss match section              
                       if (LL == 0) begin                            // No more literals to copy                            
                         offset[7:0] <= blocks_readed ? 8'd0 : data;                                                           
                         state       <= S_Read_Offset;
                         next_word();                                                                              
                       end else begin                                       
                         LL                              <= LL - 1'b1; 
                         LL_W                            <= LL_W + 1'b1; 
                         //write_word                                                                                                                         
                         window_addr                     <= window_addr + 1'b1;    
                         window_addr3                    <= window_addr3 + 1'b1;                            
                         {uncompressed_byte, window_data[8*window_addr3 +:8]} <= {2{data}};                 
                         if (!lz4_mode_64) begin                          
                           byte_valid                    <= 1'b1;                           
                           uncompressed_bytes            <= uncompressed_bytes + 32'd1;
                         end          
                         if (window_addr3 == 7) begin
                           if (lz4_mode_64) uncompressed_bytes <= uncompressed_bytes + 32'd8;                           
                           long_valid                          <= 1'b1;
                           uncompressed_long                   <= {data, window_data[00 +: 56]};       
                           window[window_addr13]               <= {data, window_data[00 +: 56]};
                           window_addr13                       <= window_addr13 + 1'b1;                                                                                                                                        
                         end  
                         //end write_word

                         if (lz4_mode_64 && read_ready_64 && LL > 8 && block_read_index == 0 && LL_W >= window_addr3) begin // 64bit mode
                           state <= S_Read_Literals_64;
                           next_long();
                         end else begin
                           next_word();
                         end           
                         //next_word();                                                                                                                           
                       end                                                        
                     end else paused <= 1'b1;                                  
                   end       
              
                 S_Read_Literals_64: 
                   begin   
                     if (read_ready || blocks_readed) begin                                                       
                       LL                 <= LL - 32'd8;
                       LL_W               <= LL_W + 32'd8;                                              
                       //write_long                      
                       long_valid         <= 1'b1;
                       window_addr        <= window_addr + 16'd8; 
                       window_addr13      <= window_addr13 + 1'b1;
                       uncompressed_bytes <= uncompressed_bytes + 32'd8;
                       case (window_addr3)
                         0: begin 
                              window_data                                 <= data_64;
                              {uncompressed_long, window[window_addr13]}  <= {2{data_64}};                             
                            end
                         1: begin 
                              window_data[00 +: 08]                       <= data_64[56 +: 08];  
                              {uncompressed_long, window[window_addr13]}  <= {2{data_64[00 +: 56], window_data[00 +: 08]}};                                                        
                            end
                         2: begin         
                              window_data[00 +: 16]                       <= data_64[48 +: 16];                                     
                              {uncompressed_long, window[window_addr13]}  <= {2{data_64[00 +: 48], window_data[00 +: 16]}};   
                            end 
                         3: begin         
                              window_data[00 +: 24]                       <= data_64[40 +: 24];  
                              {uncompressed_long, window[window_addr13]}  <= {2{data_64[00 +: 40], window_data[00 +: 24]}};                                     
                            end 
                         4: begin         
                              window_data[00 +: 32]                       <= data_64[32 +: 32];   
                              {uncompressed_long, window[window_addr13]}  <= {2{data_64[00 +: 32], window_data[00 +: 32]}};                                       
                            end 
                         5: begin         
                              window_data[00 +: 40]                       <= data_64[24 +: 40];   
                              {uncompressed_long, window[window_addr13]}  <= {2{data_64[00 +: 24], window_data[00 +: 40]}};                                          
                            end 
                         6: begin         
                              window_data[00 +: 48]                       <= data_64[16 +: 48];   
                              {uncompressed_long, window[window_addr13]}  <= {2{data_64[00 +: 16], window_data[00 +: 48]}};                                         
                            end 
                         7: begin         
                              window_data[00 +: 56]                       <= data_64[08 +: 56];                              
                              {uncompressed_long, window[window_addr13]}  <= {2{data_64[00 +: 08], window_data[00 +: 56]}}; 
                            end         
                       endcase 
                       //end write_long
                       if (read_ready_64 && LL >= 16) begin                             
                         next_long();
                       end else begin
                         state <= S_Read_Literals;
                         next_word();
                       end      
                     end else paused <= 1'b1;
                   end

                 S_Read_Offset: 
                   begin                   
                     offset[15:8] <= blocks_readed ? 8'd0 : data; // Match offset 2 bytes complete                               
                     state        <= S_Read_Match_Offset;
                   end 

                 S_Read_Match_Offset: 
                   begin
                     if ((offset == 0 && ML == 0) || blocks_readed)   // Last Block                 
                       state <= S_Done;
                     else if (ML < 15) begin          // Prepared to copy, match length no has additional bytes
                       ML    <= ML + 16'd4;           // Add 4 bytes to match length (minium match length) 
                       MP    <= window_addr - offset; // Set match pointer from decoded window buffer
                       MP3   <= (window_addr - offset) % 8;
                       MP13  <= (window_addr - offset) >> 3;
                       state <= S_Copy_Matches;       // Copy literals match bytes 
                     end else begin                   // Add bytes to match length (ML == 15)
                       if (read_ready) begin                    
                         next_word();                           
                         state <= S_Read_Match_Length;
                       end else paused <= 1'b1;                                                                                                                                                                                
                     end    
                   end

                 S_Done: 
                   begin                     
                     if (lz4_mode_64 && window_addr3 != 0) begin                                    
                       long_valid         <= 1'b1;     
                       uncompressed_bytes <= uncompressed_bytes + window_addr3;
                       uncompressed_long  <= window_data;                      
                       state              <= S_Done_64;
                     end else begin
                       done               <= 1'b1;
                       error              <= offset == 0 && ML == 0 && LL == 0 && blocks_readed ? 1'b0 : 1'b1;                    
                     end                     
                   end                   
                 
                 S_Done_64: 
                   begin                                          
                     done  <= 1'b1;
                     error <= offset == 0 && ML == 0 && LL == 0 && blocks_readed ? 1'b0 : 1'b1;                                                           
                   end

                 S_Read_Match_Length: 
                   begin                          
                     if (data < 255) begin
                       ML    <= ML + data + 16'd4; 
                       MP    <= window_addr - offset;
                       MP3   <= (window_addr - offset) % 8;
                       MP13  <= (window_addr - offset) >> 3;
                       state <= S_Copy_Matches;      
                     end else begin                     // More match length (data = 255)                              
                       if (read_ready) begin                        
                         if (data_64 == {64'b1}) begin
                           ML <= ML + 32'd2040;
                           fetch_long();
                           state <= S_Read_Match_Length_64;
                         end else begin
                           ML <= ML + data;                         
                           next_word();                                                 
                         end
                       end else paused <= 1'b1;  
                     end                                     
                   end                                                             

                 S_Read_Match_Length_64: 
                   begin               
                     next_word();
                     state <= S_Read_Match_Length;
                   end                                             

                 S_Copy_Matches:
                   begin
                     ML                              <= ML - 1'b1; 
                     ML_W                            <= ML_W + 1'b1;     
                     MP                              <= MP + 1'b1;                                             
                     MP3                             <= MP3 + 1'b1;
                     MP13                            <= MP3 == 7 ? MP13 + 1'b1 : MP13;                     
                     //write_word                                                                                                                                                                                                                             
                     window_addr                     <= window_addr + 1'b1; 
                     window_addr3                    <= window_addr3 + 1'b1;                                                                                                                               
                     {uncompressed_byte, window_data[8*window_addr3 +:8]} <= window_addr3 >= offset ? {2{window_data[8*MP3 +: 8]}} : {2{window[MP13][8*MP3 +: 8]}};                                                                                                                                                                                                                                                                   
                     if (!lz4_mode_64) begin                      
                       byte_valid                    <= 1'b1;
                       uncompressed_bytes            <= uncompressed_bytes + 32'd1;
                     end
                     if (window_addr3 == 7) begin                       
                       long_valid                                 <= 1'b1;
                       if (lz4_mode_64) uncompressed_bytes        <= uncompressed_bytes + 32'd8;  
                       {uncompressed_long, window[window_addr13]} <= {2{window_addr3 >= offset ? window_data[8*MP3 +: 8] : window[MP13][8*MP3 +: 8], window_data[00 +: 56]}};                                                                                                                                                                       
                       window_addr13                              <= window_addr13 + 1'b1;  
                     end
                     //end write_word                                        
                     if (lz4_mode_64 && ML > 8 && MP3 == 7 && window_addr13 > MP13 + 1) begin //64b mode using window buffer                      
                       state <= S_Copy_Matches_64;  
                     end else if (lz4_mode_64 && ML > 8 && window_addr3 == 7 && offset <= 8) begin //64b mode using last 8 bytes                      
                                state <= S_Copy_Matches_64_8;  
                              end else if (ML == 1) state <= S_Idle;                      
                   end       

                 S_Copy_Matches_64:
                   begin          
                     ML                 <= ML - 32'd8;                                                             
                     ML_W               <= ML_W + 32'd8;   
                     MP                 <= MP + 16'd8;  
                     MP13               <= MP13 + 1'b1;                                                         
                     //write_long                   
                     long_valid         <= 1'b1;
                     window_addr        <= window_addr + 16'd8; 
                     window_addr13      <= window_addr13 + 1'b1;
                     uncompressed_bytes <= uncompressed_bytes + 32'd8;
                     case (window_addr3)
                       0: begin 
                            window_data                                <= window[MP13];
                            {uncompressed_long, window[window_addr13]} <= {2{window[MP13]}};                             
                          end
                       1: begin 
                            window_data[00 +: 08]                      <= window[MP13][56 +: 08];  
                            {uncompressed_long, window[window_addr13]} <= {2{window[MP13][00 +: 56], window_data[00 +: 08]}};                                                      
                          end
                       2: begin      
                            window_data[00 +: 16]                      <= window[MP13][48 +: 16];  
                            {uncompressed_long, window[window_addr13]} <= {2{window[MP13][00 +: 48], window_data[00 +: 16]}};                               
                          end 
                       3: begin         
                            window_data[00 +: 24]                      <= window[MP13][40 +: 24];  
                            {uncompressed_long, window[window_addr13]} <= {2{window[MP13][00 +: 40], window_data[00 +: 24]}};    
                          end 
                       4: begin         
                            window_data[00 +: 32]                      <= window[MP13][32 +: 32];  
                            {uncompressed_long, window[window_addr13]} <= {2{window[MP13][00 +: 32], window_data[00 +: 32]}};
                          end 
                       5: begin         
                            window_data[00 +: 40]                      <= window[MP13][24 +: 40];  
                            {uncompressed_long, window[window_addr13]} <= {2{window[MP13][00 +: 24], window_data[00 +: 40]}};
                          end 
                       6: begin         
                            window_data[00 +: 48]                      <= window[MP13][16 +: 48];  
                            {uncompressed_long, window[window_addr13]} <= {2{window[MP13][00 +: 16], window_data[00 +: 48]}};
                          end 
                       7: begin         
                            window_data[00 +: 56]                      <= window[MP13][08 +: 56];  
                            {uncompressed_long, window[window_addr13]} <= {2{window[MP13][00 +: 08], window_data[00 +: 56]}};
                          end         
                     endcase 
                     //end write_long                                                                                
                     if (ML == 8) state  <= S_Idle;
                      else if (ML < 16) state  <= S_Copy_Matches;
                   end  

                 S_Copy_Matches_64_8:
                   begin          
                     ML                 <= ML - 32'd8;                                                             
                     ML_W               <= ML_W + 32'd8;   
                     MP                 <= MP + 16'd8;  
                     MP13               <= MP13 + 1'b1;                                                         
                     //write_long                  
                     long_valid         <= 1'b1;
                     window_addr        <= window_addr + 16'd8; 
                     window_addr13      <= window_addr13 + 1'b1;
                     uncompressed_bytes <= uncompressed_bytes + 32'd8;
                     case (offset)
                       1: begin    
                            window_data           <= {8{window_data[56 +: 08]}};                      
                            uncompressed_long     <= {8{window_data[56 +: 08]}};                              
                            window[window_addr13] <= {8{window_data[56 +: 08]}};                                               
                          end
                       2: begin    
                            window_data           <= {4{window_data[48 +: 16]}};                      
                            uncompressed_long     <= {4{window_data[48 +: 16]}};                              
                            window[window_addr13] <= {4{window_data[48 +: 16]}};                              
                          end
                       3: begin    
                            window_data           <= {window_data[40 +: 16], window_data[40 +: 24], window_data[40 +: 24]};                    
                            uncompressed_long     <= {window_data[40 +: 16], window_data[40 +: 24], window_data[40 +: 24]};                              
                            window[window_addr13] <= {window_data[40 +: 16], window_data[40 +: 24], window_data[40 +: 24]}; 
                          end
                       4: begin    
                            window_data           <= {2{window_data[32 +: 32]}};                      
                            uncompressed_long     <= {2{window_data[32 +: 32]}};                              
                            window[window_addr13] <= {2{window_data[32 +: 32]}};                              
                          end
                       5: begin    
                            window_data           <= {window_data[24 +: 24], window_data[24 +: 40]};                      
                            uncompressed_long     <= {window_data[24 +: 24], window_data[24 +: 40]};                              
                            window[window_addr13] <= {window_data[24 +: 24], window_data[24 +: 40]}; 
                          end
                       6: begin    
                            window_data           <= {window_data[16 +: 16], window_data[16 +: 48]};                      
                            uncompressed_long     <= {window_data[16 +: 16], window_data[16 +: 48]};                              
                            window[window_addr13] <= {window_data[16 +: 16], window_data[16 +: 48]};   
                          end
                       7: begin    
                            window_data           <= {window_data[08 +: 08], window_data[08 +: 56]};                      
                            uncompressed_long     <= {window_data[08 +: 08], window_data[08 +: 56]};                                                                           
                            window[window_addr13] <= {window_data[08 +: 08], window_data[08 +: 56]}; 
                          end
                       8: begin
                            uncompressed_long     <= window_data;                             
                            window[window_addr13] <= window_data;
                          end
                     endcase 
                     //end write_long                                                                                
                     if (ML == 8) state  <= S_Idle;
                      else if (ML < 16) state  <= S_Copy_Matches;
                   end  


                 default:
                    state <= S_Idle;
                         
         endcase          
       end          
end

wire read_ready;
wire read_ready_64;
wire blocks_readed;

assign read_ready = block_write_total > block_read_total;
assign read_ready_64 = block_write_total > block_read_total + 7;
assign blocks_readed = block_read_total >= lz4_compressed_bytes;
assign lz4_write_ready = (block_write_total - block_read_total) < BLOCKS_SIZE << 3; 
assign lz4_uncompressed_byte = uncompressed_byte;
assign lz4_byte_valid = byte_valid;
assign lz4_uncompressed_long = uncompressed_long;
assign lz4_long_valid = long_valid;
assign lz4_uncompressed_bytes = uncompressed_bytes;
assign lz4_paused = paused;
assign lz4_done = done;
assign lz4_error = error;
assign lz4_state = state;

/* DEBUG
assign lz4_gravats = block_write_total;
assign lz4_llegits = block_read_total;
assign lz4_read_ready = read_ready;
*/

endmodule
