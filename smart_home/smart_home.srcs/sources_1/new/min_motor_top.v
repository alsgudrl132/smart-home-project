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

// 도어 버튼 제어 모듈 - 버튼 입력을 10초간 유지하는 기능
module door_button_top(
    input clk, reset_p,      // 시스템 클럭, 리셋 신호
    input door_btn,          // 도어 버튼 입력 (active low)
    output reg btn_signal);  // 10초간 유지되는 버튼 신호 출력
    
    // 버튼 상태 변화 감지를 위한 이전 상태 저장 레지스터
    reg door_btn_prev;
    
    // 10초 타이머 카운터 (100MHz 클럭 기준: 10초 = 1,000,000,000 클럭)
    reg [31:0] timer_counter;
    localparam TIMER_10SEC = 32'd1_000_000_000;  // 10초 상수 정의
    
    // 버튼 하강 에지 검출 (버튼이 눌린 순간 감지)
    wire btn_pressed;
    assign btn_pressed = door_btn_prev && !door_btn;  // 이전=1, 현재=0 일때 눌림
    
    always @(posedge clk, posedge reset_p) begin
        if(reset_p) begin
            // 리셋 시 초기화
            btn_signal <= 0;
            door_btn_prev <= 1;  // 버튼 초기상태는 1 (안 눌린 상태)
            timer_counter <= 0;
        end
        else begin
            door_btn_prev <= door_btn;  // 현재 버튼 상태를 이전 상태로 저장
            
            // 버튼이 눌렸을 때 처리
            if(btn_pressed) begin
                btn_signal <= 1;        // 출력 신호 활성화
                timer_counter <= 0;     // 타이머 초기화
            end
            // btn_signal이 활성화된 상태에서 10초 카운트
            else if(btn_signal) begin
                if(timer_counter < TIMER_10SEC) begin
                    timer_counter <= timer_counter + 1;  // 1클럭씩 증가
                end
                else begin
                    btn_signal <= 0;        // 10초 경과 후 신호 비활성화
                    timer_counter <= 0;     // 카운터 초기화
                end
            end
        end
    end
endmodule

// 도어 서보 모터 제어 메인 모듈
module door_motor_top(
    input clk,          // 시스템 클럭 입력 (100MHz)
    input reset_p,      // 비동기 리셋 신호 (active high)
    input door_open,    // 외부 문 열림 신호 (패스워드 시스템에서)
    input door_btn,     // 내부 문 열림 버튼
    output btn_signal,  // 버튼 신호 상태 출력
    output sg90         // SG90 서보 모터 PWM 제어 신호
);
    // 서보 모터 위치 제어 변수
    integer step, cnt;   // step: 서보 각도값, cnt: 타이밍 생성용 카운터
    
    // 버튼 신호를 내부에서 처리하기 위한 wire
    wire btn_signal_internal;
    assign btn_signal = btn_signal_internal;  // 내부 신호를 출력 포트에 연결
    
    // 메인 카운터 - 서보 모터 제어 타이밍 생성
    always @(posedge clk or posedge reset_p) begin
        if(reset_p)
            cnt = 0;
        else
            cnt = cnt + 1;  // 매 클럭마다 1씩 증가
    end
    
    // cnt[19] 비트의 상승 에지 검출 (약 5.24ms 주기)
    wire cnt_pedge;
    edge_detector_p echo_ed(
        .clk(clk), 
        .reset_p(reset_p), 
        .cp(cnt[19]),        // cnt의 19번째 비트를 주기 신호로 사용
        .p_edge(cnt_pedge)   // 상승 에지 발생시 1클럭 펄스 생성
    );
    
    // 도어 버튼 제어 모듈 인스턴스
    door_button_top door_button(
        .clk(clk), 
        .reset_p(reset_p), 
        .door_btn(door_btn),                    // 물리적 버튼 입력
        .btn_signal(btn_signal_internal)        // 10초 유지 신호 출력
    );
    
    // 서보 모터 회전 방향 제어 플래그 (현재 미사용)
    reg inc_flag;
    
    // 서보 모터 step 값 제어 로직
    always @(posedge clk or posedge reset_p) begin
        if(reset_p) begin
            step = 36;       // 서보 초기 위치 (0도 근처)
            inc_flag = 1;    // 증가 방향 초기값
        end
        else if(cnt_pedge) begin // 약 5.24ms마다 실행
            // 문을 열어야 하는 조건: 외부 신호 OR 내부 버튼 신호
            if(door_open || btn_signal_internal) begin  
                if(step < 180) begin
                    step = step + 1;  // 서보를 열림 방향으로 회전 (최대 180도)
                end
            end
            // 문을 닫아야 하는 조건: 두 신호 모두 비활성화
            else begin
                if(step > 36) begin
                    step = step - 1;  // 서보를 닫힘 방향으로 회전
                end
            end
        end
    end
    
    // SG90 서보모터용 PWM 생성 모듈
    pwm_Nfreq_Nstep #(
        .pwm_freq(50),       // 서보모터 표준 PWM 주파수 50Hz
        .duty_step_N(1440)   // PWM duty cycle 분해능 (0~1440)
    ) pwm_sg90(
        .clk(clk), 
        .reset_p(reset_p), 
        .duty(step),         // 현재 서보 위치값
        .pwm(sg90)          // PWM 신호 출력
    );    
endmodule