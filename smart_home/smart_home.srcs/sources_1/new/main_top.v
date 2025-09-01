module main_top(
    input clk, reset_p,  
    input [3:0] btn,     
    input [1:0] mode_sel,
    input echo,
    input [3:0] row,   
    input vauxp6, vauxn6, vauxp14, vauxn14,
    input door_btn,
    output servo_out, led_b, led_r,       
    output[3:0] column,        
    output scl, sda,
    output trig,
    output inner_scl, inner_sda,
    output [7:0] seg_7,
    output [3:0] com,     
    output [15:0] led,
    output reg motor_on,
    output sg90,
    inout dht11_data);
    
    wire is_hot, is_occupied, door_open, btn_signal;
    
    // 올바른 모듈 인스턴스화
    lcd_dht11_watch_top lcd_dht11(
        .clk(clk), 
        .reset_p(reset_p), 
        .btn(btn), 
        .mode_sel(mode_sel), 
        .scl(inner_scl), 
        .sda(inner_sda), 
        .is_hot(is_hot), 
        .dht11_data(dht11_data)
    );
    
    // 초음파 센서 모듈 - 올바른 인스턴스화
    ultrasonic_top ultra_inst(
        .clk(clk),
        .reset_p(reset_p), 
        .echo(echo),
        .trig(trig),
        .seg_7(seg_7),
        .com(com),
        .is_occupied(is_occupied)  // 마지막 포트
    );
    
    // LCD 키패드 모듈 - 올바른 인스턴스화 (포트 순서대로)
    lcd_top lcd_inst(
        .clk(clk), 
        .reset_p(reset_p), 
        .btn(btn), 
        .row(row), 
        .column(column), 
        .scl(scl), 
        .sda(sda), 
        .door_open(door_open)
    );
    
    // 도어 모터 모듈 - 올바른 인스턴스화
    door_motor_top door_inst(
        .clk(clk), 
        .reset_p(reset_p), 
        .door_open(door_open), 
        .door_btn(door_btn), 
        .btn_signal(btn_signal), 
        .sg90(sg90)
    );
    
    // ADC 모듈 - 올바른 인스턴스화
    adc_sequence2_top adc_inst(
        .clk(clk), 
        .reset_p(reset_p), 
        .vauxp6(vauxp6), 
        .vauxn6(vauxn6), 
        .vauxp14(vauxp14), 
        .vauxn14(vauxn14), 
        .servo_out(servo_out), 
        .led_b(led_b), 
        .led_r(led_r)
    );
    
    // 신호 안정화를 위한 레지스터들 - 비트폭 수정
    reg [23:0] stable_counter;      
    reg [25:0] motor_off_counter;   // 26비트로 수정
    reg motor_enable;
    
    // 디버깅용 LED 할당 - 더 많은 신호 모니터링
    assign led[10] = is_hot;      
    assign led[11] = motor_on;    
    assign led[9] = is_occupied;  
    assign led[8] = motor_enable; 
    assign led[7] = (stable_counter > 0); // 안정화 카운터 동작 확인
    assign led[6] = (motor_off_counter > 0); // 오프 카운터 동작 확인
    assign led[5] = (is_hot && is_occupied); // 두 조건 AND 결과
    assign led[15:12] = stable_counter[23:20]; // 상위 4비트 표시
    
    // 안정화 시간 파라미터 (100MHz 기준)
    localparam STABLE_TIME = 24'd10_000_000;  // 0.1초
    localparam OFF_DELAY_TIME = 26'd50_000_000; // 0.5초 (26비트로 수정)
    
    always @(posedge clk, posedge reset_p) begin
        if(reset_p) begin
            motor_on <= 0;
            motor_enable <= 0;
            stable_counter <= 0;
            motor_off_counter <= 0;
        end
        else begin
            // 두 조건이 모두 만족될 때
            if(is_hot && is_occupied) begin
                if(stable_counter < STABLE_TIME) begin
                    stable_counter <= stable_counter + 1;
                    motor_off_counter <= 0; // 오프 카운터 리셋
                end
                else begin
                    motor_enable <= 1;
                end
            end
            // 조건이 만족되지 않을 때
            else begin
                stable_counter <= 0; // 안정화 카운터 리셋
                if(motor_enable) begin
                    // 모터가 켜져 있다면 일정 시간 후 끄기
                    if(motor_off_counter < OFF_DELAY_TIME) begin
                        motor_off_counter <= motor_off_counter + 1;
                    end
                    else begin
                        motor_enable <= 0;
                        motor_off_counter <= 0;
                    end
                end
                else begin
                    motor_off_counter <= 0;
                end
            end
            
            motor_on <= motor_enable;
        end
    end
    
endmodule