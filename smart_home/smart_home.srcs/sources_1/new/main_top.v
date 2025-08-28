`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/26/2025 02:10:54 PM
// Design Name: 
// Module Name: main_top
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


module main_top(
    input clk, reset_p,  
    input [3:0] btn,     
    input [1:0] mode_sel,
    input echo,
    input [3:0] row,           
    output[3:0] column,        
    output scl, sda,
    output trig,
    output inner_scl, inner_sda,
    output [7:0] seg_7,
    output [3:0] com,     
    output [15:0] led,
    output reg motor_on,
    output sg90,
    inout dht11_data);
    
    wire is_hot, is_occupied, door_open;
    
    lcd_dht11_watch_top(.clk(clk), .reset_p(reset_p), .btn(btn), .mode_sel(mode_sel), .scl(inner_scl), .sda(inner_sda), .led(led), .is_hot(is_hot), .dht11_data(dht11_data));
    ultrasonic_top(clk, reset_p, echo, trig, seg_7, com, is_occupied);
    lcd_top lcd(clk, reset_p, btn, row, column, scl, sda, led, door_open);
    door_motor_top door(clk, reset_p, door_open, sg90);  
    
    // 신호 안정화를 위한 레지스터들
    reg [23:0] stable_counter;      // 더 긴 안정화 시간
    reg [23:0] motor_off_counter;   // 더 긴 오프 지연
    reg motor_enable;
    
    // 디버깅용 LED 할당
    assign led[10] = is_hot;      // 온도 상태 확인
    assign led[9] = is_occupied;  // 거리 상태 확인
    assign led[11] = motor_on;    // 모터 상태
    assign led[8] = motor_enable; // 내부 motor_enable 상태
    
    // 1초 약간 안정화를 위한 파라미터 (100MHz 기준)
    localparam STABLE_TIME = 24'd10_000_000;  // 0.1초
    localparam OFF_DELAY_TIME = 26'd50_000_000; // 0.5초
    
    always @(posedge clk, posedge reset_p) begin
        if(reset_p) begin
            motor_on <= 0;
            motor_enable <= 0;
            stable_counter <= 0;
            motor_off_counter <= 0;
        end
        else begin
            // 두 조건이 모두 만족될 때
            if(is_hot && is_occupied) begin
                if(stable_counter < STABLE_TIME) begin
                    stable_counter <= stable_counter + 1;
                    motor_off_counter <= 0;
                end
                else begin
                    motor_enable <= 1;
                end
            end
            // 조건이 만족되지 않을 때
            else begin
                stable_counter <= 0;
                if(motor_enable) begin
                    // 모터가 켜져 있다면 일정 시간 후 끄기
                    if(motor_off_counter < OFF_DELAY_TIME) begin
                        motor_off_counter <= motor_off_counter + 1;
                    end
                    else begin
                        motor_enable <= 0;
                        motor_off_counter <= 0;
                    end
                end
                else begin
                    motor_off_counter <= 0;
                end
            end
            
            motor_on <= motor_enable;
        end
    end
    
endmodule