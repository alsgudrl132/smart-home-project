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
module door_button_top(
    input clk, reset_p,
    input door_btn,
    output reg btn_signal);  
    
    // 버튼 상승 에지 검출을 위한 레지스터
    reg door_btn_prev;
    
    // 10초 타이머 (100MHz 클럭 기준: 10 * 100,000,000 = 1,000,000,000)
    reg [31:0] timer_counter;
    localparam TIMER_10SEC = 32'd1_000_000_000;  // 10초
    
    // 버튼 상승 에지 검출 (버튼이 눌린 순간)
    wire btn_pressed;
    assign btn_pressed = door_btn_prev && !door_btn;  // falling edge 검출
    
    always @(posedge clk, posedge reset_p) begin
        if(reset_p) begin
            btn_signal <= 0;
            door_btn_prev <= 1;  // 초기값은 1 (버튼이 안 눌린 상태)
            timer_counter <= 0;
        end
        else begin
            door_btn_prev <= door_btn;  // 이전 상태 저장
            
            // 버튼이 눌렸을 때
            if(btn_pressed) begin
                btn_signal <= 1;
                timer_counter <= 0;  // 타이머 리셋
            end
            // btn_signal이 1인 상태에서 타이머 동작
            else if(btn_signal) begin
                if(timer_counter < TIMER_10SEC) begin
                    timer_counter <= timer_counter + 1;
                end
                else begin
                    btn_signal <= 0;  // 10초 후 신호를 0으로
                    timer_counter <= 0;
                end
            end
        end
    end
endmodule

module door_motor_top(
    input clk,          // 시스템 클럭 입력 (예: 100MHz)
    input reset_p,      // 비동기 리셋 신호, 1로 들어오면 초기화
    input door_open,    // 문 열림 신호
    input door_btn,
    output btn_signal,  // 출력 포트
    output sg90         // SG90 서보 모터 PWM 출력
);
    // step: 서보 위치를 나타내는 값
    // cnt: 펄스 생성용 카운터
    integer step, cnt;
    
    // btn_signal을 내부 wire로 선언
    wire btn_signal_internal;
    assign btn_signal = btn_signal_internal;  // 출력 포트에 할당
    
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
    
    // door_button_top 인스턴스 - 내부 wire에 연결
    door_button_top door_button(
        .clk(clk), 
        .reset_p(reset_p), 
        .door_btn(door_btn), 
        .btn_signal(btn_signal_internal)  // 내부 wire에 연결
    );
    
    // inc_flag: step 증가/감소 방향 결정
    reg inc_flag;
    
    // step 값 업데이트 - 내부 wire 사용
    always @(posedge clk or posedge reset_p) begin
        if(reset_p) begin
            step = 36;       // 초기 step 값 (서보 PWM 최소 위치)
            inc_flag = 1;    // 처음에는 증가 방향
        end
        else if(cnt_pedge) begin //  cnt[19] 상승 에지마다 실행
            if(door_open || btn_signal_internal) begin  // 내부 wire 사용
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