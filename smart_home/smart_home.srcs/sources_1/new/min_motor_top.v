`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/27/2025 11:48:55 AM
// Design Name: 
// Module Name: min_motor_top
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


module door_motor_top(
    input clk,          // 시스템 클럭 입력 (예: 100MHz)
    input reset_p,      // 비동기 리셋 신호, 1로 들어오면 초기화
    input door_open,    // 문 열림 신호
    output sg90         // SG90 서보 모터 PWM 출력
);
    // step: 서보 위치를 나타내는 값
    // cnt: 펄스 생성용 카운터
    integer step, cnt;
    
    // 1클럭마다 cnt 증가 - reset 조건 추가
    always @(posedge clk or posedge reset_p) begin
        if(reset_p)
            cnt = 0;
        else
            cnt = cnt + 1;
    end
    
    // cnt[19]의 상승 에지 검출용
    wire cnt_pedge;
    edge_detector_p echo_ed(
        .clk(clk), 
        .reset_p(reset_p), 
        .cp(cnt[19]),     // cnt[19] 신호를 카운트 기준으로 사용
        .p_edge(cnt_pedge) // cnt[19] 상승 에지 발생 시 1
    );
    
    // inc_flag: step 증가/감소 방향 결정
    reg inc_flag;
    
    // step 값 업데이트
    always @(posedge clk or posedge reset_p) begin
        if(reset_p) begin
            step = 36;       // 초기 step 값 (서보 PWM 최소 위치)
            inc_flag = 1;    // 처음에는 증가 방향
        end
        else if(cnt_pedge) begin //  cnt[19] 상승 에지마다 실행
            if(door_open) begin
                if(step < 180) begin
                    step = step + 1;
                end
            end
            else begin
                if(step > 36) begin
                    step = step - 1;
                end
            end
        end
    end
    
    // PWM 생성 모듈 인스턴스
    pwm_Nfreq_Nstep #(
        .pwm_freq(50),       // SG90 서보 기준 PWM 주파수 50Hz
        .duty_step_N(1440)   // step 최대값 설정 (PWM 분해능)
    ) pwm_sg90(
        .clk(clk), 
        .reset_p(reset_p), 
        .duty(step), 
        .pwm(sg90)
    );    
endmodule
