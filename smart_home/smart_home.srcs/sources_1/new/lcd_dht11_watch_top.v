`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/27/2025 03:51:46 PM
// Design Name: 
// Module Name: lcd_dht11_watch_top
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


module lcd_dht11_watch_top(
    input clk, reset_p,        // 시스템 클럭, 리셋
    input [3:0] btn,           // 버튼 입력 (4개)
    input [1:0] mode_sel,      // 00: LCD, 01: Watch
    output scl, sda,           // I2C 신호
    output [15:0] led,         // 상태 확인용 LED
    inout dht11_data           // DHT11 데이터 핀
);
    wire is_hot;
    // 버튼 상승엣지 검출
    wire [3:0] btn_pedge_raw;
    btn_cntr btn0(clk, reset_p, btn[0], btn_pedge_raw[0]);
    btn_cntr btn1(clk, reset_p, btn[1], btn_pedge_raw[1]);
    btn_cntr btn2(clk, reset_p, btn[2], btn_pedge_raw[2]);
    btn_cntr btn3(clk, reset_p, btn[3], btn_pedge_raw[3]);

    // ---------------------------
    // 모드별 버튼 MUX
    // ---------------------------
    wire [3:0] lcd_btn_pedge;
    wire inc_sec, inc_min, btn_mode;
    
    // LCD 모드일 때만 LCD 버튼 활성화
    assign lcd_btn_pedge[0] = (mode_sel == 2'b00) ? btn_pedge_raw[0] : 1'b0;
    assign lcd_btn_pedge[1] = (mode_sel == 2'b00) ? btn_pedge_raw[1] : 1'b0;
    assign lcd_btn_pedge[2] = (mode_sel == 2'b00) ? btn_pedge_raw[2] : 1'b0;
    assign lcd_btn_pedge[3] = (mode_sel == 2'b00) ? btn_pedge_raw[3] : 1'b0;

    // Watch 모드일 때만 Watch 버튼 활성화
    assign inc_sec  = (mode_sel == 2'b01) ? btn_pedge_raw[0] : 1'b0;
    assign inc_min  = (mode_sel == 2'b01) ? btn_pedge_raw[1] : 1'b0;
    assign btn_mode = (mode_sel == 2'b01) ? btn_pedge_raw[2] : 1'b0;
    

    // ---------------------------
    // Watch 모듈
    // ---------------------------
    wire [7:0] sec, min;
    wire set_watch;

    smart_watch watch_inst(
        .clk(clk),
        .reset_p(reset_p),
        .btn_mode(btn_mode),
        .inc_sec(inc_sec),
        .inc_min(inc_min),
        .sec(sec),
        .min(min),
        .set_watch(set_watch)
    );

    // LCD 초기화를 위한 지연 카운터
    integer cnt_sysclk;
    reg count_clk_e;
    always @(negedge clk, posedge reset_p) begin
        if (reset_p) cnt_sysclk <= 0;
        else if (count_clk_e) cnt_sysclk <= cnt_sysclk + 1;
        else cnt_sysclk <= 0;
    end

    // I2C LCD 전송용 신호
    reg [7:0] send_buffer;
    reg send, rs;
    wire busy;

    i2c_lcd_send_byte send_byte(
        clk, reset_p, 7'h27, send_buffer, send, rs,
        scl, sda, busy, led
    );

    // DHT11 제어 모듈
    wire [7:0] humidity, temperature;
    dht11_cntr dht11_inst(
        .clk(clk),
        .reset_p(reset_p),
        .dht11_data(dht11_data),
        .humidity(humidity),
        .temperature(temperature),
        .is_hot(is_hot),
        .led() // LED는 LCD 모듈에서 사용
    );
    
    assign led[12] = is_hot;

    // FSM 상태 정의
    localparam IDLE                 = 6'b00_0001;
    localparam INIT                 = 6'b00_0010;
    localparam SEND_CHARACTER       = 6'b00_0100;
    localparam SHIFT_RIGHT_DISPLAY  = 6'b00_1000;
    localparam SHIFT_LEFT_DISPLAY   = 6'b01_0000;
    localparam SEND_DATA            = 6'b10_0000;  // DHT+Watch 데이터 전송

    reg [5:0] state, next_state;
    always @(negedge clk, posedge reset_p) begin
        if (reset_p) state <= IDLE;
        else state <= next_state;
    end

    // DHT11 데이터 → 문자 변환
    reg [7:0] humi_tens, humi_ones;
    reg [7:0] temp_tens, temp_ones;
    always @(*) begin
        humi_tens = "0" + (humidity / 10);
        humi_ones = "0" + (humidity % 10);
        temp_tens = "0" + (temperature / 10);
        temp_ones = "0" + (temperature % 10);
    end

    // LCD 초기화 및 데이터 송신 관리
    reg init_flag;
    reg [10:0] cnt_data;
    reg [31:0] update_cnt;
    localparam UPDATE_INTERVAL = 32'd100_000_000; // 100MHz 1초 기준

    always @(posedge clk, posedge reset_p) begin
        if (reset_p) begin
            next_state   <= IDLE;
            init_flag    <= 0;
            count_clk_e  <= 0;
            send         <= 0;
            send_buffer  <= 0;
            rs           <= 0;
            cnt_data     <= 0;
            update_cnt   <= 0;
        end
        else begin
            case (state)
                // 초기 대기 상태
                IDLE: begin
                    if (init_flag) begin
                        // 1초마다 자동으로 데이터 송신 (DHT11 + Watch)
                        if (update_cnt >= UPDATE_INTERVAL) begin
                            update_cnt <= 0;
                            next_state <= SEND_DATA;
                        end
                        else update_cnt <= update_cnt + 1;

                        // LCD 모드일 때만 버튼 기능 활성화
                        if (mode_sel == 2'b00) begin
                            if (lcd_btn_pedge[0]) next_state <= SEND_CHARACTER;
                            else if (lcd_btn_pedge[1]) next_state <= SHIFT_RIGHT_DISPLAY;
                            else if (lcd_btn_pedge[2]) next_state <= SHIFT_LEFT_DISPLAY;
                        end
                        // Watch 모드일 때는 버튼이 watch 모듈에서 처리됨
                    end
                    else begin
                        if (cnt_sysclk <= 32'd16_000_000)
                            count_clk_e <= 1;
                        else begin
                            next_state  <= INIT;
                            count_clk_e <= 0;
                        end
                    end
                end

                // LCD 초기화
                INIT: begin
                    if (busy) begin
                        send <= 0;
                        if (cnt_data >= 6) begin
                            cnt_data  <= 0;
                            next_state<= IDLE;
                            init_flag <= 1;
                        end
                    end
                    else if (!send) begin
                        case (cnt_data)
                            0: send_buffer <= 8'h33;
                            1: send_buffer <= 8'h32;
                            2: send_buffer <= 8'h28;
                            3: send_buffer <= 8'h0c;
                            4: send_buffer <= 8'h01;
                            5: send_buffer <= 8'h06;
                        endcase
                        send     <= 1;
                        cnt_data <= cnt_data + 1;
                    end
                end

                // 버튼0: a~z 출력 (LCD 모드에서만)
                SEND_CHARACTER: begin
                    if (busy) begin
                        send      <= 0;
                        if (cnt_data >= 25) cnt_data <= 0;
                        else cnt_data <= cnt_data + 1;
                        next_state<= IDLE;
                    end
                    else begin
                        rs          <= 1;
                        send_buffer <= "a" + cnt_data;
                        send        <= 1;
                    end
                end

                // 화면 오른쪽 이동 (LCD 모드에서만)
                SHIFT_RIGHT_DISPLAY: begin
                    if (busy) begin
                        send       <= 0;
                        next_state <= IDLE;
                    end
                    else begin
                        rs          <= 0;
                        send_buffer <= 8'h1c;
                        send        <= 1;
                    end
                end

                // 화면 왼쪽 이동 (LCD 모드에서만)
                SHIFT_LEFT_DISPLAY: begin
                    if (busy) begin
                        send       <= 0;
                        next_state <= IDLE;
                    end
                    else begin
                        rs          <= 0;
                        send_buffer <= 8'h18;
                        send        <= 1;
                    end
                end

                // 자동 DHT11 + Watch 출력
                SEND_DATA: begin
                    if (busy) begin
                        send <= 0;
                        if (cnt_data >= 20) begin // 전체 데이터 송신 완료
                            cnt_data  <= 0;
                            next_state<= IDLE;
                        end
                    end
                    else if (!send) begin
                        case (cnt_data)
                            // 화면 클리어 및 첫 번째 줄 설정
                            0: begin 
                                send_buffer <= 8'h01; // 화면 클리어
                                rs <= 0; 
                            end
                            1: begin 
                                send_buffer <= 8'h80+3; // 첫 번째 줄 커서 (3칸 오른쪽으로 이동)
                                rs <= 0; 
                            end
                            
                            // 첫 번째 줄: 온습도 "H45% T25C"
                            2: begin send_buffer <= " "; rs <= 1; end
                            3: begin send_buffer <= " "; rs <= 1; end
                            4: begin send_buffer <= " "; rs <= 1; end   
                            5: begin send_buffer <= "H"; rs <= 1; end
                            6: begin send_buffer <= humi_tens; rs <= 1; end
                            7: begin send_buffer <= humi_ones; rs <= 1; end
                            8: begin send_buffer <= "%"; rs <= 1; end
                            9: begin send_buffer <= " "; rs <= 1; end
                            10: begin send_buffer <= "T"; rs <= 1; end
                            11: begin send_buffer <= temp_tens; rs <= 1; end
                            12: begin send_buffer <= temp_ones; rs <= 1; end
                            13: begin send_buffer <= "C"; rs <= 1; end
                            
                            // 두 번째 줄로 이동
                            14: begin 
                                send_buffer <= 8'hC0+5; // 두 번째 줄 커서
                                rs <= 0; 
                            end
                            
                            // 두 번째 줄: 시간 "12:34"
                            15: begin send_buffer <= "0" + (min / 10); rs <= 1; end
                            16: begin send_buffer <= "0" + (min % 10); rs <= 1; end
                            17: begin send_buffer <= ":"; rs <= 1; end
                            18: begin send_buffer <= "0" + (sec / 10); rs <= 1; end
                            19: begin send_buffer <= "0" + (sec % 10); rs <= 1; end
                            
                            default: begin
                                send_buffer <= 8'h01;
                                rs <= 0;
                            end
                        endcase
                        send     <= 1;
                        cnt_data <= cnt_data + 1;
                    end
                end
            endcase
        end
    end
endmodule