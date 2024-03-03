
module vga_pwm
(
	input         clk,
	input         pwm_en,
	input         csync_en,

	input         hsync,
	input         csync,

	input  [23:0] din,
	output [17:0] dout
);

reg [17:0] pwm_v;
reg [1:0]  vga_pwm;
always @(posedge clk) begin
 
 if (pwm_en) begin 
  	if (csync_en ? ~csync : ~hsync)
	  	vga_pwm <= vga_pwm + 1'd1; 
	  else
		  vga_pwm <= 2'd3;
	
  	if (vga_pwm < din[17:16] && din[23:18] < 6'b111111)
	  	pwm_v[17:12] <= din[23:18] + 1'd1;
	  else 	
		  pwm_v[17:12] <= din[23:18];
		
	  if (vga_pwm < din[9:8] && din[15:10] < 6'b111111)
	  	pwm_v[11:6] <= din[15:10] + 1'd1;
	  else 	
	  	pwm_v[11:6] <= din[15:10];
		
	  if (vga_pwm < din[1:0] && din[7:2] < 6'b111111)
	  	pwm_v[5:0] <= din[7:2] + 1'd1;
	  else 	
	  	pwm_v[5:0] <= din[7:2]; 
 end
 else begin
    pwm_v[17:12] <= din[23:18];
    pwm_v[11:6]  <= din[15:10];
    pwm_v[5:0]   <= din[7:2];
 end

end

assign dout = pwm_v;

endmodule
