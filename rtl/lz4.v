`timescale 1ns / 1ps
module lz4 (
      input clk,
		input reset,
      input run,                          // continue flag
		input [31:0] compressed_bytes,      // bytes of compressed blocks (end condition)
		input [7:0] compressed_byte,        // compressed byte		
		input write_byte,                   // write compressed byte 
		input [63:0] compressed_long,       // compressed long
		input write_long,                   // write compressed long 	
		
	   output write_ready,                 // fifo is free
		output reg [7:0] uncompressed_byte, // decodified word		
		output reg data_valid = 0,          // indicates if uncompressed_byte is valid		
		output [31:0] uncompressed_bytes,   // current uncompressed bytes
		output reg lz4_done = 0,            // last state
      output reg lz4_error = 0		      // last state error flag
	);

parameter BLOCKS_SIZE = 16'd8192;

parameter S_Idle 	                = 4'b0000; 
parameter S_Read_Token            = 4'b0001; 
parameter S_Read_Literals_Length  = 4'b0010; 
parameter S_Read_Literals         = 4'b0011; 
parameter S_Read_Offset           = 4'b0100; 
parameter S_Read_Match_Offset     = 4'b0101; 
parameter S_Done                  = 4'b0110; 
parameter S_Read_Match_Length     = 4'b0111;
parameter S_Copy_Matches          = 4'b1000; 

reg [3:0]  state = S_Idle;
 
reg [7:0]  blocks[BLOCKS_SIZE];
reg [15:0] block_read_addr = 16'd0;
reg [15:0] block_write_addr = 16'd0;
reg [31:0] block_read_total = 32'd0;
reg [31:0] block_write_total = 32'd0;
reg [7:0]  data;

reg [7:0]  window[65535];          // Decoded window buffer
reg [15:0] window_addr = 16'd0;

reg [15:0] LL = 16'd0, ML = 16'd0; // Token: Literal length / Match length 
reg [15:0] MP = 16'd0;             // Match pointer from decoded buffer (window) to copy literals
reg [15:0] offset = 16'd0;         // Match Offset (little endian)
reg [31:0] words_decoded = 32'd0;

assign write_ready = (block_write_total - block_read_total) < BLOCKS_SIZE - 8; 
assign read_ready = block_write_total > block_read_total;
assign blocks_readed = block_read_total >= compressed_bytes;

assign uncompressed_bytes = words_decoded;


//write new compressed bytes
always @(posedge clk) begin       	
		 
       if (reset) begin
		   block_write_addr  <= 16'd0;
			block_write_total <= 32'd0;
       end			 		 
		 
		 if (write_byte && write_ready) begin					
			blocks[block_write_addr] <= compressed_byte;
			block_write_addr         <= block_write_addr + 1'b1;
			block_write_total        <= block_write_total + 1'b1;
		 end
		 
		 if (write_long && write_ready) begin	
		   blocks[block_write_addr + 0] <= compressed_long[00 +: 8]; 
		   blocks[block_write_addr + 1] <= compressed_long[08 +: 8]; 
		   blocks[block_write_addr + 2] <= compressed_long[16 +: 8]; 
		   blocks[block_write_addr + 3] <= compressed_long[24 +: 8]; 
		   blocks[block_write_addr + 4] <= compressed_long[32 +: 8]; 
		   blocks[block_write_addr + 5] <= compressed_long[40 +: 8]; 
		   blocks[block_write_addr + 6] <= compressed_long[48 +: 8]; 
		   blocks[block_write_addr + 7] <= compressed_long[56 +: 8]; 
         block_write_addr             <= block_write_addr + 16'd8;
			block_write_total            <= block_write_total + 32'd8;			
	    end		
end

//read bytes 
always @(posedge clk) begin

		if (reset) begin
		  state            <= S_Idle;
		  ML               <= 16'd0;
		  LL               <= 16'd0;			
		  MP               <= 16'd0;			
		  offset           <= 16'd0;								               
        window_addr      <= 16'd0;  
        words_decoded	 <= 16'd0;				
        block_read_addr  <= 16'd0;       		
		  block_read_total <= 32'd0;
		  data_valid       <= 1'b0;		  
		  lz4_done         <= 1'b0;
		  lz4_error        <= 1'b0;
		end	      		
		
		data_valid  <= 1'b0;	
		
		if (run) begin		      	  
										
		case (state)
			S_Idle: 
			  begin		 
             if (read_ready) begin             
				   state            <= S_Read_Token;
					data             <= blocks[block_read_addr];
			      block_read_addr  <= block_read_addr + 1'b1;		
					block_read_total <= block_read_total + 1'b1;
				 end          		
			  end 
			
			S_Read_Token: 
			  begin		
		       if (read_ready) begin	  
			      ML               <= data[3:0];  // Match length        
				   LL               <= data[7:4];  // Literal length				    
				   state            <= data[7:4] == 15 ? S_Read_Literals_Length : S_Read_Literals; // Literal length add bytes ?				 
				   data             <= blocks[block_read_addr];
			      block_read_addr  <= block_read_addr + 1'b1;	
				   block_read_total <= block_read_total + 1'b1;
 			    end					
		     end	
			  
			S_Read_Literals_Length: 			   
			  begin				
			    if (read_ready) begin
				   LL               <= LL + data;				 
				   state            <= data == 255 ? S_Read_Literals_Length : S_Read_Literals; // Literal length add bytes ?				 				
				   data             <= blocks[block_read_addr];
			      block_read_addr  <= block_read_addr + 1'b1;
				   block_read_total <= block_read_total + 1'b1; 
			    end
           end			
			
			S_Read_Literals: 
			  begin			
				 if (read_ready || blocks_readed) begin			 // Last Block miss match section              
				   if (LL == 0) begin                            // No more literals to copy				
				     offset[7:0] <= blocks_readed ? 8'd0 : data; 				  
				     state       <= S_Read_Offset;										
				   end else begin					
				     LL                  <= LL - 1'b1; 
					  window[window_addr] <= data;
					  window_addr         <= window_addr + 1'b1;  // Circular buffer					
					  data_valid          <= 1'b1;
					  uncompressed_byte   <= data;
					  words_decoded       <= words_decoded + 1'b1;
				   end	
               data             <= blocks[block_read_addr];
			      block_read_addr  <= block_read_addr + 1'b1;	
               block_read_total <= block_read_total + 1'b1; 				  
			    end					
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
				 else if (ML < 15) begin                                                                           // Prepared to copy, match length no has additional bytes
				   ML    <= ML + 16'd4;                                                                            // Add 4 bytes to match length (minium match length)	
					MP    <= offset > window_addr ? 1'd1 + 16'd65535 + window_addr - offset : window_addr - offset; // Set match pointer from decoded window buffer
				   state <= S_Copy_Matches;                                                                        // Copy literals match bytes 
				 end else begin                                                                                    // Add bytes to match length (ML == 15)
				   if (read_ready) begin
                 data             <= blocks[block_read_addr];
			        block_read_addr  <= block_read_addr + 1'b1;					
					  block_read_total <= block_read_total + 1'b1; 
			 		  state            <= S_Read_Match_Length;
               end									  													 
				 end	
			  end

			S_Done: 
			  begin
			    lz4_done  <= 1'b1;
				 lz4_error <= offset == 0 && ML == 0 && LL == 0 && blocks_readed ? 1'b0 : 1'b1;
			  end			
			
			S_Read_Match_Length: 
			  begin				 
			    if (data < 255) begin
				   ML    <= ML + data + 16'd4; 
					MP    <= offset > window_addr ? 1'd1 + 16'd65535 + window_addr - offset : window_addr - offset;
				   state <= S_Copy_Matches;      
				 end else begin                     // More match length (data = 255)				   
				   if (read_ready) begin
				     ML               <= ML + data;				  
                 data             <= blocks[block_read_addr];
			        block_read_addr  <= block_read_addr + 1'b1;
	              block_read_total <= block_read_total + 1'b1;				  
				   end 
				 end					 
			  end					
			  
			S_Copy_Matches:
			  begin
			    ML                  <= ML - 1'b1;
				 data_valid          <= 1'b1;
				 uncompressed_byte   <= window[MP]; 
				 window[window_addr] <= window[MP];
				 window_addr         <= window_addr + 1'b1; 		
				 MP                  <= MP + 1'b1; 
				 words_decoded       <= words_decoded + 1'b1;				
				 state               <= ML == 1 ? S_Idle : S_Copy_Matches;				
			  end									
			
			default:
				state <= S_Idle;
				
		endcase
	  
	  end
	  
	end
endmodule
