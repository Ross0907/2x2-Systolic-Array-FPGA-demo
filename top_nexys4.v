// =============================================================================
// FILE        : top_nexys4.v
// DESCRIPTION : Nexys 4 DDR top-level for 2x2 Systolic Array Demo
//
// BOARD : Nexys 4 DDR  (xc7a100t-1csg324c)
// CLOCK : 100 MHz crystal on pin E3
//
// 
//   MATRIX INPUTS  -  16 slide switches (2 bits per element, values 0-3)   
//                                                                           
//     SW[1:0]  = a00    SW[3:2]  = a01    (Matrix A - row 0)              
//     SW[5:4]  = a10    SW[7:6]  = a11    (Matrix A - row 1)              
//     SW[9:8]  = b00    SW[11:10]= b01    (Matrix B - col 0/1, row 0)     
//     SW[13:12]= b10    SW[15:14]= b11    (Matrix B - col 0/1, row 1)     
//                                                                         
//     Example: to enter element = 2, set the two switches to "10"         
//              to enter element = 3, set both switches to  "11"           
//              LSB is the lower-numbered switch of each pair              
//                                                                         
//   CONTROL  -  pushbuttons (active-high, debounced internally)            
//                                                                          
//     BTNC  (center)  ->  MANUAL CLOCK : one press = one pipeline step    
//     BTNL  (left)    ->  START        : arm the computation              
//     BTNR  (right)   ->  RESET        : clear everything, return to IDLE 
//     BTNRES (red)    ->  also acts as RESET                               
//                                                                          
//   OUTPUT  -  16 LEDs  (ALL 16 in use, no constant-driven bits)          
//                                                                           
//     LD[15:12] = C[0][0] = acc00  (4-bit, saturates at 15 for val 16-18) 
//     LD[11:8]  = C[0][1] = acc01  (same encoding)                         
//     LD[7:4]   = C[1][0] = acc10                                           
//     LD[3:0]   = C[1][1] = acc11                                           
//                                                                           
//   Each group of 4 LEDs shows one result element live.  Because 5-bit     
//   accumulators top out at 18 (> 15), values 16-18 are shown as 1111.    
//   The 7-segment display always shows the exact decimal value (0-18).     
//                                                                                                                                              
//   OUTPUT  -  8-digit 7-segment display (live, updates every BTNC press) 
//                                                                           
//     DIG7  DIG6  |  DIG5  DIG4  |  DIG3  DIG2  |  DIG1  DIG0           
//     C[0][0]       C[0][1]         C[1][0]         C[1][1]              
//     (acc00)       (acc01)         (acc10)         (acc11)             
//                                                                        
//     Each pair shows the result in DECIMAL (0-18, leading zero blanked) 
//     Example: A=B=[[2,1],[1,2]] → display shows  " 5  4  4  5"          
//                                                                        
//   FULL DEMO SEQUENCE                                                   
//                                                                        
//     1. Set matrix elements with slide switches SW[15:0]                
//     2. Press BTNR  → Reset (LD all off)                                
//     3. Press BTNL  → Start (arms the array)                            
//     4. Press BTNC × 5  → step through pipeline                         
//          Step 1 : all PEs cleared to 0                                 
//          Step 2 : PE00 shows a00×b00                                   
//          Step 3 : PE00 done (C[0][0]); PE01/PE10 partial               
//          Step 4 : PE01/PE10 done; PE11 gets first product              
//          Step 5 : ALL DONE - 7-seg shows final results
//     5. Read all four results from the LED groups and 7-segment display  
//     6. Press BTNR to reset and try new matrices                          
// =============================================================================

