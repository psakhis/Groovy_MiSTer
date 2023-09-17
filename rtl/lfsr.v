
module lfsr(
   output [N-1:0] rnd
);

parameter N = 63;

lcell lc0(~(rnd[N - 1] ^ rnd[N - 3] ^ rnd[N - 4] ^ rnd[N - 6] ^ rnd[N - 10]), rnd[0]);
generate 
	genvar i;
	for (i = 0; i <= N - 2; i = i + 1) begin : lcn
		lcell lc(rnd[i], rnd[i + 1]);
	end
endgenerate

endmodule
