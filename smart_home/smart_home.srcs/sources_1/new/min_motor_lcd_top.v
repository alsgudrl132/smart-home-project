`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/27/2025 02:20:36 PM
// Design Name: 
// Module Name: min_motor_lcd_top
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


module min_motor_lcd_top(
    input clk, reset_p,        // 시스템 클럭, 리셋
    input [3:0] btn,           // 버튼 입력 (4개)
    input [3:0] row,           // 키패드 row
    output[3:0] column,        // 키패드 column
    output scl, sda,           // I2C 신호
    output [15:0] led,
    output sg90
    );
    wire door_open;
    lcd_top lcd(clk, reset_p, btn, row, column, scl, sda, led, door_open);
    door_motor_top door(clk, reset_p, door_open, sg90);    
    
endmodule
