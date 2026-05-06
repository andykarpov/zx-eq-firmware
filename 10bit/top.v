// ------------------------------------------------------
// ZX-EQ Project 
// 
// Refactored by andykarpov 2026
// supports both common anode and common cathode led bars
// Warning: schematic pinout connected to totally different signals on real ZX BUS, see both schematics 
// ------------------------------------------------------
module top(
	input wire clk,
	input wire [2:0] cfg,
	input wire a15,
	input wire a14,
	input wire a1,
	input wire [7:0] d,
	input wire iorq_n,
	input wire wr_n,
	input wire m1_n,

	output wire [2:0] led_p0,
	output wire [9:0] led_c0,
	
	output wire [2:0] led_p1,
	output wire [9:0] led_c1, 

	output wire [2:0] led_p2,
	output wire [9:0] led_c2
);

localparam COMM_ANODE = 1;
localparam COMM_CATHODE = 2;

parameter COMM = COMM_CATHODE;

// decode AY ports
wire ssg = ~(a15 && ~(a1 || iorq_n));
wire bc1  = ~(ssg || ~(a14 && m1_n));
wire bdir = ~(ssg || wr_n);
wire wr_addr = bdir && bc1;
wire wr_data = bdir && ~bc1;

// mux counter
reg [16:0] scan_cnt; 
always @(posedge clk) begin
	scan_cnt <= scan_cnt + 1;
end
wire [1:0] current_col = scan_cnt[16:15]; 
wire scan_clk = scan_cnt == 17'b11111111111111111;

// AY reg address
reg [3:0] ay_addr;
always @(posedge clk)
	if (wr_addr)
		ay_addr <= d[3:0];
		
// AY channel freq and volumes
reg [4:0] freq_a, freq_b, freq_c;
reg [2:0] vol_a, vol_b, vol_c;
reg wr_stb, prev_wr_data;
always @(posedge clk) begin
	
	prev_wr_data <= wr_data;
	wr_stb <= 0;
	if (wr_data && ~prev_wr_data)
		wr_stb <= 1;

	if (wr_data) begin
		case (ay_addr)
			4'h0: freq_a[1:0] <= d[7:6]; 
			4'h2: freq_b[1:0] <= d[7:6];
			4'h4: freq_c[1:0] <= d[7:6];
			4'h1: freq_a[4:2] <= d[2:0] || {3{d[3]}};
			4'h3: freq_a[4:2] <= d[2:0] || {3{d[3]}};
			4'h5: freq_a[4:2] <= d[2:0] || {3{d[3]}};
			4'h8: vol_a[2:0] <= d[3:1];
			4'h9: vol_b[2:0] <= d[3:1];
			4'ha: vol_c[2:0] <= d[3:1];
		endcase
	end
end

// spread freq / vol to bars
wire [9:0] data_a1, data_a2, data_a3, data_b1, data_b2, data_b3, data_c1, data_c2, data_c3;
psg_data_mapper mapper_a(.clk(clk), .sclk(scan_clk), .f(freq_a), .v(vol_a), .wr(wr_stb), .data1(data_a1), .data2(data_a2), .data3(data_a3));
psg_data_mapper mapper_b(.clk(clk), .sclk(scan_clk), .f(freq_b), .v(vol_b), .wr(wr_stb), .data1(data_b1), .data2(data_b2), .data3(data_b3));
psg_data_mapper mapper_c(.clk(clk), .sclk(scan_clk), .f(freq_c), .v(vol_c), .wr(wr_stb), .data1(data_c1), .data2(data_c2), .data3(data_c3));

// drive led bars
led_driver3 #(.COMM(COMM)) led_driver_a(.clk(clk), .sel(current_col), .data1(data_a1), .data2(data_a2), .data3(data_a3), .led_col(led_p0), .led_row(led_c0));
led_driver3 #(.COMM(COMM)) led_driver_b(.clk(clk), .sel(current_col), .data1(data_b1), .data2(data_b2), .data3(data_b3), .led_col(led_p1), .led_row(led_c1));
led_driver3 #(.COMM(COMM)) led_driver_c(.clk(clk), .sel(current_col), .data1(data_c1), .data2(data_c2), .data3(data_c3), .led_col(led_p2), .led_row(led_c2));
 