`default_nettype none

module top_nexys4 #(
    // Debounce window in clock cycles.
    // Real board @ 100 MHz: 100_000 = 1 ms
    // Simulation override: set to 5
    parameter DEBOUNCE_MAX = 100_000,

    // Power-on reset duration (cycles)
    // Simulation override: set to 20
    parameter POR_CYCLES   = 20,

    // 7-seg scan: each digit active for 2^SCAN_BITS clock cycles.
    // 2^14 = 16384 cycles @ 100 MHz = ~163 µs/digit  →  ~764 Hz refresh (8 digits)
    parameter SCAN_BITS    = 14
)(
    input  wire        clk,     // 100 MHz, pin E3

    // Pushbuttons  (active-high from the board)
    input  wire        btnc,    // center : manual clock
    input  wire        btnl,    // left   : start
    input  wire        btnr,    // right  : reset
    input  wire        btnres,  // red CPU-reset button : also reset

    // 16 slide switches
    input  wire [15:0] sw,

    // 16 user LEDs
    output wire [15:0] led,

    // 8-digit 7-segment display
    output wire [7:0]  an,      // digit anodes  (active-LOW)
    output wire [6:0]  seg,     // segments CA-CG (active-LOW)
    output wire        dp       // decimal point  (active-LOW, kept OFF)
);

    // =========================================================================
    // 1.  Power-On Reset
    //     Forces rst=1 for POR_CYCLES cycles so all registers start in a
    //     known state before the user touches any button.
    // =========================================================================
    reg [5:0] por_cnt = 6'd0;
    wire      por_rst = (por_cnt < POR_CYCLES);

    always @(posedge clk)
        if (por_rst) por_cnt <= por_cnt + 6'd1;

    // =========================================================================
    // 2.  Button Debounce
    //
    //     Vector: [2]=btnr  [1]=btnl  [0]=btnc
    //             btnr and btnres are OR'd together on bit [2].
    //
    //     Pipeline:
    //       raw inputs  ->  2-FF synchroniser  ->  sampled every DEBOUNCE_MAX
    //       cycles  ->  rising-edge detect  ->  one-cycle pulse per press
    // =========================================================================
    wire [2:0] btn_raw = {(btnr | btnres), btnl, btnc};

    reg [2:0] btn_s0     = 3'b0;
    reg [2:0] btn_s1     = 3'b0;
    reg [2:0] btn_stable = 3'b0;
    reg [2:0] btn_prev   = 3'b0;

    // Two-FF synchroniser
    always @(posedge clk) begin
        if (por_rst) begin
            btn_s0 <= 3'b0;
            btn_s1 <= 3'b0;
        end else begin
            btn_s0 <= btn_raw;
            btn_s1 <= btn_s0;
        end
    end

    // Sample counter + stable register
    reg [16:0] deb_cnt = 17'd0;

    always @(posedge clk) begin
        if (por_rst) begin
            deb_cnt    <= 17'd0;
            btn_stable <= 3'b0;
        end else if (deb_cnt == DEBOUNCE_MAX - 1) begin
            deb_cnt    <= 17'd0;
            btn_stable <= btn_s1;
        end else begin
            deb_cnt <= deb_cnt + 17'd1;
        end
    end

    // Rising-edge detector
    always @(posedge clk)
        if (por_rst) btn_prev <= 3'b0;
        else         btn_prev <= btn_stable;

    wire [2:0] btn_pulse = btn_stable & ~btn_prev;

    wire pulse_clk   = btn_pulse[0];   // BTNC  -> manual clock step
    wire pulse_start = btn_pulse[1];   // BTNL  -> start / arm
    wire pulse_reset = btn_pulse[2];   // BTNR / BTNRES -> reset

    // =========================================================================
    // 3.  Master Reset  =  power-on reset  OR  button reset
    // =========================================================================
    reg rst = 1'b1;
    always @(posedge clk)
        rst <= por_rst | pulse_reset;

    // =========================================================================
    // 4.  Manual Clock Enable
    //     btn_pulse[0] is already a single-cycle pulse - use directly.
    // =========================================================================
    wire clk_en = pulse_clk;

    // =========================================================================
    // 5.  Matrix Element Unpacking from SW[15:0]
    //
    //     Each matrix element is 2 bits (value 0-3).
    //     Lower-numbered switch = LSB of the element.
    //
    //     Matrix A (rows):
    //       SW[1:0]  - a00   SW[3:2]  - a01
    //       SW[5:4]  - a10   SW[7:6]  - a11
    //
    //     Matrix B (columns):
    //       SW[9:8]  - b00   SW[11:10]- b01
    //       SW[13:12]- b10   SW[15:14]- b11
    // =========================================================================
    wire [1:0] a00 = sw[1:0];
    wire [1:0] a01 = sw[3:2];
    wire [1:0] a10 = sw[5:4];
    wire [1:0] a11 = sw[7:6];

    wire [1:0] b00 = sw[9:8];
    wire [1:0] b01 = sw[11:10];
    wire [1:0] b10 = sw[13:12];
    wire [1:0] b11 = sw[15:14];

    // =========================================================================
    // 6.  Systolic Array Core
    // =========================================================================
    wire [4:0] acc00, acc01, acc10, acc11;
    wire       done, busy;

    systolic_2x2 u_sys (
        .clk   (clk),
        .rst   (rst),
        .clk_en(clk_en),
        .a00   (a00),  .a01(a01),
        .a10   (a10),  .a11(a11),
        .b00   (b00),  .b01(b01),
        .b10   (b10),  .b11(b11),
        .start (pulse_start),
        .acc00 (acc00),
        .acc01 (acc01),
        .acc10 (acc10),
        .acc11 (acc11),
        .done  (done),
        .busy  (busy)
    );

    // =========================================================================
    // 7.  LED Assignments  -  all 16 LEDs driven by live accumulator data
    //
    //     LD[15:12]  C[0][0] = acc00
    //     LD[11:8]   C[0][1] = acc01   4-bit saturating representation of
    //     LD[7:4]    C[1][0] = acc10   each 5-bit accumulator.
    //     LD[3:0]    C[1][1] = acc11   Values 0-15 exact; 16-18 -> 1111 (all on).
    //
    //     The 7-segment display always shows exact decimal (0-18), so no
    //     information is lost - LEDs give a quick visual during pipeline stepping.
    //
    //     Example: A=B=[[2,1],[1,2]]
    //       After press 2: LD = 0100_0000_0000_0000  (acc00=4, rest 0)
    //       After press 3: LD = 0101_0000_0000_0000  (acc00=5 done, rest partial)
    //       After press 5: LD = 0101_0100_0100_0101  (5 4 4 5 - all done)
    // =========================================================================

    // Saturate a 5-bit value to 4 bits: if bit[4] is set (value >=16), return 4'hF.
    function [3:0] sat4;
        input [4:0] v;
        begin
            sat4 = v[4] ? 4'hF : v[3:0];
        end
    endfunction

    assign led = {sat4(acc00), sat4(acc01), sat4(acc10), sat4(acc11)};

    // =========================================================================
    // 8.  7-Segment Display Controller
    //
    //     Shows all four result values in decimal across the 8 digits:
    //
    //     DIG7 DIG6 | DIG5 DIG4 | DIG3 DIG2 | DIG1 DIG0
    //     C[0][0]     C[0][1]     C[1][0]     C[1][1]
    //
    //     Values range 0-18 (max = 3*3 + 3*3 = 18 with 2-bit inputs).
    //     Each pair shows up to two decimal digits with leading-zero blanking.
    //
    //     Scan rate: 2^14 cycles/digit @ 100 MHz = ~163 us/digit = ~764 Hz refresh.
    // =========================================================================

    // BCD conversion (0-18 only, fits in 5 bits)
    // Returns {tens[3:0], ones[3:0]}
    function [7:0] bcd_of;
        input [4:0] v;
        reg   [4:0] tmp;
        begin
            if (v >= 5'd10) begin
                tmp    = v - 5'd10;
                bcd_of = {4'd1, tmp[3:0]};
            end else begin
                bcd_of = {4'd0, v[3:0]};
            end
        end
    endfunction

    wire [7:0] bcd00 = bcd_of(acc00);
    wire [7:0] bcd01 = bcd_of(acc01);
    wire [7:0] bcd10 = bcd_of(acc10);
    wire [7:0] bcd11 = bcd_of(acc11);

    // 7-segment decoder (active-low, CA=a/top, CG=g/middle)
    // seg[6:0] = {CA, CB, CC, CD, CE, CF, CG}
    // digits above 9 use the blank code.
    function [6:0] seg7;
        input [3:0] d;
        begin
            case (d)
                4'd0:    seg7 = 7'b000_0001;  // 0: all on except G
                4'd1:    seg7 = 7'b100_1111;  // 1: B,C
                4'd2:    seg7 = 7'b001_0010;  // 2: A,B,D,E,G
                4'd3:    seg7 = 7'b000_0110;  // 3: A,B,C,D,G
                4'd4:    seg7 = 7'b100_1100;  // 4: B,C,F,G
                4'd5:    seg7 = 7'b010_0100;  // 5: A,C,D,F,G
                4'd6:    seg7 = 7'b010_0000;  // 6: A,C,D,E,F,G
                4'd7:    seg7 = 7'b000_1111;  // 7: A,B,C
                4'd8:    seg7 = 7'b000_0000;  // 8: all on
                4'd9:    seg7 = 7'b000_0100;  // 9: A,B,C,D,F,G
                default: seg7 = 7'b111_1111;  // blank
            endcase
        end
    endfunction

    // Scan counter
    // [SCAN_BITS+2 : SCAN_BITS] = 3-bit digit select (0-7)
    // [SCAN_BITS-1 :         0] = sub-digit free-running counter
    reg [SCAN_BITS+2:0] scan_cnt = 0;

    always @(posedge clk)
        if (rst) scan_cnt <= 0;
        else     scan_cnt <= scan_cnt + 1'd1;

    wire [2:0] digit_sel = scan_cnt[SCAN_BITS+2:SCAN_BITS];

    // Digit value for the selected position
    // Digit map:
    //   7 = tens of acc00,  6 = ones of acc00
    //   5 = tens of acc01,  4 = ones of acc01
    //   3 = tens of acc10,  2 = ones of acc10
    //   1 = tens of acc11,  0 = ones of acc11
    // Tens digit shows blank (4'd10) when zero -- leading-zero suppression.
    reg [3:0] cur_digit;

    always @(*) begin
        case (digit_sel)
            3'd7: cur_digit = (bcd00[7:4] == 4'd0) ? 4'd10 : bcd00[7:4];
            3'd6: cur_digit = bcd00[3:0];
            3'd5: cur_digit = (bcd01[7:4] == 4'd0) ? 4'd10 : bcd01[7:4];
            3'd4: cur_digit = bcd01[3:0];
            3'd3: cur_digit = (bcd10[7:4] == 4'd0) ? 4'd10 : bcd10[7:4];
            3'd2: cur_digit = bcd10[3:0];
            3'd1: cur_digit = (bcd11[7:4] == 4'd0) ? 4'd10 : bcd11[7:4];
            3'd0: cur_digit = bcd11[3:0];
            default: cur_digit = 4'd10; // blank
        endcase
    end

    // Anode select (active-LOW: pull the selected digit's anode LOW)
    reg [7:0] an_reg;

    always @(*) begin
        case (digit_sel)
            3'd0: an_reg = 8'b1111_1110;
            3'd1: an_reg = 8'b1111_1101;
            3'd2: an_reg = 8'b1111_1011;
            3'd3: an_reg = 8'b1111_0111;
            3'd4: an_reg = 8'b1110_1111;
            3'd5: an_reg = 8'b1101_1111;
            3'd6: an_reg = 8'b1011_1111;
            3'd7: an_reg = 8'b0111_1111;
            default: an_reg = 8'b1111_1111;
        endcase
    end

    assign an  = an_reg;
    assign seg = seg7(cur_digit);
    // dp = 1 (inactive) because the display uses no decimal points.
    // Vivado Synth 8-3917 'constant' warning on dp is expected and harmless.
    assign dp  = 1'b1;

endmodule

`default_nettype wire
