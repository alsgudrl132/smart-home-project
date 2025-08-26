`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 08/26/2025 02:08:36 PM
// Design Name: 
// Module Name: lcd_top
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


module lcd_top(
input clk, reset_p,        // 시스템 클럭, 리셋
    input [3:0] btn,           // 버튼 입력 (4개)
    input [3:0] row,           // 키패드 row
    output[3:0] column,        // 키패드 column
    output scl, sda,           // I2C 신호
    output [15:0] led);        // 상태 확인용 LED

    // 버튼의 상승엣지 검출
    wire [3:0] btn_pedge;
    btn_cntr btn0(clk, reset_p, btn[0], btn_pedge[0]);
    btn_cntr btn1(clk, reset_p, btn[1], btn_pedge[1]);
    btn_cntr btn2(clk, reset_p, btn[2], btn_pedge[2]);
    btn_cntr btn3(clk, reset_p, btn[3], btn_pedge[3]);
    
    // LCD 초기화를 위한 지연 카운터
    integer cnt_sysclk;
    reg count_clk_e;
    always @(negedge clk, posedge reset_p) begin
        if(reset_p) cnt_sysclk = 0;
        else if(count_clk_e) cnt_sysclk = cnt_sysclk + 1;
        else cnt_sysclk = 0;
    end
    
    // I2C LCD 전송용 신호
    reg [7:0] send_buffer;   // 보낼 데이터
    reg send, rs;            // send: 송신 트리거, rs: 명령/데이터 선택
    wire busy;               // I2C 동작중 여부

    // LCD로 바이트 단위 송신
    i2c_lcd_send_byte send_byte(
        clk, reset_p, 7'h27, send_buffer, send, rs, 
        scl, sda, busy, led
    );

    // 키패드 제어
    wire [3:0] key_value;   // 입력된 키 값
    wire key_valid;         // 키 입력 유효 여부
    keypad_cntr keypad(clk, reset_p, row, column, key_value, key_valid);
    
    assign led[15] = key_valid;   // 키 유효 여부 LED 표시
    assign led[3:0] = row;        // 디버깅용 row 출력
    
    // 키 유효 신호의 상승엣지 검출
    wire key_valid_pedge;
    edge_detector_p key_valid_ed(
        .clk(clk), 
        .reset_p(reset_p), 
        .cp(key_valid),
        .p_edge(key_valid_pedge));
    
    // FSM 상태 정의
    localparam IDLE                 = 6'b00_0001;
    localparam INIT                 = 6'b00_0010;
    localparam SEND_CHARACTER       = 6'b00_0100;
    localparam SHIFT_RIGHT_DISPLAY  = 6'b00_1000;
    localparam SHIFT_LEFT_DISPLAY   = 6'b01_0000;
    localparam SEND_KEY             = 6'b10_0000;

    // 현재 상태, 다음 상태
    reg [5:0] state, next_state;
    always @(negedge clk, posedge reset_p) begin
        if(reset_p) state = IDLE;
        else state = next_state;
    end
    
    // LCD 초기화 및 데이터 송신 관리
    reg init_flag;          // 초기화 완료 여부
    reg [10:0] cnt_data;    // 전송 데이터 인덱스
    always @(posedge clk, posedge reset_p) begin
        if(reset_p) begin
            next_state = IDLE;
            init_flag = 0;
            count_clk_e = 0;
            send = 0;
            send_buffer = 0;
            rs = 0;
            cnt_data = 0;
        end
        else begin
            case(state)
                // 대기 상태
                IDLE: begin
                    if(init_flag) begin
                        // 버튼/키 입력에 따라 상태 전환
                        if(btn_pedge[0]) next_state = SEND_CHARACTER;
                        if(btn_pedge[1]) next_state = SHIFT_RIGHT_DISPLAY;
                        if(btn_pedge[2]) next_state = SHIFT_LEFT_DISPLAY;
                        if(key_valid_pedge) next_state = SEND_KEY;
                    end
                    else begin
                        // 전원 인가 후 LCD 초기화 지연
                        if(cnt_sysclk <= 32'd80_000_00) begin
                            count_clk_e = 1;
                        end
                        else begin
                            next_state = INIT;
                            count_clk_e = 0;
                        end
                    end
                end

                // LCD 초기화 (데이터시트에 따른 시퀀스)
                INIT: begin
                    if(busy) begin
                        send = 0;
                        if(cnt_data >= 6) begin
                            cnt_data = 0;
                            next_state = IDLE;
                            init_flag = 1; // 초기화 완료
                        end
                    end
                    else if(!send) begin
                        case(cnt_data)
                            0:send_buffer = 8'h33;
                            1:send_buffer = 8'h32;
                            2:send_buffer = 8'h28;
                            3:send_buffer = 8'h0c;
                            4:send_buffer = 8'h01;
                            5:send_buffer = 8'h06;
                        endcase
                        send = 1;
                        cnt_data = cnt_data + 1;
                    end
                end

                // 버튼0: "a~z" 순서 출력
                SEND_CHARACTER: begin
                    if(busy) begin
                        next_state = IDLE;
                        send = 0;
                        if(cnt_data >= 25) cnt_data = 0;
                        cnt_data = cnt_data + 1;
                    end
                    else begin
                        rs = 1;  // 데이터 모드
                        send_buffer = "a" + cnt_data;
                        send = 1;
                    end
                end

                // 버튼1: 화면 오른쪽 이동
                SHIFT_RIGHT_DISPLAY: begin
                    if(busy) begin
                        next_state = IDLE;
                        send = 0;
                    end
                    else begin
                        rs = 0;          // 명령 모드
                        send_buffer = 8'h1c;
                        send = 1;
                    end
                end

                // 버튼2: 화면 왼쪽 이동
                SHIFT_LEFT_DISPLAY: begin
                    if(busy) begin
                        next_state = IDLE;
                        send = 0;
                    end
                    else begin
                        rs = 0;
                        send_buffer = 8'h18;
                        send = 1;
                    end
                end

                // 키패드 입력된 값을 LCD에 표시
                SEND_KEY: begin
                    if(busy) begin
                        next_state = IDLE;
                        send = 0;
                    end
                    else begin
                        rs = 1;
                        if(key_value < 10) send_buffer = "0" + key_value;  // 숫자
                        else if(key_value == 10) send_buffer = "+";
                        else if(key_value == 11) send_buffer = "-";
                        else if(key_value == 12) send_buffer = "C";
                        else if(key_value == 13) send_buffer = "/";
                        else if(key_value == 14) send_buffer = "*";
                        else if(key_value == 15) send_buffer = "=";
                        send = 1;
                    end
                end
            endcase
        end
    end
endmodule
