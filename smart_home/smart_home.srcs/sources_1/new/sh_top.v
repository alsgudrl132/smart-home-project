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
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module bin_to_dec_16(
    input  [11:0] bin,   // 0~4095
    output reg [15:0] bcd // 4자리 BCD
);
    integer i;
    reg [27:0] shift;

    always @(*) begin
        shift = {16'b0, bin}; // 상위 16bit 초기화
        for(i=0;i<12;i=i+1) begin
            if(shift[15:12] >= 5) shift[15:12] = shift[15:12] + 3;
            if(shift[19:16] >= 5) shift[19:16] = shift[19:16] + 3;
            if(shift[23:20] >= 5) shift[23:20] = shift[23:20] + 3;
            if(shift[27:24] >= 5) shift[27:24] = shift[27:24] + 3;
            shift = shift << 1;
        end
        bcd = shift[27:12]; // 4자리 BCD
    end
endmodule

module pwm_led_Nstep(
    input clk, reset_p,
    input [31:0] duty, // Duty cycle input (0~duty_step_N)
    output reg pwm);

    // ---- Parameters ----
    parameter sys_clk_freq = 100_000_000; // System clock frequency
    parameter pwm_freq = 1000;          // PWM frequency
    parameter duty_step_N= 256;           // Number of duty steps
    parameter temp = sys_clk_freq / pwm_freq / duty_step_N / 2; // Divider

    // ---- Clock divider to generate PWM base clock ----
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
                pwm_freqX128 = ~pwm_freqX128;
            end
            else cnt = cnt + 1;
        end
   end

    // ---- Detect negative edge of PWM base clock ----
    wire pwm_freqX128_nedge;
    edge_detector_p pwm_freaqX128_ed(
        .clk(clk), .reset_p(reset_p), .cp(pwm_freqX128),
        .n_edge(pwm_freqX128_nedge));

   // ---- PWM counter and duty control ----
   integer cnt_duty;
   always @(posedge clk, posedge reset_p)begin 
       if(reset_p)begin 
           cnt_duty = 0;
           pwm = 0;
       end
       else if(pwm_freqX128_nedge)begin 
           if(cnt_duty >= duty_step_N) cnt_duty = 0;
           else cnt_duty = cnt_duty + 1;
           if(cnt_duty < duty) pwm = 1;
           else pwm = 0;
       end
   end
endmodule


module curtain_motor_top(
    input clk,          // 시스템 클럭 입력 (예: 100MHz)
    input reset_p,      // 비동기 리셋 신호, 1로 들어오면 초기화
    input adc_y_signed,    // 문 열림 신호
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
            step = 40;       // 초기 step 값 (서보 PWM 최소 위치)
            inc_flag = 1;    // 처음에는 증가 방향
        end
        else if(cnt_pedge) begin //  cnt[19] 상승 에지마다 실행
            if(adc_y_signed) begin
                if(step < 170) begin
                    step = step + 1;
                end
            end
            else begin
                if(step > 40) begin
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

module adc_sequence2_top(
    input clk,
    input reset_p,
    input vauxp6, vauxn6,
    input vauxp14, vauxn14,
    output servo_out,
    output [7:0] seg_7,
    output [3:0] com,
    output led_g, led_b, led_r,
    output [15:0] led
);

    // =================================================================
    // ======================= ADC 및 XADC 설정 ========================
    // =================================================================
    wire [4:0] channel_out;
    wire [15:0] do_out;
    wire eoc_out;

    xadc_joystic joystick (
        .daddr_in({2'b00, channel_out}),
        .dclk_in(clk),
        .den_in(eoc_out),
        .reset_in(reset_p),
        .vauxp6(vauxp6),
        .vauxn6(vauxn6),
        .vauxp14(vauxp14), 
        .vauxn14(vauxn14),
        .channel_out(channel_out),
        .do_out(do_out),
        .eoc_out(eoc_out)
    );
  
    reg [11:0] adc_value_x;     // 채널 6 (사운드)
    reg [11:0] adc_value_y;     // 채널 14 (조도)
    wire eoc_pedge;

    edge_detector_p eoc_ed(
        .clk(clk), 
        .reset_p(reset_p), 
        .cp(eoc_out),
        .p_edge(eoc_pedge)
    );
  
    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            adc_value_x <= 0;
            adc_value_y <= 0;
        end else if (eoc_pedge) begin
            case(channel_out[3:0])
                6:  adc_value_x <= do_out[15:4];  // 채널 6
                14: adc_value_y <= do_out[15:4]; // 채널 14 (조도)
            endcase
        end
    end

    // =================================================================
    // ======================= FND 및 PWM 설정 ========================
    // =================================================================
wire [15:0] y_bcd_16;

// 12비트 ADC → 최대 4095 → 4자리 BCD 필요
bin_to_dec_16 bcd_y16(
    .bin(adc_value_y[11:0]),
    .bcd(y_bcd_16)
);

fnd_cntr fnd(
    .clk(clk),
    .reset_p(reset_p),
    .fnd_value(y_bcd_16),  // ← 16비트 BCD를 그대로 넣음
    .hex_bcd(1),
    .seg_7(seg_7), 
    .com(com)
);
    wire pwm_g_signal;

    pwm_led_Nstep #(.duty_step_N(256)) pwm_led_g_inst(
        clk,
        reset_p,
        adc_value_x[11:4],
        pwm_g_signal
    );

    // ================================================================= 
// ====================== 사운드 감지 + 2회 토글 =================== 
// ================================================================= 
    localparam SOUND_THRESHOLD = 12'd3000;
    localparam CLAP_WINDOW_CYCLES = 100_000_000;  // 1초 윈도우
    localparam COOLDOWN_CYCLES = 25_000_000;      // 0.25초 쿨다운 (테스트용으로 단축)
    
    wire sound_is_loud;
    wire sound_p_edge;
    assign sound_is_loud = (adc_value_x > SOUND_THRESHOLD);
    
    edge_detector_p sound_edge_detector (
        .clk(clk),
        .reset_p(reset_p),
        .cp(sound_is_loud),
        .p_edge(sound_p_edge)
    );
    
    reg led_state;
    reg [1:0] clap_cnt;
    reg [31:0] clap_timer;
    reg [31:0] cooldown_timer;
    reg cooldown_active;
    
    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            clap_cnt <= 0;
            clap_timer <= 0;
            cooldown_timer <= 0;
            cooldown_active <= 0;
            led_state <= 0;
        end
        else begin
            // 박수 윈도우 타이머 관리
            if (clap_timer > 0) begin
                clap_timer <= clap_timer - 1;
                if (clap_timer == 1) begin
                    clap_cnt <= 0;  // 타임아웃 시 카운트 리셋
                end
            end
            
            // 쿨다운 타이머 관리
            if (cooldown_timer > 0) begin
                cooldown_timer <= cooldown_timer - 1;
                if (cooldown_timer == 1) begin
                    cooldown_active <= 0;
                end
            end
            
            // 박수 감지 및 처리
            if (sound_p_edge && !cooldown_active) begin
                if (clap_cnt == 0) begin
                    // 첫 번째 박수
                    clap_cnt <= 1;
                    clap_timer <= CLAP_WINDOW_CYCLES;
                end
                else if (clap_cnt == 1 && clap_timer > 0) begin
                    // 두 번째 박수 (윈도우 내에서)
                    led_state <= ~led_state;  // LED 상태 토글
                    clap_cnt <= 0;
                    clap_timer <= 0;
                    cooldown_timer <= COOLDOWN_CYCLES;
                    cooldown_active <= 1;
                end
            end
        end
    end
    
    // LED 출력 할당
    assign led_r = led_state;
    assign led_g = pwm_g_signal & led_state;
    assign led_b = 1'b0;
    
    // 모든 LED에 동일한 상태 할당 (또는 필요에 따라 조정)
    assign led[0] = led_state;

    // =================================================================
    // ====================== 서보 모터 제어 (조도 기반) =================
    // =================================================================
    reg servo_on;
    always @(posedge clk or posedge reset_p) begin
        if (reset_p)
            servo_on <= 0;
        else
            servo_on <= (adc_value_y < 12'd2000) ? 1'b1 : 1'b0;
    end


    curtain_motor_top curtain_motor(.clk(clk), .reset_p(reset_p), .adc_y_signed(servo_on), .sg90(servo_out));

endmodule