endmodule

// map 3-bit level value to 10 bit led bar
module led_bar #(
    parameter WIDTH = 10
)(
    input wire [2:0] level,
    output wire [WIDTH-1:0] led_bar
);
    genvar i;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : led_gen
            assign led_bar[i] = (level > i);
        end
    endgenerate
endmodule

// fall off data (slow decrement) for the led bars
module fall_off (
    input wire clk,
	 input wire sclk,
	 input wire wr,
    input wire [2:0] in_level,
    output reg [2:0] out_level
);
    always @(posedge clk) begin
	  if (wr && (in_level > out_level)) begin
			out_level <= in_level; // immediate growing
	  end else if (sclk && (out_level > 0)) begin 
			 out_level <= out_level - 1'b1; // falling off to 0
	  end
    end
endmodule

// map incoming psg data (frequency and volume) to 3 led bars by 10 leds
module psg_data_mapper (
    input  wire       clk,
	 input  wire       sclk,
    input  wire [4:0] f,
    input  wire [2:0] v,
	 input  wire wr,
    output wire [9:0] data1,
    output wire [9:0] data2,
    output wire [9:0] data3
);
    wire [2:0] lev1 = (f < 5) ? v : 0;
    wire [2:0] lev2 = ((f >= 5) && (f < 10)) ? v : 0;
    wire [2:0] lev3 = (f >= 10) ? v : 0;

/*    wire [2:0] smoothed_lev1, smoothed_lev2, smoothed_lev3;

    fall_off f1 (.clk(clk), .sclk(sclk), .wr(wr), .in_level(lev1), .out_level(smoothed_lev1));
    fall_off f2 (.clk(clk), .sclk(sclk), .wr(wr), .in_level(lev2), .out_level(smoothed_lev2));
    fall_off f3 (.clk(clk), .sclk(sclk), .wr(wr), .in_level(lev3), .out_level(smoothed_lev3));

    led_bar #(.WIDTH(10)) led_bar1(.level(smoothed_lev1), .led_bar(data1));
    led_bar #(.WIDTH(10)) led_bar2(.level(smoothed_lev2), .led_bar(data2));
    led_bar #(.WIDTH(10)) led_bar3(.level(smoothed_lev3), .led_bar(data3));*/

    led_bar #(.WIDTH(10)) led_bar1(.level(lev1), .led_bar(data1));
    led_bar #(.WIDTH(10)) led_bar2(.level(lev2), .led_bar(data2));
    led_bar #(.WIDTH(10)) led_bar3(.level(lev3), .led_bar(data3));
	 
endmodule

// dynamic indication: drive 3 led bars by 10 leds
module led_driver3(
	input wire clk,
	input wire [1:0] sel,
	input wire [9:0] data1,
	input wire [9:0] data2,
	input wire [9:0] data3,
	output wire [2:0] led_col,
	output wire [9:0] led_row
);

	localparam COMM_ANODE = 1;
	localparam COMM_CATHODE = 2;
	parameter COMM = COMM_ANODE;

	// dynamic indication
	reg [2:0] col;
	reg [9:0] row;
	always @(posedge clk) begin
		case (sel)
			2'b00: begin
				col <= 3'b001;
				row <= ~data1[9:0];
			end
			2'b01: begin
				col <= 3'b010;
				row <= ~data2[9:0];
			end
			2'b10: begin
				col <= 3'b100;
				row <= ~data3[9:0];
			end
			2'b11: begin 
				col <= 3'b000;
				row <= 10'b00000000;
			end
		endcase
	end

	// drive led with common anode or common cathode
	assign led_col = (COMM == COMM_ANODE) ? col : ~col;
	assign led_row = (COMM == COMM_ANODE) ? row : ~row;

endmodule
