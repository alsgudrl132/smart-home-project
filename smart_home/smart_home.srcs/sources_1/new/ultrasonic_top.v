`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/26/2025 02:09:08 PM
// Design Name: 
// Module Name: ultrasonic_top
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


module ultrasonic_top(
    input clk,
    input reset_p,
    input echo,
    output trig,
    output [7:0] seg_7,
    output [3:0] com,
    output [15:0] led
);
    wire is_occupied;
    wire [7:0] distance_cm;
    hc_sr04_cntr hcsr04(
        .clk(clk),
        .reset_p(reset_p),
        .echo(echo),
        .trig(trig),
        .distance_cm(distance_cm),
        .led(led),
        .is_occupied(is_occupied)
    );
    
    wire [15:0] distance_bcd;
    bin_to_dec bcd_ultra_sonic(
        .bin({4'b0000, distance_cm}),
        .bcd(distance_bcd)           
    );
    
    assign led[13] = is_occupied;
    
    fnd_cntr fnd(
        .clk(clk),
        .reset_p(reset_p),
        .fnd_value(distance_bcd), 
        .hex_bcd(1),
        .seg_7(seg_7),
        .com(com)
    );

endmodule