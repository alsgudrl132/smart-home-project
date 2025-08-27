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
    
    integer valid_sysclk;
    reg valid_clk_e;
    always @(negedge clk, posedge reset_p) begin
        if(reset_p) valid_sysclk = 0;
        else if(valid_clk_e) valid_sysclk = valid_sysclk + 1;
        else valid_sysclk = 0;
    end
    
    integer wrong_sysclk;
    reg wrong_clk_e;
    always @(negedge clk, posedge reset_p) begin
        if(reset_p) wrong_sysclk = 0;
        else if(wrong_clk_e) wrong_sysclk = wrong_sysclk + 1;
        else wrong_sysclk = 0;
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
    keypad_door_cntr keypad(clk, reset_p, row, column, key_value, key_valid);
    
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
    localparam IDLE                 = 8'b0000_0001;
    localparam INIT                 = 8'b0000_0010;
    localparam SEND_CHARACTER       = 8'b0000_0100;
    localparam SHIFT_RIGHT_DISPLAY  = 8'b0000_1000;
    localparam SHIFT_LEFT_DISPLAY   = 8'b0001_0000;
    localparam SEND_UNDERSCORE      = 8'b0010_0000;
    localparam MOVE_TO_FIRST_UNDER  = 8'b0100_0000;  // 첫 번째 언더바로 이동
    localparam SEND_KEY             = 8'b1000_0000;
    localparam CHECK_PASSWORD       = 8'b0011_0000;  // 패스워드 검증
    localparam SEND_SUCCESS         = 8'b0101_0000;  // 성공 메시지
    localparam SEND_FAIL            = 8'b1001_0000;  // 실패 메시지
    localparam MOVE_TO_SECOND_LINE  = 8'b1100_0000;  // 2번째 라인으로 이동
    localparam IS_WRONG             = 8'b1010_0000;  // 틀렸을경우 초기상태로 진입후 언더바로까지 진행
    localparam IS_DONE              = 8'b1101_0000;  // 완료후 초기상태로 진입

    // 현재 상태, 다음 상태
    reg [7:0] state, next_state;
    always @(negedge clk, posedge reset_p) begin
        if(reset_p) state = IDLE;
        else state = next_state;
    end
    
    // LCD 초기화 및 데이터 송신 관리
    reg init_flag;          // 초기화 완료 여부
    reg [10:0] cnt_data;    // 전송 데이터 인덱스
    reg [1:0] input_pos;    // 현재 입력 위치 (0~3: 4자리 숫자)
    reg underscore_sent;    // 언더바 출력 완료 여부
    reg [3:0] input_password [3:0];  // 입력된 4자리 패스워드 저장
    reg [3:0] correct_password [3:0]; // 정답 패스워드 (1234)
    reg password_complete;   // 4자리 입력 완료 여부
    reg star_pressed_once;   // 별표 첫 번째 눌림 여부
    reg is_done;
    reg is_wrong;
    
    assign led[5] = is_done;
    assign led[6] = busy;
    assign led[7] = star_pressed_once;
    
    // 정답 패스워드 초기화 (1234)
    initial begin
        correct_password[0] = 4'd1;
        correct_password[1] = 4'd2;
        correct_password[2] = 4'd3;
        correct_password[3] = 4'd4;
    end
    
    always @(posedge clk, posedge reset_p) begin
        if(reset_p) begin
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
        else begin
            case(state)
                // 대기 상태
                IDLE: begin
                    if(init_flag) begin
                        if(is_wrong) begin
                            next_state = SEND_UNDERSCORE;
                            input_pos = 0;
                            underscore_sent = 0;
                            password_complete = 0;
                            star_pressed_once = 1;
                            is_wrong = 0;
                        end
                        // 버튼/키 입력에 따라 상태 전환
                        if(btn_pedge[0]) next_state = SEND_CHARACTER;
                        if(btn_pedge[1]) next_state = SHIFT_RIGHT_DISPLAY;
                        if(btn_pedge[2]) next_state = SHIFT_LEFT_DISPLAY;
                        if(key_valid_pedge) begin
                            if(key_value == 10) begin  // '*' 키
                                if(!star_pressed_once) begin  // 첫 번째 '*': 언더바 출력
                                    next_state = SEND_UNDERSCORE;
                                    input_pos = 0;
                                    underscore_sent = 0;
                                    password_complete = 0;
                                    star_pressed_once = 1;
                                end
                                else if(password_complete) begin  // 두 번째 '*': 패스워드 검증
                                    next_state = CHECK_PASSWORD;
                                end
                            end
                            else if(key_value <= 9 && underscore_sent && !password_complete) begin // 숫자 키 (0~9)
                                next_state = SEND_KEY;
                            end
                        end
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
                
                // '*' 키 첫 번째: "      ____" 출력
                SEND_UNDERSCORE: begin
                    if(busy) begin
                        send = 0;
                        if(cnt_data >= 10) begin
                            cnt_data = 0;
                            next_state = MOVE_TO_FIRST_UNDER;
                        end
                    end
                    else if(!send) begin
                        if(cnt_data < 6) begin  // 첫 6개는 공백
                            rs = 1;
                            send_buffer = " ";
                            send = 1;
                            cnt_data = cnt_data + 1;
                        end else begin          // 나머지 4개는 '_'
                            rs = 1;
                            send_buffer = "_";
                            send = 1;
                            cnt_data = cnt_data + 1;
                        end        
                    end
                end
                
                // 첫 번째 언더바 위치로 커서 이동
                MOVE_TO_FIRST_UNDER: begin
                    if(busy) begin
                        send = 0;
                        if(cnt_data >= 4) begin  // 4번 왼쪽으로 이동
                            cnt_data = 0;
                            next_state = IDLE;
                            underscore_sent = 1;  // 언더바 출력 완료 표시
                        end
                    end
                    else if(!send) begin
                        rs = 0;          // 명령 모드
                        send_buffer = 8'h10;  // 커서 왼쪽 이동
                        send = 1;
                        cnt_data = cnt_data + 1;
                    end
                end

                // 키패드 숫자 입력: 현재 위치의 언더바를 숫자로 치환
                SEND_KEY: begin
                    if(busy) begin
                        send = 0;
                        next_state = IDLE;
                        // 입력된 값 저장
                        input_password[input_pos] = key_value;
                        // 다음 입력 위치로 이동 (4자리 넘으면 입력 완료)
                        if(input_pos >= 3) begin
                            password_complete = 1;  // 4자리 입력 완료
                        end
                        else begin
                            input_pos = input_pos + 1;
                        end
                    end
                    else if(!send) begin
                        rs = 1;          // 데이터 모드
                        send_buffer = "0" + key_value;  // 숫자를 ASCII로 변환
                        send = 1;
                    end
                end
                
                // 패스워드 검증
                CHECK_PASSWORD: begin
                    // 입력된 패스워드와 정답 비교
                    if((input_password[0] == correct_password[0]) &&
                       (input_password[1] == correct_password[1]) &&
                       (input_password[2] == correct_password[2]) &&
                       (input_password[3] == correct_password[3])) begin
                        next_state = MOVE_TO_SECOND_LINE;  // 성공
                        cnt_data = 1;  // 성공 플래그
                    end
                    else begin
                        next_state = MOVE_TO_SECOND_LINE;  // 실패
                        cnt_data = 0;  // 실패 플래그
                    end
                end
                
                // 2번째 라인으로 커서 이동 (0xC0)
                MOVE_TO_SECOND_LINE: begin
                    if(busy) begin
                        send = 0;
                        if(cnt_data == 1) begin  // 성공
                            next_state = SEND_SUCCESS;
                            cnt_data = 0;
                        end
                        else begin  // 실패
                            next_state = SEND_FAIL;
                            cnt_data = 0;
                        end
                    end
                    else if(!send) begin
                        rs = 0;          // 명령 모드
                        send_buffer = 8'hC0;  // 2번째 라인 첫 번째 위치로 이동
                        send = 1;
                    end
                end
                
                // 성공 메시지 출력
                SEND_SUCCESS: begin
                    if(busy) begin
                        send = 0;
                        if(cnt_data >= 8) begin  // "SUCCESS!" = 8글자
                            cnt_data = 0;
                            next_state = IS_DONE;
                            // 시스템 리셋
                            star_pressed_once = 0;
                            underscore_sent = 0;
                            password_complete = 0;
                            input_pos = 0;
                        end
                    end
                    else if(!send) begin
                        rs = 1;  // 데이터 모드
                        case(cnt_data)
                            0: send_buffer = "S";
                            1: send_buffer = "U";
                            2: send_buffer = "C";
                            3: send_buffer = "C";
                            4: send_buffer = "E";
                            5: send_buffer = "S";
                            6: send_buffer = "S";
                            7: send_buffer = "!";
                        endcase
                        send = 1;
                        cnt_data = cnt_data + 1;
                        is_done = 1;
                        
                    end
                end
                
                // 실패 메시지 출력 후 다시 언더바 표시
                SEND_FAIL: begin
                    if(busy) begin
                        send = 0;
                        if(cnt_data >= 6) begin  // "WRONG!" = 6글자
                            cnt_data = 0;
                            next_state = IS_WRONG;  // 다시 언더바 출력
                            // 시스템 부분 리셋
                            underscore_sent = 0;
                            password_complete = 0;
                            input_pos = 0;
                            // star_pressed_once는 유지 (이미 한 번 눌렸으므로)
                        end
                    end
                    else if(!send) begin
                        rs = 1;  // 데이터 모드
                        case(cnt_data)
                            0: send_buffer = "W";
                            1: send_buffer = "R";
                            2: send_buffer = "O";
                            3: send_buffer = "N";
                            4: send_buffer = "G";
                            5: send_buffer = "!";
                        endcase
                        send = 1;
                        cnt_data = cnt_data + 1;
                        is_wrong = 1;
                    end
                end
                
                IS_WRONG: begin
                    if(is_wrong) begin
                        if(wrong_sysclk <= 32'd100_000_000) begin
                            wrong_clk_e = 1;
                        end
                        else begin
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
                
                IS_DONE: begin
                    if(is_done) begin
                        if(valid_sysclk <= 32'd100_000_000_0) begin
                            valid_clk_e = 1;
                        end
                        else begin
                            // reset_p를 누른 것과 동일한 효과
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