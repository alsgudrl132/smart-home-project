`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 스마트 도어 시스템 메인 통합 모듈
// - DHT11 온도/습도 센서를 통한 환경 모니터링
// - 초음파 센서를 통한 사람 감지
// - 키패드 패스워드 인증 시스템
// - 서보모터 기반 도어 제어
// - ADC를 통한 아날로그 센서 입력 처리
// - 자동 환기 팬 제어 시스템
//////////////////////////////////////////////////////////////////////////////////

module main_top(
    input clk, reset_p,          // 메인 클럭(100MHz), 시스템 리셋
    input [3:0] btn,             // 4개 푸시 버튼 입력
    input [1:0] mode_sel,        // 2비트 모드 선택 스위치
    
    // 초음파 센서 인터페이스
    input echo,                  // 초음파 에코 신호 입력
    output trig,                 // 초음파 트리거 신호 출력
    
    // 키패드 인터페이스 (4x4 매트릭스)
    input [3:0] row,             // 키패드 행 입력
    output[3:0] column,          // 키패드 열 출력
    
    // ADC 인터페이스 (XADC 사용)
    input vauxp6, vauxn6,        // ADC 채널 6 차동 입력
    input vauxp14, vauxn14,      // ADC 채널 14 차동 입력
    
    // 도어 제어 관련
    input door_btn,              // 내부 도어 버튼 (수동 개방)
    output sg90,                 // 서보모터 PWM 제어 신호
    
    // ADC 제어 출력
    output servo_out,            // ADC 기반 서보 제어
    output led_b, led_r,         // 파란색/빨간색 상태 LED
    
    // I2C LCD 인터페이스 (2개 - 외부/내부)
    output scl, sda,             // 외부 LCD용 I2C (키패드 시스템)
    output inner_scl, inner_sda, // 내부 LCD용 I2C (환경 모니터링)
    
    // 7세그먼트 디스플레이 (거리 표시)
    output [7:0] seg_7,          // 7세그먼트 세그먼트 신호
    output [3:0] com,            // 7세그먼트 공통 신호
    
    // LED 상태 표시 및 환기팬 제어
    output [15:0] led,           // 16개 상태 표시 LED
    output reg motor_on,         // 환기팬 모터 제어 신호
    
    // DHT11 온습도 센서 (양방향 통신)
    inout dht11_data);           // DHT11 데이터 라인 (단선 통신)
    
    // 시스템 내부 상태 신호들
    wire is_hot,                 // 고온 감지 신호 (DHT11에서)
         is_occupied,            // 사람 감지 신호 (초음파에서)
         door_open,              // 도어 열림 신호 (패스워드 인증)
         btn_signal;             // 내부 버튼 신호 (10초 유지)
    
    // DHT11 온습도 센서 + LCD 디스플레이 모듈
    lcd_dht11_watch_top lcd_dht11(
        .clk(clk), 
        .reset_p(reset_p), 
        .btn(btn),               // 모드 전환 버튼
        .mode_sel(mode_sel),     // 표시 모드 선택
        .scl(inner_scl),         // 내부 LCD I2C 클럭
        .sda(inner_sda),         // 내부 LCD I2C 데이터
        .is_hot(is_hot),         // 고온 상태 출력 (환기팬 제어용)
        .dht11_data(dht11_data)  // DHT11 센서 데이터 라인
    );
    
    // 초음파 센서 + 7세그먼트 거리 표시 모듈
    ultrasonic_top ultra_inst(
        .clk(clk),
        .reset_p(reset_p), 
        .echo(echo),             // 초음파 에코 신호
        .trig(trig),             // 초음파 트리거 신호
        .seg_7(seg_7),           // 7세그먼트 출력
        .com(com),               // 7세그먼트 공통 신호
        .is_occupied(is_occupied) // 사람 감지 신호 출력 (환기팬 제어용)
    );
    
    // 키패드 패스워드 인증 + LCD 표시 모듈
    lcd_top lcd_inst(
        .clk(clk), 
        .reset_p(reset_p), 
        .btn(btn),               // 디버그용 버튼
        .row(row),               // 키패드 행 입력
        .column(column),         // 키패드 열 출력
        .scl(scl),               // 외부 LCD I2C 클럭
        .sda(sda),               // 외부 LCD I2C 데이터
        .door_open(door_open)    // 인증 성공 시 도어 열림 신호
    );
    
    // 서보모터 도어 제어 모듈
    door_motor_top door_inst(
        .clk(clk), 
        .reset_p(reset_p), 
        .door_open(door_open),   // 외부 인증 신호 (패스워드 성공)
        .door_btn(door_btn),     // 내부 수동 버튼
        .btn_signal(btn_signal), // 버튼 신호 상태 (디버그용)
        .sg90(sg90)              // SG90 서보모터 PWM 출력
    );
    
    // ADC 아날로그 센서 처리 모듈 (추가 센서 확장용)
    adc_sequence2_top adc_inst(
        .clk(clk), 
        .reset_p(reset_p), 
        .vauxp6(vauxp6),         // ADC 채널 6 양극
        .vauxn6(vauxn6),         // ADC 채널 6 음극
        .vauxp14(vauxp14),       // ADC 채널 14 양극
        .vauxn14(vauxn14),       // ADC 채널 14 음극
        .servo_out(servo_out),   // ADC 기반 서보 제어
        .led_b(led_b),           // 파란색 상태 LED
        .led_r(led_r)            // 빨간색 상태 LED
    );
    
    // 환기팬 제어를 위한 신호 안정화 및 타이밍 제어 레지스터
    reg [23:0] stable_counter;      // 신호 안정화 카운터 (24비트)
    reg [25:0] motor_off_counter;   // 모터 지연 정지 카운터 (26비트)
    reg motor_enable;               // 내부 모터 활성화 플래그
    
    // 시스템 상태 모니터링용 LED 할당
    assign led[10] = is_hot;                    // 고온 감지 상태
    assign led[11] = motor_on;                  // 환기팬 동작 상태
    assign led[9] = is_occupied;                // 사람 감지 상태
    assign led[8] = motor_enable;               // 모터 활성화 플래그
    assign led[7] = (stable_counter > 0);       // 안정화 카운터 동작 표시
    assign led[6] = (motor_off_counter > 0);    // 오프 타이머 동작 표시
    assign led[5] = (is_hot && is_occupied);    // 두 조건 AND 결과
    assign led[15:12] = stable_counter[23:20];  // 안정화 카운터 상위 4비트 표시
    
    // 환기팬 제어 타이밍 파라미터 (100MHz 클럭 기준)
    localparam STABLE_TIME = 24'd10_000_000;    // 0.1초 신호 안정화 시간
    localparam OFF_DELAY_TIME = 26'd50_000_000; // 0.5초 모터 지연 정지 시간
    
    // 자동 환기팬 제어 로직
    always @(posedge clk, posedge reset_p) begin
        if(reset_p) begin
            // 리셋 시 모든 제어 신호 초기화
            motor_on <= 0;
            motor_enable <= 0;
            stable_counter <= 0;
            motor_off_counter <= 0;
        end
        else begin
            // 환기팬 동작 조건: 고온 감지 AND 사람 감지
            if(is_hot && is_occupied) begin
                if(stable_counter < STABLE_TIME) begin
                    // 신호 안정화 대기 중 (0.1초)
                    stable_counter <= stable_counter + 1;
                    motor_off_counter <= 0; // 오프 타이머 리셋
                end
                else begin
                    // 안정화 완료 후 모터 활성화
                    motor_enable <= 1;
                end
            end
            // 환기팬 정지 조건: 고온 해제 OR 사람 없음
            else begin
                stable_counter <= 0; // 안정화 카운터 리셋
                if(motor_enable) begin
                    // 모터가 동작 중이면 지연 후 정지
                    if(motor_off_counter < OFF_DELAY_TIME) begin
                        motor_off_counter <= motor_off_counter + 1; // 0.5초 지연
                    end
                    else begin
                        motor_enable <= 0;      // 모터 비활성화
                        motor_off_counter <= 0; // 카운터 리셋
                    end
                end
                else begin
                    motor_off_counter <= 0; // 모터가 꺼져있으면 카운터 리셋
                end
            end
            
            // 최종 모터 제어 신호 출력 (1클럭 지연으로 안정화)
            motor_on <= motor_enable;
        end
    end
    
endmodule