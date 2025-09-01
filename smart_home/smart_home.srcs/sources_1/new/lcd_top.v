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
// Description: 패스워드 입력 시스템 (4자리)
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments: 키패드로 4자리 패스워드 입력 및 검증
// 
//////////////////////////////////////////////////////////////////////////////////


module lcd_top(
    input clk, reset_p,        // 시스템 클럭, 리셋
    input [3:0] btn,           // 버튼 입력 (4개)
    input [3:0] row,           // 키패드 row
    output[3:0] column,        // 키패드 column
    output scl, sda,           // I2C 신호
    output [15:0] led,
    output reg door_open);     // 문 열림 상태 출력

    // 버튼의 상승엣지 검출 모듈 인스턴스
    wire [3:0] btn_pedge;
    btn_cntr btn0(clk, reset_p, btn[0], btn_pedge[0]);
    btn_cntr btn1(clk, reset_p, btn[1], btn_pedge[1]);
    btn_cntr btn2(clk, reset_p, btn[2], btn_pedge[2]);
    btn_cntr btn3(clk, reset_p, btn[3], btn_pedge[3]);
    
    // LCD 초기화를 위한 지연 카운터 (전원 안정화 대기)
    integer cnt_sysclk;
    reg count_clk_e;
    always @(negedge clk, posedge reset_p) begin
        if(reset_p) cnt_sysclk = 0;
        else if(count_clk_e) cnt_sysclk = cnt_sysclk + 1;
        else cnt_sysclk = 0;
    end
    
    // 인증 성공 후 문 열림 유지 시간 카운터
    integer valid_sysclk;
    reg valid_clk_e;
    always @(negedge clk, posedge reset_p) begin
        if(reset_p) valid_sysclk = 0;
        else if(valid_clk_e) valid_sysclk = valid_sysclk + 1;
        else valid_sysclk = 0;
    end
    
    // 인증 실패 후 화면 복구 지연 카운터
    integer wrong_sysclk;
    reg wrong_clk_e;
    always @(negedge clk, posedge reset_p) begin
        if(reset_p) wrong_sysclk = 0;
        else if(wrong_clk_e) wrong_sysclk = wrong_sysclk + 1;
        else wrong_sysclk = 0;
    end
    
    // I2C LCD 통신을 위한 신호들
    reg [7:0] send_buffer;   // LCD로 전송할 데이터 버퍼
    reg send, rs;            // send: 송신 시작 신호, rs: 명령/데이터 모드 선택 (0:명령, 1:데이터)
    wire busy;               // I2C 통신 중 상태 신호

    // I2C LCD 바이트 전송 모듈
    i2c_lcd_send_byte send_byte(
        clk, reset_p, 7'h27, send_buffer, send, rs, 
        scl, sda, busy, led
    );

    // 키패드 입력 처리 모듈
    wire [3:0] key_value;   // 눌린 키의 값 (0~9, 10:*, 11:#)
    wire key_valid;         // 유효한 키 입력 감지 신호
    keypad_door_cntr keypad(clk, reset_p, row, column, key_value, key_valid);
    
    // 키 입력의 상승엣지 검출 (중복 입력 방지)
    wire key_valid_pedge;
    edge_detector_p key_valid_ed(
        .clk(clk), 
        .reset_p(reset_p), 
        .cp(key_valid),
        .p_edge(key_valid_pedge));
        
    // FSM(유한상태기계) 상태 정의
    localparam IDLE                 = 8'b0000_0001;  // 대기 상태
    localparam INIT                 = 8'b0000_0010;  // LCD 초기화
    localparam SEND_UNDERSCORE      = 8'b0010_0000;  // 언더바('____') 출력
    localparam MOVE_TO_FIRST_UNDER  = 8'b0100_0000;  // 첫 번째 언더바로 커서 이동
    localparam SEND_KEY             = 8'b1000_0000;  // 입력된 숫자 출력
    localparam CHECK_PASSWORD       = 8'b0011_0000;  // 패스워드 검증
    localparam SEND_SUCCESS         = 8'b0101_0000;  // 성공 메시지 출력
    localparam SEND_FAIL            = 8'b1001_0000;  // 실패 메시지 출력
    localparam MOVE_TO_SECOND_LINE  = 8'b1100_0000;  // LCD 2번째 라인으로 이동
    localparam IS_WRONG             = 8'b1010_0000;  // 틀림 후 초기화 대기
    localparam IS_DONE              = 8'b1101_0000;  // 성공 후 문열림 상태

    // 상태 레지스터
    reg [7:0] state, next_state;
    always @(negedge clk, posedge reset_p) begin
        if(reset_p) state = IDLE;
        else state = next_state;
    end
    
    // 시스템 제어 변수들
    reg init_flag;          // LCD 초기화 완료 플래그
    reg [10:0] cnt_data;    // 데이터 전송 순서 카운터
    reg [1:0] input_pos;    // 현재 패스워드 입력 위치 (0~3)
    reg underscore_sent;    // 언더바 출력 완료 플래그
    reg [3:0] input_password [3:0];    // 사용자가 입력한 4자리 패스워드 저장 배열
    reg [3:0] correct_password [3:0];  // 정답 패스워드 저장 배열 (1234)
    reg password_complete;   // 4자리 패스워드 입력 완료 플래그
    reg star_pressed_once;   // '*' 키 첫 번째 입력 플래그 (언더바 출력용)
    reg is_done;            // 인증 성공 완료 플래그
    reg is_wrong;           // 인증 실패 플래그
    
    // 정답 패스워드를 1234로 초기화
    initial begin
        correct_password[0] = 4'd1;
        correct_password[1] = 4'd2;
        correct_password[2] = 4'd3;
        correct_password[3] = 4'd4;
    end
    
    // 메인 상태기계 로직
    always @(posedge clk, posedge reset_p) begin
        if(reset_p) begin
            // 리셋 시 모든 변수 초기화
            next_state = IDLE;
            door_open = 0;
            init_flag = 0;
            count_clk_e = 0;
            valid_clk_e = 0;
            wrong_clk_e = 0;
            is_done = 0;
            is_wrong = 0;
            send = 0;
            send_buffer = 0;
            rs = 0;
            cnt_data = 0;
            input_pos = 0;
            underscore_sent = 0;
            password_complete = 0;
            star_pressed_once = 0;
            input_password[0] = 0;
            input_password[1] = 0;
            input_password[2] = 0;
            input_password[3] = 0;
        end
        else begin
            case(state)
                // 시스템 대기 상태
                IDLE: begin
                    if(init_flag) begin // LCD 초기화가 완료된 경우
                        if(is_wrong) begin // 인증 실패 후 복구
                            next_state = SEND_UNDERSCORE;
                            input_pos = 0;
                            underscore_sent = 0;
                            password_complete = 0;
                            star_pressed_once = 1;
                            is_wrong = 0;
                        end
                        // 키패드 입력 처리
                        if(key_valid_pedge) begin
                            if(key_value == 10) begin  // '*' 키 입력 처리
                                if(!star_pressed_once) begin  // 첫 번째 '*': 언더바 출력 시작
                                    next_state = SEND_UNDERSCORE;
                                    input_pos = 0;
                                    underscore_sent = 0;
                                    password_complete = 0;
                                    star_pressed_once = 1;
                                end
                                else if(password_complete) begin  // 두 번째 '*': 패스워드 검증 시작
                                    next_state = CHECK_PASSWORD;
                                end
                            end
                            else if(key_value <= 9 && underscore_sent && !password_complete) begin 
                                // 숫자 키 입력 (0~9), 언더바 출력 후, 4자리 미완료 시
                                next_state = SEND_KEY;
                            end
                        end
                    end
                    else begin
                        // LCD 초기화 전 안정화 대기 (800ms)
                        if(cnt_sysclk <= 32'd80_000_00) begin
                            count_clk_e = 1;
                        end
                        else begin
                            next_state = INIT;
                            count_clk_e = 0;
                        end
                    end
                end

                // LCD 초기화 상태 (표준 초기화 시퀀스)
                INIT: begin
                    if(busy) begin  // I2C 전송 중이면 대기
                        send = 0;
                        if(cnt_data >= 6) begin  // 6개 초기화 명령 완료
                            cnt_data = 0;
                            next_state = IDLE;
                            init_flag = 1; // 초기화 완료 표시
                        end
                    end
                    else if(!send) begin  // 전송 준비 상태
                        case(cnt_data)
                            0:send_buffer = 8'h33;  // Function Set
                            1:send_buffer = 8'h32;  // Function Set  
                            2:send_buffer = 8'h28;  // 4bit, 2line, 5x7 font
                            3:send_buffer = 8'h0c;  // Display ON, Cursor OFF
                            4:send_buffer = 8'h01;  // Clear Display
                            5:send_buffer = 8'h06;  // Entry Mode Set
                        endcase
                        send = 1;  // 전송 시작
                        cnt_data = cnt_data + 1;
                    end
                end
                
                // '*' 키 첫 번째 입력: "      ____" 출력 상태
                SEND_UNDERSCORE: begin
                    if(busy) begin
                        send = 0;
                        if(cnt_data >= 10) begin  // 공백 6개 + 언더바 4개 = 총 10개 문자
                            cnt_data = 0;
                            next_state = MOVE_TO_FIRST_UNDER;
                        end
                    end
                    else if(!send) begin
                        if(cnt_data < 6) begin  // 처음 6개는 공백 출력
                            rs = 1;  // 데이터 모드
                            send_buffer = " ";
                            send = 1;
                            cnt_data = cnt_data + 1;
                        end else begin          // 나머지 4개는 언더바 출력
                            rs = 1;  // 데이터 모드
                            send_buffer = "_";
                            send = 1;
                            cnt_data = cnt_data + 1;
                        end        
                    end
                end
                
                // 첫 번째 언더바 위치로 커서 이동 상태
                MOVE_TO_FIRST_UNDER: begin
                    if(busy) begin
                        send = 0;
                        if(cnt_data >= 4) begin  // 커서를 4칸 왼쪽으로 이동
                            cnt_data = 0;
                            next_state = IDLE;
                            underscore_sent = 1;  // 언더바 출력 완료 표시
                        end
                    end
                    else if(!send) begin
                        rs = 0;          // 명령 모드
                        send_buffer = 8'h10;  // 커서 왼쪽 이동 명령
                        send = 1;
                        cnt_data = cnt_data + 1;
                    end
                end

                // 키패드 숫자 입력 처리: 언더바를 숫자로 교체
                SEND_KEY: begin
                    if(busy) begin
                        send = 0;
                        next_state = IDLE;
                        // 입력된 숫자를 패스워드 배열에 저장
                        input_password[input_pos] = key_value;
                        // 입력 위치 업데이트
                        if(input_pos >= 3) begin
                            password_complete = 1;  // 4자리 입력 완료
                        end
                        else begin
                            input_pos = input_pos + 1;  // 다음 위치로 이동
                        end
                    end
                    else if(!send) begin
                        rs = 1;          // 데이터 모드
                        send_buffer = "0" + key_value;  // 숫자를 ASCII 문자로 변환
                        send = 1;
                    end
                end
                
                // 패스워드 검증 상태
                CHECK_PASSWORD: begin
                    // 입력된 4자리와 정답 4자리 비교
                    if((input_password[0] == correct_password[0]) &&
                       (input_password[1] == correct_password[1]) &&
                       (input_password[2] == correct_password[2]) &&
                       (input_password[3] == correct_password[3])) begin
                        next_state = MOVE_TO_SECOND_LINE;
                        cnt_data = 1;  // 성공 플래그 설정
                    end
                    else begin
                        next_state = MOVE_TO_SECOND_LINE;
                        cnt_data = 0;  // 실패 플래그 설정
                    end
                end
                
                // LCD 2번째 라인으로 커서 이동
                MOVE_TO_SECOND_LINE: begin
                    if(busy) begin
                        send = 0;
                        if(cnt_data == 1) begin  // 인증 성공
                            next_state = SEND_SUCCESS;
                            cnt_data = 0;
                        end
                        else begin  // 인증 실패
                            next_state = SEND_FAIL;
                            cnt_data = 0;
                        end
                    end
                    else if(!send) begin
                        rs = 0;          // 명령 모드
                        send_buffer = 8'hC0;  // 2번째 라인 첫 번째 위치 (0x80 + 0x40)
                        send = 1;
                    end
                end
                
                // 인증 성공 메시지 "    SUCCESS!" 출력
                SEND_SUCCESS: begin
                    if(busy) begin
                        send = 0;
                        if(cnt_data >= 12) begin  // 공백 4개 + "SUCCESS!" 8개 = 12개
                            cnt_data = 0;
                            next_state = IS_DONE;
                            // 시스템 변수 리셋 (재입력 준비)
                            star_pressed_once = 0;
                            underscore_sent = 0;
                            password_complete = 0;
                            input_pos = 0;
                        end
                    end
                    else if(!send) begin
                        rs = 1;  // 데이터 모드
                        case(cnt_data)
                            0: send_buffer = " ";
                            1: send_buffer = " ";
                            2: send_buffer = " ";
                            3: send_buffer = " ";
                            4: send_buffer = "S";
                            5: send_buffer = "U";
                            6: send_buffer = "C";
                            7: send_buffer = "C";
                            8: send_buffer = "E";
                            9: send_buffer = "S";
                            10: send_buffer = "S";
                            11: send_buffer = "!";
                        endcase
                        send = 1;
                        cnt_data = cnt_data + 1;
                        is_done = 1;  // 성공 완료 플래그 설정
                    end
                end
                
                // 인증 실패 메시지 "     WRONG!" 출력
                SEND_FAIL: begin
                    if(busy) begin
                        send = 0;
                        if(cnt_data >= 11) begin  // 공백 5개 + "WRONG!" 6개 = 11개
                            cnt_data = 0;
                            next_state = IS_WRONG;  // 실패 후 대기 상태로
                            // 패스워드 입력 관련 변수만 리셋
                            underscore_sent = 0;
                            password_complete = 0;
                            input_pos = 0;
                            // star_pressed_once는 유지 (이미 언더바 출력했으므로)
                        end
                    end
                    else if(!send) begin
                        rs = 1;  // 데이터 모드
                        case(cnt_data)
                            0: send_buffer = " ";
                            1: send_buffer = " ";
                            2: send_buffer = " ";
                            3: send_buffer = " ";
                            4: send_buffer = " ";
                            5: send_buffer = "W";
                            6: send_buffer = "R";
                            7: send_buffer = "O";
                            8: send_buffer = "N";
                            9: send_buffer = "G";
                            10: send_buffer = "!";
                        endcase
                        send = 1;
                        cnt_data = cnt_data + 1;
                        is_wrong = 1;  // 실패 플래그 설정
                    end
                end
                
                // 인증 실패 후 화면 초기화 대기 (1초)
                IS_WRONG: begin
                    if(is_wrong) begin
                        if(wrong_sysclk <= 32'd100_000_000) begin  // 1초 대기
                            wrong_clk_e = 1;
                        end
                        else begin
                            // 시스템 완전 리셋 (LCD 재초기화)
                            next_state = IDLE;
                            init_flag = 0;
                            count_clk_e = 0;
                            valid_clk_e = 0;
                            wrong_clk_e = 0;
                            is_done = 0;
                            send = 0;
                            send_buffer = 0;
                            rs = 0;
                            cnt_data = 0;
                            input_pos = 0;
                            underscore_sent = 0;
                            password_complete = 0;
                            star_pressed_once = 0;
                            input_password[0] = 0;
                            input_password[1] = 0;
                            input_password[2] = 0;
                            input_password[3] = 0;
                        end
                    end
                end
                
                // 인증 성공 후 문 열림 상태 (10초간 유지)
                IS_DONE: begin
                    if(is_done) begin
                        if(valid_sysclk <= 32'd100_000_000_0) begin  // 10초간 문 열림
                            valid_clk_e = 1;
                            door_open = 1;  // 문 열림 신호 출력
                        end
                        else begin
                            // 10초 후 시스템 완전 리셋
                            door_open = 0;
                            next_state = IDLE;
                            init_flag = 0;
                            count_clk_e = 0;
                            valid_clk_e = 0;
                            wrong_clk_e = 0;
                            is_done = 0;
                            is_wrong = 0;
                            send = 0;
                            send_buffer = 0;
                            rs = 0;
                            cnt_data = 0;
                            input_pos = 0;
                            underscore_sent = 0;
                            password_complete = 0;
                            star_pressed_once = 0;
                            input_password[0] = 0;
                            input_password[1] = 0;
                            input_password[2] = 0;
                            input_password[3] = 0;
                        end
                    end
                end
            endcase
        end
    end
endmodule