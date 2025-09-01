`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/29/2025 09:36:33 AM
// Design Name: 
// Module Name: sh_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 스마트홈 제어 시스템 - 조도센서 커튼제어 + 사운드센서 LED제어
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments: ADC 기반 조도/사운드 센서를 이용한 자동화 시스템
// 
//////////////////////////////////////////////////////////////////////////////////

// 12비트 이진수를 4자리 BCD로 변환하는 모듈 (Binary to BCD 변환)
module bin_to_dec_16(
    input  [11:0] bin,   // 0~4095 범위의 12비트 이진 입력
    output reg [15:0] bcd // 4자리 BCD 출력 (각 4비트씩)
);
    integer i;
    reg [27:0] shift;    // 시프트 연산용 임시 레지스터

    always @(*) begin
        shift = {16'b0, bin}; // 상위 16비트는 0으로 초기화, 하위에 입력값 배치
        
        // Double Dabble 알고리즘: 12번 시프트하면서 BCD 변환
        for(i=0;i<12;i=i+1) begin
            // 각 BCD 자리가 5 이상이면 3을 더함 (BCD 보정)
            if(shift[15:12] >= 5) shift[15:12] = shift[15:12] + 3; // 1의 자리
            if(shift[19:16] >= 5) shift[19:16] = shift[19:16] + 3; // 10의 자리  
            if(shift[23:20] >= 5) shift[23:20] = shift[23:20] + 3; // 100의 자리
            if(shift[27:24] >= 5) shift[27:24] = shift[27:24] + 3; // 1000의 자리
            shift = shift << 1; // 1비트 왼쪽 시프트
        end
        bcd = shift[27:12]; // 최종 4자리 BCD 추출
    end
endmodule

// LED 밝기 제어용 PWM 생성 모듈
module pwm_led_Nstep(
    input clk, reset_p,
    input [31:0] duty,       // PWM 듀티 사이클 입력 (0~duty_step_N)
    output reg pwm);         // PWM 출력 신호

    // PWM 파라미터 설정
    parameter sys_clk_freq = 100_000_000; // 시스템 클럭 주파수 (100MHz)
    parameter pwm_freq = 1000;            // PWM 주파수 (1kHz)
    parameter duty_step_N= 256;           // PWM 분해능 (0~255 단계)
    parameter temp = sys_clk_freq / pwm_freq / duty_step_N / 2; // 분주비 계산

    // PWM 기준 클럭 생성을 위한 분주기
    integer cnt;
    reg pwm_freqX128;
    always @(posedge clk, posedge reset_p)begin
        if(reset_p)begin 
            cnt = 0;
            pwm_freqX128 = 0;
        end
        else begin
            if(cnt >= temp-1)begin 
                cnt = 0;
                pwm_freqX128 = ~pwm_freqX128; // 토글로 클럭 생성
            end
            else cnt = cnt + 1;
        end
   end

    // PWM 기준 클럭의 하강 에지 검출
    wire pwm_freqX128_nedge;
    edge_detector_p pwm_freaqX128_ed(
        .clk(clk), .reset_p(reset_p), .cp(pwm_freqX128),
        .n_edge(pwm_freqX128_nedge));

   // PWM 듀티 사이클 생성 로직
   integer cnt_duty;
   always @(posedge clk, posedge reset_p)begin 
       if(reset_p)begin 
           cnt_duty = 0;
           pwm = 0;
       end
       else if(pwm_freqX128_nedge)begin 
           if(cnt_duty >= duty_step_N) cnt_duty = 0; // 주기 완료 시 리셋
           else cnt_duty = cnt_duty + 1;
           
           // 듀티 사이클에 따른 PWM 출력 결정
           if(cnt_duty < duty) pwm = 1;  // HIGH 구간
           else pwm = 0;                 // LOW 구간
       end
   end
endmodule

// 조도센서 기반 자동 커튼 제어 모듈
module curtain_motor_top(
    input clk,              // 시스템 클럭 (100MHz)
    input reset_p,          // 비동기 리셋 신호
    input adc_y_signed,     // 조도센서 기반 커튼 제어 신호 (밝으면 1)
    output sg90             // SG90 서보모터 PWM 출력
);
    // 서보모터 위치 제어 변수
    integer step, cnt;      // step: 서보 각도값, cnt: 타이밍 카운터

    // 타이밍 생성용 메인 카운터
    always @(posedge clk or posedge reset_p) begin
        if(reset_p)
            cnt = 0;
        else
            cnt = cnt + 1;  // 매 클럭마다 증가
    end

    // cnt[19] 비트의 상승 에지 검출 (약 5.24ms 주기 생성)
    wire cnt_pedge;
    edge_detector_p echo_ed(
        .clk(clk), 
        .reset_p(reset_p), 
        .cp(cnt[19]),       // 19번째 비트를 주기 신호로 사용
        .p_edge(cnt_pedge)  // 상승 에지 감지
    );

    // 서보 회전 방향 제어 플래그
    reg inc_flag;

    // 조도에 따른 커튼 제어 로직
    always @(posedge clk or posedge reset_p) begin
        if(reset_p) begin
            step = 40;       // 서보 초기 위치 (커튼 열림)
            inc_flag = 1;    // 증가 방향 초기값
        end
        else if(cnt_pedge) begin // 약 5.24ms마다 실행
            if(adc_y_signed) begin  // 밝을 때: 커튼 닫기
                if(step < 170) begin
                    step = step + 1;  // 서보를 닫힘 방향으로 회전
                end
            end
            else begin              // 어두울 때: 커튼 열기
                if(step > 40) begin
                    step = step - 1;  // 서보를 열림 방향으로 회전
                end
            end
        end
    end

    // SG90 서보모터용 PWM 생성 모듈
    pwm_Nfreq_Nstep #(
        .pwm_freq(50),       // 서보모터 표준 50Hz PWM
        .duty_step_N(1440)   // PWM 분해능 설정
    ) pwm_sg90(
        .clk(clk), 
        .reset_p(reset_p), 
        .duty(step),         // 현재 서보 위치값
        .pwm(sg90)          // PWM 신호 출력
    );
endmodule

// 스마트홈 메인 제어 모듈 - ADC 센서 기반 자동화 시스템
module adc_sequence2_top(
    input clk,
    input reset_p,
    
    // XADC 차동 입력 인터페이스
    input vauxp6, vauxn6,       // 채널 6: 사운드 센서 (마이크)
    input vauxp14, vauxn14,     // 채널 14: 조도 센서 (포토레지스터)
    
    // 출력 인터페이스
    output servo_out,           // 커튼 서보모터 PWM
    output [7:0] seg_7,         // 7세그먼트 디스플레이
    output [3:0] com,           // 7세그먼트 공통 신호
    output led_g, led_b, led_r, // RGB LED 제어
    output [15:0] led           // 상태 표시 LED 배열
);

    // =================================================================
    // ======================= ADC 및 XADC 설정 ========================
    // =================================================================
    wire [4:0] channel_out;     // 현재 변환 중인 ADC 채널
    wire [15:0] do_out;         // ADC 변환 결과 (16비트)
    wire eoc_out;               // End of Conversion 신호

    // XADC IP 코어 인스턴스 (듀얼 채널 조이스틱용 설정)
    xadc_joystic joystick (
        .daddr_in({2'b00, channel_out}),    // 채널 주소
        .dclk_in(clk),                      // ADC 클럭
        .den_in(eoc_out),                   // 변환 시작 신호
        .reset_in(reset_p),                 // 리셋
        .vauxp6(vauxp6),                    // 채널 6 양극 (사운드)
        .vauxn6(vauxn6),                    // 채널 6 음극
        .vauxp14(vauxp14),                  // 채널 14 양극 (조도)
        .vauxn14(vauxn14),                  // 채널 14 음극
        .channel_out(channel_out),          // 현재 채널 출력
        .do_out(do_out),                    // 변환 데이터 출력
        .eoc_out(eoc_out)                   // 변환 완료 신호
    );
  
    // ADC 값 저장 레지스터
    reg [11:0] adc_value_x;     // 채널 6: 사운드 센서 값
    reg [11:0] adc_value_y;     // 채널 14: 조도 센서 값
    
    // ADC 변환 완료 에지 검출
    wire eoc_pedge;
    edge_detector_p eoc_ed(
        .clk(clk), 
        .reset_p(reset_p), 
        .cp(eoc_out),
        .p_edge(eoc_pedge)
    );
  
    // ADC 값 업데이트 로직 (변환 완료시마다)
    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            adc_value_x <= 0;
            adc_value_y <= 0;
        end else if (eoc_pedge) begin
            case(channel_out[3:0])
                6:  adc_value_x <= do_out[15:4];  // 채널 6: 사운드 (상위 12비트 사용)
                14: adc_value_y <= do_out[15:4];  // 채널 14: 조도 (상위 12비트 사용)
            endcase
        end
    end

    // =================================================================
    // ======================= 7세그먼트 조도 표시 =====================
    // =================================================================
    wire [15:0] y_bcd_16;   // 조도값의 BCD 변환 결과

    // 조도 센서 값을 BCD로 변환 (7세그먼트 표시용)
    bin_to_dec_16 bcd_y16(
        .bin(adc_value_y[11:0]),    // 12비트 조도값 입력
        .bcd(y_bcd_16)              // 4자리 BCD 출력
    );

    // 7세그먼트 디스플레이 제어 모듈
    fnd_cntr fnd(
        .clk(clk),
        .reset_p(reset_p),
        .fnd_value(y_bcd_16),       // 표시할 BCD 값
        .hex_bcd(1),                // BCD 모드 선택
        .seg_7(seg_7),              // 7세그먼트 세그먼트 신호
        .com(com)                   // 7세그먼트 공통 신호
    );
    
    // =================================================================
    // =================== 사운드 기반 LED PWM 제어 ===================
    // =================================================================
    wire pwm_g_signal;  // 사운드 레벨에 따른 초록 LED PWM 신호

    // 사운드 센서 값으로 LED 밝기 제어 (상위 8비트 사용)
    pwm_led_Nstep #(.duty_step_N(256)) pwm_led_g_inst(
        clk,
        reset_p,
        adc_value_x[11:4],          // 사운드 값의 상위 8비트를 듀티로 사용
        pwm_g_signal                // PWM 신호 출력
    );

    // =================================================================
    // ================ 박수 감지 및 2회 토글 LED 제어 ==================
    // =================================================================
    localparam SOUND_THRESHOLD = 12'd3000;        // 박수 감지 임계값
    localparam CLAP_WINDOW_CYCLES = 100_000_000;  // 1초 윈도우 (두 박수 간격)
    localparam COOLDOWN_CYCLES = 25_000_000;      // 0.25초 쿨다운 (중복 감지 방지)
    
    // 박수 감지 로직
    wire sound_is_loud;         // 현재 소리가 임계값 이상인지
    wire sound_p_edge;          // 소리 레벨 상승 에지
    assign sound_is_loud = (adc_value_x > SOUND_THRESHOLD);
    
    // 소리 레벨 상승 에지 검출 (박수 순간 감지)
    edge_detector_p sound_edge_detector (
        .clk(clk),
        .reset_p(reset_p),
        .cp(sound_is_loud),
        .p_edge(sound_p_edge)
    );
    
    // 박수 제어 상태 변수들
    reg led_state;              // LED 온/오프 상태
    reg [1:0] clap_cnt;         // 박수 카운트 (0~1)
    reg [31:0] clap_timer;      // 박수 윈도우 타이머
    reg [31:0] cooldown_timer;  // 쿨다운 타이머
    reg cooldown_active;        // 쿨다운 활성화 플래그
    
    // 박수 감지 및 LED 토글 제어 로직
    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            // 리셋 시 모든 상태 초기화
            clap_cnt <= 0;
            clap_timer <= 0;
            cooldown_timer <= 0;
            cooldown_active <= 0;
            led_state <= 0;
        end
        else begin
            // 박수 윈도우 타이머 관리 (1초 카운트다운)
            if (clap_timer > 0) begin
                clap_timer <= clap_timer - 1;
                if (clap_timer == 1) begin
                    clap_cnt <= 0;  // 윈도우 만료 시 박수 카운트 리셋
                end
            end
            
            // 쿨다운 타이머 관리 (중복 감지 방지)
            if (cooldown_timer > 0) begin
                cooldown_timer <= cooldown_timer - 1;
                if (cooldown_timer == 1) begin
                    cooldown_active <= 0;  // 쿨다운 해제
                end
            end
            
            // 박수 감지 및 처리 로직
            if (sound_p_edge && !cooldown_active) begin
                if (clap_cnt == 0) begin
                    // 첫 번째 박수: 윈도우 시작
                    clap_cnt <= 1;
                    clap_timer <= CLAP_WINDOW_CYCLES;
                end
                else if (clap_cnt == 1 && clap_timer > 0) begin
                    // 두 번째 박수 (1초 윈도우 내): LED 토글
                    led_state <= ~led_state;            // LED 상태 반전
                    clap_cnt <= 0;                      // 박수 카운트 리셋
                    clap_timer <= 0;                    // 윈도우 타이머 리셋
                    cooldown_timer <= COOLDOWN_CYCLES;  // 쿨다운 시작
                    cooldown_active <= 1;               // 쿨다운 활성화
                end
            end
        end
    end
    
    // RGB LED 출력 할당
    assign led_r = led_state;                    // 빨간 LED: 박수 토글 상태
    assign led_g = pwm_g_signal & led_state;     // 초록 LED: 사운드 레벨 PWM (토글 상태일 때만)
    assign led_b = 1'b0;                         // 파란 LED: 사용 안 함
    
    // 상태 표시 LED 할당
    assign led[0] = led_state;                   // 전체 LED 상태

    // =================================================================
    // ================== 조도 기반 커튼 자동 제어 =====================
    // =================================================================
    reg servo_on;   // 커튼 제어 신호 (밝으면 닫기, 어두우면 열기)
    
    // 조도 임계값 기반 커튼 제어 결정
    always @(posedge clk or posedge reset_p) begin
        if (reset_p)
            servo_on <= 0;
        else
            // 조도값이 2000 미만이면 어둡다고 판단 → 커튼 열기 (servo_on = 0)
            // 조도값이 2000 이상이면 밝다고 판단 → 커튼 닫기 (servo_on = 1)
            servo_on <= (adc_value_y < 12'd2000) ? 1'b0 : 1'b1;
    end

    // 커튼 서보모터 제어 모듈 인스턴스
    curtain_motor_top curtain_motor(
        .clk(clk), 
        .reset_p(reset_p), 
        .adc_y_signed(servo_on),    // 조도 기반 제어 신호
        .sg90(servo_out)            // 커튼 서보모터 PWM 출력
    );

endmodule