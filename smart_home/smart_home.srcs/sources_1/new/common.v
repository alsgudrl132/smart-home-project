`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 08/11/2025 02:29:27 PM
// Design Name:
// Module Name: controller (with several utility modules)
// Project Name:
// Target Devices:
// Tool Versions:
// Description:
//   여러 유틸리티 및 센서 제어 모듈들을 한 파일에 모아둔 소스입니다.
//   - edge_detector_p: 신호의 상승/하강 엣지 검출
//   - fnd_cntr: 7-seg FND 제어 (BCD/HEX 선택 포함)
//   - debounce / btn_cntr: 버튼 디바운스 및 엣지 카운터
//   - dht11_cntr: DHT11 센서 읽기 FSM (데이터 수신, 체크섬 포함)
//   - hc_sr04_cntr: HC-SR04 초음파 거리 측정 제어 FSM
//   - keypad_cntr: 4x4 키패드 스캔 FSM
//   - I2C_master: 간단한 I2C 마스터(쓰기 중심) FSM
//   - i2c_lcd_send_byte: I2C로 4비트 LCD에 1바이트 전송
//   - pwm_led_128step / pwm_Nfreq_Nstep: PWM 생성기
//
////////////////////////////////////////////////////////////////////////////////////

// ===========================================================
// edge_detector_p
// - 2-FF 동기화 후 상승/하강 엣지를 출력하는 모듈
// - 입력 신호(cp)가 비동기일 수 있으므로 먼저 2단 플리핑하여 동기화 함
// Ports:
//   clk      : 동기 클럭
//   reset_p  : active-high 리셋
//   cp       : 감시할 신호 (비동기 입력 가능)
//   p_edge   : cp의 상승 엣지 펄스 (1클럭 너비)
//   n_edge   : cp의 하강 엣지 펄스 (1클럭 너비)
// ===========================================================

module seg_decoder (
    input [3:0] digit_in,
    output reg [7:0] seg_out
);
    always @(*) begin
        case (digit_in)
                             //pgfe_dcba
            4'd0: seg_out = 8'b1100_0000;   // 0 (dp 꺼짐)
            4'd1: seg_out = 8'b1111_1001; // 1
            4'd2: seg_out = 8'b1010_0100; // 2
            4'd3: seg_out = 8'b1011_0000; // 3
            4'd4: seg_out = 8'b1001_1001; // 4
            4'd5: seg_out = 8'b1001_0010; // 5
            4'd6: seg_out = 8'b1000_0010; // 6
            4'd7: seg_out = 8'b1111_1000; // 7
            4'd8: seg_out = 8'b1000_0000; // 8
            4'd9: seg_out = 8'b1001_0000; // 9
            4'hA: seg_out = 8'b1000_1000; // A
            4'hb: seg_out = 8'b0000_0011; // b
            4'hC: seg_out = 8'b1100_0110; // C
            4'hd: seg_out = 8'b1010_0001; // D
            4'hE: seg_out = 8'b1000_0110; // E
            4'hF: seg_out = 8'b1000_1110; // F
            default: seg_out = 8'b1111_1111;
        endcase
    end
endmodule

module clock_div_100 (
    input clk, reset_p,                 // 입력: 시스템 클럭, 리셋
    output reg clk_div_100,             // 출력: 1/100 분주된 클럭
    output nedge_div_100, pedge_div_100 // 출력: 분주된 클럭의 상승/하강 엣지 펄스
    );

    reg [5:0] cnt_sysclk; // 6비트 카운터 (최대 63까지 카운트 가능)

    always @(posedge clk, posedge reset_p) begin
        if (reset_p) begin
            cnt_sysclk = 0;       // 리셋 시 카운터 초기화
            clk_div_100 = 0;      // 분주 클럭도 0으로 초기화
        end
        else begin
            if (cnt_sysclk >= 49) begin
                cnt_sysclk = 0;             // 50번 카운트 되면 초기화
                clk_div_100 = ~clk_div_100; // 분주 클럭 토글 (0→1, 1→0)
            end
            else begin
                cnt_sysclk = cnt_sysclk + 1; // 카운터 증가
            end
        end
    end

    // 엣지 디텍터 인스턴스: 분주된 클럭(clk_div_100)의 상승/하강을 감지
    edge_detector_p clk_ed (
        .clk(clk), 
        .reset_p(reset_p),
        .cp(clk_div_100), 
        .p_edge(pedge_div_100), 
        .n_edge(nedge_div_100)
    );
endmodule

module anode_selector (
    input [1:0] scan_count,
    output reg [3:0] an_out
);
    always @(*) begin
        case (scan_count)
            2'd0: an_out = 4'b1110; // an[0]
            2'd1: an_out = 4'b1101; // an[1]
            2'd2: an_out = 4'b1011; // an[2]
            2'd3: an_out = 4'b0111; // an[3]
            default: an_out = 4'b1111;
        endcase
    end
endmodule


module bin_to_dec(
    input [11:0] bin,           // 12비트 이진 입력
    output reg [15:0] bcd       // 4자리의 BCD를 출력 (4비트 x 4자리)
    );

    integer i;      // 반복문

    always @(bin) begin

        bcd = 0;    // initial value

        for(i = 0; i < 12; i = i + 1) begin
            // 1) 알고리즘 각 단위비트 자리별로 5이상이면 +3 해줌
            if(bcd[3:0] >= 5) bcd[3:0] = bcd[3:0] + 3;          // 1의 자리수
            if(bcd[7:4] >= 5) bcd[7:4] = bcd[7:4] + 3;          // 10의 자리수
            if(bcd[11:8] >= 5) bcd[11:8] = bcd[11:8] + 3;       // 100의 자리수
            if(bcd[15:12] >= 5) bcd[15:12] = bcd[15:12] +3;     // 1000의 자리수

            // 2) 1비트 left shift + 새로운 비트 붙임
            bcd = {bcd[14:0], bin[11 - i]};
        end

    end
endmodule

module edge_detector_p(
    input clk,
    input reset_p,
    input cp,

    output p_edge,
    output n_edge

    );

    reg ff_cur, ff_old;

    always @(posedge clk or posedge reset_p) begin
        if(reset_p) begin
            ff_cur <= 0;
            ff_old <= 0;
        end else begin
            ff_old <= ff_cur;
            ff_cur <= cp;
        end
    end

    // ff_old, ff_cur 조합으로 엣지 판별
    assign p_edge = ({ff_cur, ff_old} == 2'b10) ? 1'b1 : 1'b0;
    assign n_edge = ({ff_cur, ff_old} == 2'b01) ? 1'b1 : 1'b0;
endmodule


// ===========================================================
// fnd_cntr
// - 4자리 FND(7-seg) 드라이브를 위한 컨트롤러
// - 입력으로 16비트 값(fnd_value)을 받아 BCD 변환 또는 HEX 직접 출력 선택 가능
// Ports:
//   clk, reset_p : 클럭/리셋
//   fnd_value    : 표시할 16비트 값 (hex_bcd=1이면 hex로, 0이면 BCD 변환된 값 사용)
//   hex_bcd      : 1=HEX, 0=BCD
//   seg_7        : 7-seg 출력 (8비트: dp 포함)
//   com          : 애노드(또는 캐소드) 선택 (4비트 스캔 라인)
// Note:
//   내부에서 bin_to_dec, anode_selector, seg_decoder를 사용함.
// ===========================================================
module fnd_cntr(
    input clk, reset_p,
    input [15:0] fnd_value,
    input hex_bcd,
    output [7:0] seg_7,
    output [3:0] com);
    
    wire [15:0] bcd_value;
    bin_to_dec bcd(.bin(fnd_value[11:0]), .bcd(bcd_value));
    
    reg [16:0] clk_div;
    always @(posedge clk)clk_div = clk_div + 1;
    
    anode_selector ring_com(
        .scan_count(clk_div[16:15]), .an_out(com));
    reg [3:0] digit_value; 
    wire [15:0] out_value;
    assign out_value = hex_bcd ? fnd_value : bcd_value;   
    always @(posedge clk or posedge reset_p)begin
        if(reset_p)begin
            digit_value = 0;
        end
        else begin
            case(com)
                4'b1110 : digit_value = out_value[3:0];
                4'b1101 : digit_value = out_value[7:4];
                4'b1011 : digit_value = out_value[11:8];
                4'b0111 : digit_value = out_value[15:12];
            endcase
        end
    end
    seg_decoder dec(.digit_in(digit_value), .seg_out(seg_7));
endmodule


// ===========================================================
// debounce
// - 버튼 입력을 동기화하고 흔들림(debounce)을 제거하여 안정된 btn_out 생성
// - 내부적으로 2-FF 동기화 및 카운터로 안정상태 유지 시 업데이트
// Ports:
//   clk     : 시스템 클럭
//   btn_in  : 원시 버튼 입력(비동기 가능)
//   btn_out : 디바운스 후 신호 (동기화된 출력)
// ===========================================================
module debounce (
    input clk,
    input btn_in,
    output reg btn_out
);

    reg [15:0] count;
    reg btn_sync_0, btn_sync_1;
    wire stable = (count == 16'hFFFF);

    // 2-stage synchronizer
    always @(posedge clk) begin
        btn_sync_0 <= btn_in;
        btn_sync_1 <= btn_sync_0;
    end

    // stable 판정 후 btn_out 업데이트
    always @(posedge clk) begin
        if(btn_sync_1 == btn_out) begin
            count <= 0;
        end else begin
            count <= count + 1;
            if(stable)
                btn_out <= btn_sync_1;
        end
    end

endmodule


// ===========================================================
// btn_cntr
// - debounce 모듈을 사용해 버튼을 안정화하고 엣지 펄스 출력
// Ports:
//   clk, reset_p : 클럭, 리셋
//   btn          : 원시 버튼 입력
//   btn_pedge    : 버튼의 상승 엣지 펄스
//   btn_nedge    : 버튼의 하강 엣지 펄스
// ===========================================================
module btn_cntr(
    input clk, reset_p,
    input btn,
    output btn_pedge, btn_nedge);
    wire debounced_btn;
    debounce btn_0(.clk(clk), .btn_in(btn), .btn_out(debounced_btn));
    
    edge_detector_p btn_ed(
        .clk(clk), .reset_p(reset_p), .cp(debounced_btn),
        .p_edge(btn_pedge), .n_edge(btn_nedge));

endmodule


// ===========================================================
// dht11_cntr
// - DHT11 센서와의 1-wire 인터페이스를 구현한 FSM
// - Start (MCU Low 18ms) -> DHT 응답(80us low/high) -> 40bit 데이터 수신
// - 체크섬 검증 후 humidity, temperature에 저장
// Ports:
//   clk, reset_p : 시스템 클럭, 리셋
//   dht11_data   : DHT11 데이터 핀 (inout - 양방향)
//   humidity     : 수신된 습도(정수부)
//   temperature  : 수신된 온도(정수부)
//   led          : 디버깅 LED(상태/카운트 등 표시)
// Notes:
//   - 내부에 clock_div_100 (1us 단위 펄스 생성) 및 edge_detector_p 필요
//   - dht11_data는 tri-state 방식(assign ... 'bz)로 제어됨
// ===========================================================
module dht11_cntr(
    input clk, reset_p,          // 시스템 클럭, 리셋
    inout dht11_data,            // DHT11 데이터 핀 (양방향)
    output reg [7:0] humidity,   // 습도 값
    output reg [7:0] temperature,// 온도 값
    output [15:0] led,           // 디버깅용 LED 출력
    output reg is_hot
);

    //===================================================
    // 상태 정의 (FSM)
    //===================================================
    localparam S_IDLE       = 6'b00_0001;  // 대기 상태
    localparam S_LOW_18MS   = 6'b00_0010;  // MCU → DHT11 Start 신호 (18ms Low)
    localparam S_HIGH_20US  = 6'b00_0100;  // MCU → High 유지 (20us)
    localparam S_LOW_80US   = 6'b00_1000;  // DHT11 응답 Low (80us)
    localparam S_HIGH_80US  = 6'b01_0000;  // DHT11 응답 High (80us)
    localparam S_READ_DATA  = 6'b10_0000;  // 데이터 읽기 상태

    // 데이터 읽기 서브 상태
    localparam S_WAIT_PEDGE = 2'b01;       // 상승 엣지 대기
    localparam S_WAIT_NEDGE = 2'b10;       // 하강 엣지 대기
    
    //===================================================
    // 마이크로초(us) 단위 타이밍 카운터
    //===================================================
    wire clk_usec_nedge;
    clock_div_100 us_clk(
        .clk(clk), 
        .reset_p(reset_p),
        .nedge_div_100(clk_usec_nedge)     // 1us 단위 네거티브 엣지 펄스
    );
    
    reg [21:0] count_usec; // 마이크로초 카운터
    reg count_usec_e;      // 카운터 enable

    always @(negedge clk, posedge reset_p) begin
        if(reset_p)
            count_usec = 0;  // 리셋 시 카운터 초기화
        else if(clk_usec_nedge && count_usec_e)
            count_usec = count_usec + 1;  // enable 상태에서 카운트 증가
        else if(!count_usec_e)
            count_usec = 0;  // enable=0이면 카운터 초기화
    end
    
    //===================================================
    // DHT11 데이터 핀 엣지 검출
    //===================================================
    wire dht_nedge, dht_pedge;
    edge_detector_p dht_ed(
        .clk(clk), 
        .reset_p(reset_p), 
        .cp(dht11_data),
        .p_edge(dht_pedge),  // 상승 엣지
        .n_edge(dht_nedge)   // 하강 엣지
    );
        
    reg dht11_buffer;        // 출력 버퍼
    reg dht11_data_out_e;    // 출력 enable
    assign dht11_data = dht11_data_out_e ? dht11_buffer : 'bz; // 삼상 버퍼
    
    //===================================================
    // FSM 상태 변수
    //===================================================
    reg [5:0] state, next_state;
    assign led[5:0] = state; // 현재 상태를 LED로 표시
    reg [1:0] read_state;
    
    always @(negedge clk, posedge reset_p) begin
        if(reset_p) 
            state = S_IDLE;
        else 
            state = next_state;
    end
    
    //===================================================
    // 데이터 수신
    //===================================================
    reg [39:0] temp_data;   // 수신 데이터 버퍼 (40bit)
    reg [5:0] data_count;   // 수신된 비트 수
    assign led[11:6] = data_count;
    
    always @(posedge clk, posedge reset_p) begin
        if(reset_p) begin
            next_state = S_IDLE;
            temp_data = 0;
            data_count = 0;
            dht11_data_out_e = 0;
            read_state = S_WAIT_PEDGE;
            is_hot = 0;
        end
        else begin
            case(state)
                //---------------------------------------------------
                // 초기 대기 상태 (약 3초)
                //---------------------------------------------------
                S_IDLE: begin
                    if(count_usec < 22'd3_000_000) begin // 3초 대기
                        count_usec_e = 1;
                        dht11_data_out_e = 0;
                    end
                    else begin
                        count_usec_e = 0;
                        next_state = S_LOW_18MS;
                    end
                end
                
                //---------------------------------------------------
                // MCU → Start 신호 (18ms Low)
                //---------------------------------------------------
                S_LOW_18MS: begin
                    if(count_usec < 22'd18_000) begin
                        count_usec_e = 1;
                        dht11_data_out_e = 1;
                        dht11_buffer = 0;
                    end
                    else begin
                        count_usec_e = 0;
                        next_state = S_HIGH_20US;
                        dht11_data_out_e = 0;
                    end
                end
                
                //---------------------------------------------------
                // MCU → High 유지 (20us)
                //---------------------------------------------------
                S_HIGH_20US: begin
                    count_usec_e = 1;
                    if(count_usec > 22'd100_100) begin
                        count_usec_e = 0;
                        next_state = S_IDLE;
                    end
                    if(dht_nedge) begin
                        next_state = S_LOW_80US;
                        count_usec_e = 0;
                    end
                end
                
                //---------------------------------------------------
                // DHT11 응답 Low (80us)
                //---------------------------------------------------
                S_LOW_80US: begin
                    count_usec_e = 1;
                    if(count_usec > 22'd100_100) begin
                        count_usec_e = 0;
                        next_state = S_IDLE;
                    end
                    if(dht_pedge) begin
                        next_state = S_HIGH_80US;
                        count_usec_e = 0;
                    end
                end
                
                //---------------------------------------------------
                // DHT11 응답 High (80us)
                //---------------------------------------------------
                S_HIGH_80US: begin
                    count_usec_e = 1;
                    if(count_usec > 22'd100_100) begin
                        count_usec_e = 0;
                        next_state = S_IDLE;
                    end
                    if(dht_nedge) begin
                        next_state = S_READ_DATA;
                        count_usec_e = 0;
                    end
                end
                
                //---------------------------------------------------
                // DHT11 데이터 수신 (40bit)
                //---------------------------------------------------
                S_READ_DATA: begin
                    case(read_state)
                        // 상승 엣지 대기
                        S_WAIT_PEDGE: begin
                            if(dht_pedge) 
                                read_state = S_WAIT_NEDGE;
                            count_usec_e = 0;
                        end
                        // 하강 엣지 대기
                        S_WAIT_NEDGE: begin
                            if(dht_nedge) begin
                                read_state = S_WAIT_PEDGE;
                                data_count = data_count + 1;
                                // '0' or '1' 판별 (펄스 폭 기준)
                                if(count_usec < 50) 
                                    temp_data = {temp_data[38:0], 1'b0};
                                else 
                                    temp_data = {temp_data[38:0], 1'b1};
                            end
                            else begin
                                count_usec_e = 1;
                                if(count_usec > 22'd100_000) begin
                                    count_usec_e = 0;
                                    next_state = S_IDLE;
                                    data_count = 0;
                                    read_state = S_WAIT_PEDGE;
                                end
                            end
                        end
                    endcase
                    // 데이터 40bit 수신 완료
                    if(data_count >= 40) begin
                        next_state = S_IDLE;
                        data_count = 0;
                        if(temp_data[39:32] + temp_data[31:24] + temp_data[23:16] + temp_data[15:8] == temp_data[7:0]) begin
                            humidity = temp_data[39:32];
                            temperature = temp_data[23:16];
                            if(temperature >= 25) is_hot = 1;
                            else is_hot = 0;
                        end
                    end
                end
                default: 
                    next_state = S_IDLE;
            endcase
        end
    end
endmodule


// ===========================================================
// hc_sr04_cntr
// - HC-SR04 초음파 센서 제어 FSM (Trig 송신 -> Echo 받아 거리 계산)
// - 내부에서 1us 타이머(clock_div_100)와 엣지 검출기를 사용
// Ports:
//   clk, reset_p : 클럭/리셋
//   echo         : Echo 입력 (상태 감시)
//   trig         : Trig 출력 (마이크로초 단위로 pulse 생성)
//   distance_cm  : 측정된 거리(cm) (디버깅/표시 용도)
//   led          : 디버깅 LED (상태/입력 표시)
// ===========================================================
module hc_sr04_cntr(
    input clk,
    input reset_p,
    input echo,                  
    output reg trig,             
    output reg [7:0] distance_cm,
    output [15:0] led,           
    output reg is_occupied
);
    // FSM 상태 정의
    localparam S_IDLE   = 4'b0001; 
    localparam S_SEND   = 4'b0010; 
    localparam S_RECIVE = 4'b0100; 
    localparam S_END    = 4'b1000; 
    
    // 1us 단위 클럭 생성
    wire clk_usec_pedge;
    clock_div_100 us_clk(
        .clk(clk),
        .reset_p(reset_p),
        .nedge_div_100(clk_usec_pedge)
    );
    
    reg [21:0] count_usec, start_usec, div_usec_58;    
    reg count_usec_e, div_usec_e;         
    
    // 마이크로초 카운터
    always @(negedge clk or posedge reset_p) begin
        if(reset_p) count_usec <= 0;
        else if(clk_usec_pedge && count_usec_e) count_usec <= count_usec + 1;
        else if(!count_usec_e) count_usec <= 0;
    end
    
    reg[7:0] distance_cnt;
    always @(negedge clk or posedge reset_p) begin
        if(reset_p) begin
            div_usec_58 = 0;
            distance_cnt = 0;
        end
        else if(clk_usec_pedge && div_usec_e) begin
            if(div_usec_58 >= 57) begin
                div_usec_58 = 0;
                distance_cnt = distance_cnt + 1;
            end
            else div_usec_58 = div_usec_58 + 1;
        end
        else if(!count_usec_e) begin
            div_usec_58 <= 0;
            distance_cnt = 0;
        end
    end
    
    wire echo_nedge, echo_pedge;
    edge_detector_p echo_ed(
        .clk(clk), 
        .reset_p(reset_p), 
        .cp(echo),
        .p_edge(echo_pedge),  
        .n_edge(echo_nedge)   
    );
    
    // FSM 상태 레지스터
    reg [3:0] state, next_state;
    reg [21:0] echo_width;    
    
    assign led[3:0] = state;  
    assign led[15] = echo;    
    assign led[14] = trig;    
    
    // 상태 전이
    always @(negedge clk or posedge reset_p) begin
        if(reset_p) state <= S_IDLE;
        else state <= next_state;
    end
    
    // FSM 동작
    always @(posedge clk or posedge reset_p) begin
        if(reset_p) begin
            next_state <= S_IDLE;
            trig <= 0;
            count_usec_e <= 0;
            distance_cm <= 0;
            is_occupied <= 0;
        end
        else begin
            case(state)
                S_IDLE: begin
                    trig <= 0;
                    count_usec_e <= 1;
                    if(count_usec > 22'd60_000) begin   
                        count_usec_e <= 0;
                        next_state <= S_SEND;
                    end
                end
                S_SEND: begin
                    trig <= 1;
                    count_usec_e <= 1;
                    if(count_usec > 22'd10) begin       
                        trig <= 0;
                        count_usec_e <= 0;
                        next_state <= S_RECIVE;
                    end
                end
                S_RECIVE: begin
                    count_usec_e <= 1;
                    if(count_usec > 22'd100_000) begin  
                        next_state <= S_IDLE;
                    end
                    if(echo_pedge) begin
                        div_usec_e = 1;
                    end
                    else if(echo_nedge) begin
                        distance_cm = distance_cnt;
                        div_usec_e = 0;
                        next_state <= S_END;
                    end 
                end
                S_END: begin
                    // 거리 기준 점유 상태 업데이트를 S_END에서 수행
                    if(distance_cm < 7) is_occupied <= 1;
                    else is_occupied <= 0;
                    next_state <= S_IDLE;
                end
                default: next_state <= S_IDLE;
            endcase
        end
    end
endmodule


// ===========================================================
// keypad_cntr
// - 4x4 매트릭스 키패드 스캔 컨트롤러
// - 각 column을 순차적으로 활성화하고 row를 읽어 눌린 키를 판별
// Ports:
//   clk, reset_p : 클럭/리셋
//   row          : 외부에서 읽어온 row 상태 (4비트)
//   column       : 외부로 출력하는 column (4비트, 하나만 low/active인 형태로 출력)
//   key_value    : 눌린 키의 값(0~F)
//   key_valid    : 키가 유효할 때 1
// Notes:
//   - 10ms 분주를 내부 카운터로 생성하여 스캔 타이밍을 맞춤
// ===========================================================
module keypad_cntr(
    input clk, reset_p,
    input [3:0] row,            // Keypad row 입력 (4개)
    output reg [3:0] column,    // Keypad column 출력 (4개)
    output reg [3:0] key_value, // 눌린 키 값 (0~F)
    output reg key_valid        // 키 입력 유효 신호
);

    // FSM 상태 정의
    localparam [4:0]SCAN_0       = 5'b00001;
    localparam [4:0]SCAN_1       = 5'b00010;
    localparam [4:0]SCAN_2       = 5'b00100;
    localparam [4:0]SCAN_3       = 5'b01000;
    localparam [4:0]KEY_PROCESS  = 5'b10000;
    
    // 약 10ms 분주 카운터
    reg [19:0] clk_10ms;  
    always @(posedge clk) 
        clk_10ms = clk_10ms + 1;
    
    // 10ms 신호 edge 검출기
    wire clk_10ms_nedge, clk_10ms_pedge;
    edge_detector_p ms_10_ed(
        .clk(clk), 
        .reset_p(reset_p), 
        .cp(clk_10ms[19]),
        .p_edge(clk_10ms_pedge),  // 상승엣지
        .n_edge(clk_10ms_nedge)   // 하강엣지
    );
    
    // FSM 상태 레지스터
    reg [4:0] state, next_state;
    always @(posedge clk, posedge reset_p) begin
        if(reset_p) 
            state = SCAN_0;
        else if(clk_10ms_pedge) 
            state = next_state;
    end
    
    // FSM 상태 전이(next_state)
    always @* begin
        case(state)
            SCAN_0      : next_state = (row == 0) ? SCAN_1 : KEY_PROCESS;
            SCAN_1      : next_state = (row == 0) ? SCAN_2 : KEY_PROCESS;
            SCAN_2      : next_state = (row == 0) ? SCAN_3 : KEY_PROCESS;
            SCAN_3      : next_state = (row == 0) ? SCAN_0 : KEY_PROCESS;
            KEY_PROCESS : next_state = (row == 0) ? SCAN_0 : KEY_PROCESS;
            default     : next_state = SCAN_1;
        endcase
    end
    
    // FSM 출력 및 키 값 처리
    always @(posedge clk, posedge reset_p) begin
        if(reset_p) begin
            column    = 4'b0001; // 첫 번째 column 활성화
            key_value = 0;
            key_valid = 0;
        end
        else if(clk_10ms_nedge) begin
            case(state)
                SCAN_0: begin
                    column    = 4'b0001;
                    key_valid = 0;
                end
                SCAN_1: begin
                    column    = 4'b0010;
                    key_valid = 0;
                end
                SCAN_2: begin
                    column    = 4'b0100;
                    key_valid = 0;
                end
                SCAN_3: begin
                    column    = 4'b1000;
                    key_valid = 0;
                end
                KEY_PROCESS: begin   
                    key_valid = 1; // 키가 눌린 경우
                    case({column, row}) // 눌린 key mapping
                        8'b0001_0001 : key_value = 4'hC; // C clear
                        8'b0001_0010 : key_value = 4'h0; // 0
                        8'b0001_0100 : key_value = 4'hF; // F =
                        8'b0001_1000 : key_value = 4'hd; // d /
                        8'b0010_0001 : key_value = 4'h1; // 1
                        8'b0010_0010 : key_value = 4'h2; // 2
                        8'b0010_0100 : key_value = 4'h3; // 3
                        8'b0010_1000 : key_value = 4'hE; // E *
                        8'b0100_0001 : key_value = 4'h4; // 4 
                        8'b0100_0010 : key_value = 4'h5; // 5
                        8'b0100_0100 : key_value = 4'h6; // 6
                        8'b0100_1000 : key_value = 4'hb; // b -
                        8'b1000_0001 : key_value = 4'h7; // 7
                        8'b1000_0010 : key_value = 4'h8; // 8
                        8'b1000_0100 : key_value = 4'h9; // 9
                        8'b1000_1000 : key_value = 4'hA; // A +
                    endcase
                end                   
            endcase
        end
    end
    
endmodule

module keypad_door_cntr(
    input clk, reset_p,
    input [3:0] row,            // Keypad row 입력 (4개)
    output reg [3:0] column,    // Keypad column 출력 (4개)
    output reg [3:0] key_value, // 눌린 키 값 (0~F)
    output reg key_valid        // 키 입력 유효 신호
);

    // FSM 상태 정의
    localparam [4:0]SCAN_0       = 5'b00001;
    localparam [4:0]SCAN_1       = 5'b00010;
    localparam [4:0]SCAN_2       = 5'b00100;
    localparam [4:0]SCAN_3       = 5'b01000;
    localparam [4:0]KEY_PROCESS  = 5'b10000;
    
    // 약 10ms 분주 카운터
    reg [19:0] clk_10ms;  
    always @(posedge clk) 
        clk_10ms = clk_10ms + 1;
    
    // 10ms 신호 edge 검출기
    wire clk_10ms_nedge, clk_10ms_pedge;
    edge_detector_p ms_10_ed(
        .clk(clk), 
        .reset_p(reset_p), 
        .cp(clk_10ms[19]),
        .p_edge(clk_10ms_pedge),  // 상승엣지
        .n_edge(clk_10ms_nedge)   // 하강엣지
    );
    
    // FSM 상태 레지스터
    reg [4:0] state, next_state;
    always @(posedge clk, posedge reset_p) begin
        if(reset_p) 
            state = SCAN_0;
        else if(clk_10ms_pedge) 
            state = next_state;
    end
    
    // FSM 상태 전이(next_state)
    always @* begin
        case(state)
            SCAN_0      : next_state = (row == 0) ? SCAN_1 : KEY_PROCESS;
            SCAN_1      : next_state = (row == 0) ? SCAN_2 : KEY_PROCESS;
            SCAN_2      : next_state = (row == 0) ? SCAN_3 : KEY_PROCESS;
            SCAN_3      : next_state = (row == 0) ? SCAN_0 : KEY_PROCESS;
            KEY_PROCESS : next_state = (row == 0) ? SCAN_0 : KEY_PROCESS;
            default     : next_state = SCAN_1;
        endcase
    end
    
    // FSM 출력 및 키 값 처리
    always @(posedge clk, posedge reset_p) begin
        if(reset_p) begin
            column    = 4'b0001; // 첫 번째 column 활성화
            key_value = 0;
            key_valid = 0;
        end
        else if(clk_10ms_nedge) begin
            case(state)
                SCAN_0: begin
                    column    = 4'b0001;
                    key_valid = 0;
                end
                SCAN_1: begin
                    column    = 4'b0010;
                    key_valid = 0;
                end
                SCAN_2: begin
                    column    = 4'b0100;
                    key_valid = 0;
                end
                SCAN_3: begin
                    column    = 4'b1000;
                    key_valid = 0;
                end
                KEY_PROCESS: begin   
                    key_valid = 1; // 키가 눌린 경우
                    case({column, row}) // 눌린 key mapping
                        8'b0001_0001 : key_value = 4'hC; // C
                        8'b0001_0010 : key_value = 4'hC; // C
                        8'b0001_0100 : key_value = 4'h0; // C
                        8'b0001_1000 : key_value = 4'hA; // C
                        8'b0010_0001 : key_value = 4'hC; // 3
                        8'b0010_0010 : key_value = 4'h9; // 6
                        8'b0010_0100 : key_value = 4'h8; // 9
                        8'b0010_1000 : key_value = 4'h7; // B
                        8'b0100_0001 : key_value = 4'hC; // 2
                        8'b0100_0010 : key_value = 4'h6; // 5
                        8'b0100_0100 : key_value = 4'h5; // 8
                        8'b0100_1000 : key_value = 4'h4; // 0
                        8'b1000_0001 : key_value = 4'hC; // 1
                        8'b1000_0010 : key_value = 4'h3; // 4
                        8'b1000_0100 : key_value = 4'h2; // 7
                        8'b1000_1000 : key_value = 4'h1; // A
                    endcase
                end                   
            endcase
        end
    end
    
endmodule


// ===========================================================
// I2C_master
// - 단순 I2C 마스터 (쓰기 중심) FSM
// - START, 주소+R/W 전송, 데이터 전송, STOP 시퀀스 구현
// Ports:
//   clk, reset_p : 클럭/리셋
//   addr         : 7-bit I2C 주소
//   data         : 8-bit 전송 데이터
//   rd_wr        : R/W 비트 (0=write, 1=read) - 본 구현은 쓰기 중심
//   comm_start   : 통신 시작 신호 (positive edge로 동작 시작)
//   scl, sda     : I2C 선 (현재 output reg로 선언되어 있음 - 실제 open-drain 구현 주의 필요)
//   led          : 디버깅용 LED
// Notes:
//   - 실제 하드웨어에서는 SDA를 open-drain(inout)으로 처리해야 함.
//   - 내부에 clock_div_100, edge_detector_p 사용.
// ===========================================================
module I2C_master(
    input clk, reset_p,
    input [6:0] addr,        // 7비트 슬레이브 주소
    input [7:0] data,        // 전송할 8비트 데이터
    input rd_wr, comm_start, // rd_wr: 0=쓰기, 1=읽기 / comm_start: 통신 시작 신호
    output reg scl, sda,     // I2C 클럭(SCL)과 데이터(SDA) 라인
    output [15:0] led);
    
    // FSM 상태 정의 (One-hot encoding 사용)
    localparam IDLE         = 7'b000_0001;  // 대기 상태
    localparam COMM_START   = 7'b000_0010;  // START 컨디션 생성
    localparam SEND_ADDR    = 7'b000_0100;  // 주소+R/W 비트 전송
    localparam RD_ACK       = 7'b000_1000;  // ACK 신호 읽기
    localparam SEND_DATA    = 7'b001_0000;  // 데이터 전송
    localparam SCL_STOP     = 7'b010_0000;  // STOP 컨디션 준비
    localparam COMM_STOP    = 7'b100_0000;  // STOP 컨디션 완료
    
    // 1μs 단위 클럭 생성 (100MHz → 1MHz)
    wire clk_usec_nedge;
    clock_div_100 us_clk(
        .clk(clk), 
        .reset_p(reset_p),
        .nedge_div_100(clk_usec_nedge));
    
    // comm_start 신호의 positive edge 검출
    wire comm_start_pedge;
    edge_detector_p comm_start_ed(
        .clk(clk), 
        .reset_p(reset_p), 
        .cp(comm_start),
        .p_edge(comm_start_pedge));
        
    // SCL 신호의 edge 검출 (데이터 변경/읽기 타이밍용)
    wire scl_nedge, scl_pedge;
    edge_detector_p scl_ed(
        .clk(clk), 
        .reset_p(reset_p), 
        .cp(scl),
        .p_edge(scl_pedge),
        .n_edge(scl_nedge));
    
    // SCL 클럭 생성 (100kHz = 10μs 주기 = 5μs HIGH + 5μs LOW)
    reg [2:0] count_usec5;  // 5μs 카운터
    reg scl_e;              // SCL 클럭 enable 신호
    always @(posedge clk, posedge reset_p) begin
        if(reset_p) begin
            count_usec5 = 0;
            scl = 0;        // 리셋시 SCL은 LOW
        end
        else if(scl_e) begin                    // SCL 클럭이 enable되면
            if(clk_usec_nedge) begin            // 1μs마다
                if(count_usec5 >= 4) begin      // 5μs 카운트 완료시
                    count_usec5 = 0;
                    scl = ~scl;                 // SCL 토글 (HIGH↔LOW)
                end
                else count_usec5 = count_usec5 + 1;
            end
        end
        else if(!scl_e) begin      // SCL disable시
            count_usec5 = 0;
            scl = 1;               // SCL을 HIGH로 유지 (I2C idle 상태)
        end
    end
    
    // FSM 상태 레지스터 (negedge에서 상태 전환)
    reg[6:0] state, next_state;
    always @(negedge clk, posedge reset_p) begin
        if(reset_p) state = IDLE;
        else state = next_state;
    end
    
    // 주소와 R/W 비트를 합친 8비트 (I2C 표준: 7bit주소 + 1bit R/W)
    wire [7:0] addr_rd_wr;
    assign addr_rd_wr = {addr, rd_wr};
    
    reg [2:0] cnt_bit;    // 비트 카운터 (7→0으로 카운트)
    reg stop_flag;        // STOP 조건 플래그
    
    // FSM 메인 로직
    always @(posedge clk, posedge reset_p) begin
        if(reset_p) begin
            next_state = IDLE;
            scl_e = 0;
            sda = 1;              // I2C idle시 SDA는 HIGH
            cnt_bit = 7;          // MSB부터 전송하므로 7부터 시작
            stop_flag = 0;
        end
        else begin
            case(state)
                IDLE      : begin
                    scl_e = 0;                      // SCL 클럭 정지
                    sda = 1;                        // SDA HIGH (idle 상태)
                    if(comm_start_pedge) next_state = COMM_START;  // 통신 시작 신호 감지
                end
                
                COMM_START: begin
                    sda = 0;                        // START 조건: SCL=HIGH일 때 SDA를 HIGH→LOW
                    scl_e = 1;                      // SCL 클럭 시작
                    next_state = SEND_ADDR;
                end
                
                SEND_ADDR : begin
                    // SCL negedge에서 데이터 변경 (I2C 표준)
                    if(scl_nedge) sda = addr_rd_wr[cnt_bit];
                    // SCL pedge에서 비트 카운트 (슬레이브가 이 시점에서 데이터 읽음)
                    if(scl_pedge) begin
                        if(cnt_bit == 0) begin      // 8비트 모두 전송 완료
                            cnt_bit = 7;            // 카운터 리셋
                            next_state = RD_ACK;    // ACK 대기 상태로
                        end
                        else cnt_bit = cnt_bit - 1;  // 다음 비트로
                    end
                end
                
                RD_ACK    : begin
                    if(scl_nedge) sda = 'bz;        // SDA를 Hi-Z로 (슬레이브가 ACK 보냄)
                    else if(scl_pedge) begin
                        if(stop_flag) begin         // 데이터 전송도 완료된 경우
                            stop_flag = 0;
                            next_state = SCL_STOP;  // STOP 조건으로
                        end
                        else begin                  // 주소 전송 완료, 데이터 전송 시작
                            stop_flag = 1;          // 다음 ACK에서 STOP하도록 플래그 설정
                            next_state = SEND_DATA;
                        end
                    end
                end
                
                SEND_DATA : begin
                    // 데이터 전송 (주소 전송과 동일한 방식)
                    if(scl_nedge) sda = data[cnt_bit];
                    if(scl_pedge) begin
                        if(cnt_bit == 0) begin
                            cnt_bit = 7;
                            next_state = RD_ACK;    // 데이터 전송 후 다시 ACK 확인
                        end
                        else cnt_bit = cnt_bit - 1;
                    end
                end
                
                SCL_STOP  : begin
                    if(scl_nedge) sda = 0;          // STOP 조건 준비: SDA를 LOW로
                    if(scl_pedge) next_state = COMM_STOP;  // SCL이 HIGH가 되면 STOP 조건 실행
                end
                
                COMM_STOP : begin
                    // STOP 조건: SCL=HIGH일 때 SDA를 LOW→HIGH
                    if(count_usec5 >= 3) begin      // 약간의 지연 후
                        scl_e = 0;                  // SCL 클럭 정지
                        sda = 1;                    // STOP 조건: SDA HIGH
                        next_state = IDLE;          // 다시 대기 상태로
                    end
                end
            endcase
        end
    end
endmodule


// ===========================================================
// i2c_lcd_send_byte
// - I2C를 통해 HD44780 스타일 LCD(4-bit 모드)로 1바이트를 전송하는 FSM
// - 상위 니블 -> EN=1 -> 하위 니블 -> EN=1 형태로 전송
// Ports:
//   clk, reset_p : 클럭/리셋
//   addr         : LCD I2C 주소
//   send_buffer  : 전송할 8비트 데이터
//   send         : 전송 시작 신호 (positive edge 감지)
//   rs           : 0=명령어, 1=데이터(RS 신호)
//   scl, sda     : I2C 선 (I2C_master 인스턴스에 연결)
//   busy         : 전송 중 플래그
//   led          : 디버깅용 LED
// Notes:
//   - 내부에서 I2C_master를 인스턴스화하여 실제 전송 수행
// ===========================================================
module i2c_lcd_send_byte(
    input clk, reset_p,
    input [6:0] addr,           // LCD의 I2C 주소
    input [7:0] send_buffer,    // 전송할 데이터
    input send, rs,             // send: 전송 시작, rs: 0=명령어, 1=데이터
    output scl, sda,            // I2C 신호선
    output reg busy,            // 전송 중 표시
    output [15:0] led);

    // LCD 4비트 모드 전송 상태 (상위 4비트 → 하위 4비트 순서)
    localparam IDLE                     = 6'b00_0001;  // 대기
    localparam SEND_HIGH_NIBBLE_DISABLE = 6'b00_0010;  // 상위 4비트, E=0
    localparam SEND_HIGH_NIBBLE_ENABLE  = 6'b00_0100;  // 상위 4비트, E=1
    localparam SEND_LOW_NIBBLE_DISABLE  = 6'b00_1000;  // 하위 4비트, E=0
    localparam SEND_LOW_NIBBLE_ENABLE   = 6'b01_0000;  // 하위 4비트, E=1
    localparam SEND_DISABLE             = 6'b10_0000;  // 전송 완료, E=0
    
    // 1μs 클럭 생성
    wire clk_usec_nedge;
    clock_div_100 us_clk(
        .clk(clk), 
        .reset_p(reset_p),
        .nedge_div_100(clk_usec_nedge));

    reg [7:0] data;        // I2C로 전송할 실제 데이터
    reg comm_start;        // I2C 통신 시작 신호
    
    // send 신호의 positive edge 검출
    wire send_pedge;
    edge_detector_p send_ed(
        .clk(clk), 
        .reset_p(reset_p), 
        .cp(send),
        .p_edge(send_pedge));
        
    // 타이밍 제어용 카운터 (각 단계마다 200μs 대기)
    reg [21:0] count_usec;
    reg count_usec_e;

    always @(negedge clk, posedge reset_p) begin
        if(reset_p) count_usec = 0;
        else if(clk_usec_nedge && count_usec_e) count_usec = count_usec + 1;  
        else if(!count_usec_e) count_usec = 0;  
    end
    
    // I2C 마스터 모듈 인스턴스 (항상 쓰기 모드: rd_wr=0)
    I2C_master master(clk, reset_p, addr, data, 1'b0, comm_start, scl, sda);
    
    // FSM 상태 관리
    reg [5:0] state, next_state;
    always @(negedge clk, posedge reset_p) begin
        if(reset_p) begin
            state = IDLE;
        end
        else begin
            state = next_state;
        end
    end
    
    always @(posedge clk, posedge reset_p) begin
        if(reset_p) begin
            next_state = IDLE;
            comm_start = 0;
            count_usec_e = 0;
            data = 0;
            busy = 0;
        end
        else begin
            case(state)
                IDLE                       : begin
                    if(send_pedge) begin            // 전송 시작 신호 감지
                        next_state = SEND_HIGH_NIBBLE_DISABLE;
                        busy = 1;                   // 전송 중 표시
                    end
                end
                
                // 상위 4비트 전송, Enable = 0
                SEND_HIGH_NIBBLE_DISABLE   : begin
                    if(count_usec <= 22'd200) begin      // 200μs 동안
                        // LCD 데이터 포맷: [D7 D6 D5 D4] [BL EN RW RS]
                        // BL=1(백라이트 켜짐), EN=0(disable), RW=0(쓰기), RS=입력값
                        data = {send_buffer[7:4], 3'b100, rs}; 
                        comm_start = 1;             // I2C 전송 시작
                        count_usec_e = 1;           // 타이머 시작
                    end
                    else begin
                        next_state = SEND_HIGH_NIBBLE_ENABLE;
                        count_usec_e = 0;           // 타이머 리셋
                        comm_start = 0;             // I2C 전송 정지
                    end
                end
                
                // 상위 4비트 전송, Enable = 1 (LCD가 데이터를 실제로 읽는 순간)
                SEND_HIGH_NIBBLE_ENABLE    : begin
                    if(count_usec <= 22'd200) begin
                        // EN=1로 변경 (LCD Enable 신호)
                        data = {send_buffer[7:4], 3'b110, rs}; 
                        comm_start = 1;
                        count_usec_e = 1;
                    end
                    else begin
                        next_state = SEND_LOW_NIBBLE_DISABLE;
                        count_usec_e = 0;
                        comm_start = 0;
                    end
                end
                
                // 하위 4비트 전송, Enable = 0
                SEND_LOW_NIBBLE_DISABLE    : begin
                    if(count_usec <= 22'd200) begin
                        // 하위 4비트 전송
                        data = {send_buffer[3:0], 3'b100, rs}; 
                        comm_start = 1;
                        count_usec_e = 1;
                    end
                    else begin
                        next_state = SEND_LOW_NIBBLE_ENABLE;
                        count_usec_e = 0;
                        comm_start = 0;
                    end
                end
                
                // 하위 4비트 전송, Enable = 1
                SEND_LOW_NIBBLE_ENABLE     : begin
                    if(count_usec <= 22'd200) begin
                        data = {send_buffer[3:0], 3'b110, rs}; 
                        comm_start = 1;
                        count_usec_e = 1;
                    end
                    else begin
                        next_state = SEND_DISABLE;
                        count_usec_e = 0;
                        comm_start = 0;
                    end
                end
                
                // 최종적으로 Enable = 0으로 만들어 전송 완료
                SEND_DISABLE               : begin
                    if(count_usec <= 22'd200) begin
                        data = {send_buffer[3:0], 3'b100, rs}; 
                        comm_start = 1;
                        count_usec_e = 1;
                    end
                    else begin
                        next_state = IDLE;          // 다시 대기 상태로
                        count_usec_e = 0;
                        comm_start = 0;
                        busy = 0;                   // 전송 완료
                    end
                end
            endcase
        end
    end
endmodule


// ===========================================================
// pwm_led_128step
// - 128-step 분해능 PWM 생성 (파라미터로 sys_clk_freq, pwm_freq 사용)
// - 내부적으로 분주하여 pwm_freqX128 신호 생성 후 네거티브 엣지에서 듀티 카운트
// Ports:
//   clk, reset_p : 클럭/리셋
//   duty         : 듀티 (0..127)
//   pwm          : PWM 출력
// ===========================================================
module pwm_led_128step(
    input clk, reset_p,
    input [6:0] duty,
    output reg pwm);
    
    parameter sys_clk_freq = 100_000_000;
    parameter pwm_freq = 10_000;
    parameter duty_step = 128;
    parameter temp = sys_clk_freq / pwm_freq / duty_step / 2;
    
    integer cnt;
    reg pwm_freqX128;
    always @(posedge clk, posedge reset_p) begin
        if(reset_p) begin
            cnt = 0;
            pwm_freqX128 = 0;
        end
        else begin
            if(cnt >= temp - 1) begin
                cnt = 0;
                pwm_freqX128 = ~pwm_freqX128;
            end
            else cnt = cnt + 1;            
        end
    end
    
    wire pwm_freqX128_nedge;
    edge_detector_p send_ed(
        .clk(clk), 
        .reset_p(reset_p), 
        .cp(pwm_freqX128),
        .n_edge(pwm_freqX128_nedge));
        
    reg [6:0] cnt_duty;
    always @(posedge clk, posedge reset_p) begin
        if(reset_p)begin
            cnt_duty = 0;
            pwm = 0;
        end
        else if(pwm_freqX128_nedge) begin
            cnt_duty = cnt_duty + 1;
            if(cnt_duty < duty) pwm = 1;
            else pwm = 0;
        end
    end

endmodule


// ===========================================================
// pwm_Nfreq_Nstep
// - 파라미터로 주파수(pwm_freq)와 분해능(duty_step_N)을 조정 가능한 PWM 생성기
// - 개념은 pwm_led_128step과 동일 (더 일반화된 버전)
// Ports:
//   clk, reset_p : 클럭/리셋
//   duty         : 듀티 값 (0..duty_step_N)
//   pwm          : PWM 출력
// ===========================================================
module pwm_Nfreq_Nstep(
    input clk, reset_p,      // 시스템 클럭, 리셋 입력
    input [31:0] duty,       // 듀티비 설정 값 (0 ~ duty_step_N)
    output reg pwm           // PWM 출력
);

    // ----------------------------------------------
    // 파라미터 정의
    // ----------------------------------------------
    parameter sys_clk_freq = 100_000_000; // 시스템 클럭 주파수 (100 MHz)
    parameter pwm_freq     = 10_000;      // 목표 PWM 주파수 (10 kHz)
    parameter duty_step_N  = 200;         // 듀티비 분해능 (200 스텝)
    // sys_clk_freq / pwm_freq / duty_step_N / 2
    // → PWM의 최소 단위 시간을 만들기 위한 분주값
    parameter temp = sys_clk_freq / pwm_freq / duty_step_N / 2;
    
    // ----------------------------------------------
    // 분주기: PWM 클럭 생성
    // ----------------------------------------------
    integer cnt;
    reg pwm_freqXn; // 분주된 PWM용 클럭
    
    always @(posedge clk, posedge reset_p) begin
        if (reset_p) begin
            cnt        = 0;
            pwm_freqXn = 0;
        end else begin
            if (cnt >= temp - 1) begin
                cnt        = 0;
                pwm_freqXn = ~pwm_freqXn; // 분주된 클럭 토글
            end else begin
                cnt = cnt + 1;
            end
        end
    end
    
    // ----------------------------------------------
    // 분주된 클럭의 네거티브 엣지 검출기
    // → PWM 주기의 기준 이벤트로 사용
    // ----------------------------------------------
    wire pwm_freqXn_nedge;
    edge_detector_p pwm_freqX128_ed(
        .clk(clk), 
        .reset_p(reset_p), 
        .cp(pwm_freqXn),
        .n_edge(pwm_freqXn_nedge) // 네거티브 엣지 출력
    );
        
    // ----------------------------------------------
    // 듀티비 카운터 및 PWM 출력 생성
    // ----------------------------------------------
    integer cnt_duty;
    always @(posedge clk, posedge reset_p) begin
        if (reset_p) begin
            cnt_duty = 0;
            pwm      = 0;
        end 
        else if (pwm_freqXn_nedge) begin
            // 듀티 카운터 증가
            if (cnt_duty >= duty_step_N) 
                cnt_duty = 0;
            else 
                cnt_duty = cnt_duty + 1;

            // 듀티비 비교 → PWM 출력 결정
            if (cnt_duty < duty) 
                pwm = 1;
            else 
                pwm = 0;
        end
    end
    
endmodule

module smart_watch (
    input clk,
    input reset_p,
    input btn_mode,
    input inc_sec,
    input inc_min,
    output reg [7:0] sec,
    output reg [7:0] min,
    output reg set_watch
);

    // 시스템 클럭 카운터
    reg [35:0] cnt_sysclk;

    // 모드 전환
    always @(posedge clk or posedge reset_p) begin
        if (reset_p)
            set_watch <= 0;
        else if (btn_mode)
            set_watch <= ~set_watch;
    end

    // 시계 동작
    always @(posedge clk or posedge reset_p) begin
        if (reset_p) begin
            cnt_sysclk <= 0;
            sec <= 0;
            min <= 0;
        end else begin
            if (set_watch) begin
                if (cnt_sysclk >= 36'd600_000_000_0-1) begin
                    cnt_sysclk <= 0;
                    if (sec >= 59) begin
                        sec <= 0;
                        if (min >= 23)
                            min <= 0;
                        else
                            min <= min + 1;
                    end else
                        sec <= sec + 1;
                end else
                    cnt_sysclk <= cnt_sysclk + 1;
            end

            if (inc_sec && !set_watch)
                sec <= (sec >= 59) ? 0 : sec + 1;
            if (inc_min && !set_watch)
                min <= (min >= 23) ? 0 : min + 1;
        end
    end
endmodule