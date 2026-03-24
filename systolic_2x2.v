// =============================================================================
// FILE        : systolic_2x2.v
// DESCRIPTION : 2x2 Systolic Array - C = A × B  (2-bit elements, 5-bit results)
//
//   PE grid:
//            col0        col1
//   row0  [PE(0,0)] -> [PE(0,1)]
//             |            |
//   row1  [PE(1,0)] -> [PE(1,1)]
//
//   INPUTS: 2-bit matrix elements (values 0-3)
//   OUTPUT: 5-bit PE accumulators (live, update after each clk_en pulse)
//
//     when clear=1:  acc <= a_in × b_in   (clear + first MAC in one cycle)
//     when clear=0:  acc <= acc + a_in × b_in
//
//   This allows the state machine to send clear=1 together with the first
//   skewed data, so PE11 (which sits 2 hops away) gets its second product
//   during the FLUSH state and everything completes in exactly 5 presses.
//
//   Pipeline schedule (what PEs SEE on each press):
//   
//   Press  State(current)  PE00                  PE01       PE10       PE11
//     1    IDLE            feeds=0, clear=0      -          -          -
//     2    CY1             clear+a00×b00         clear+0×0  clear+0×0  clear+0×0
//     3    CY2             acc+=a01×b10(done!)   acc+=a00×b01  acc+=a10×b00  acc+=0
//     4    CY3             acc+=0                acc+=a01×b11(done)  acc+=a11×b10(done)  acc+=a10×b01
//     5    FLUSH           acc+=0                acc+=0     acc+=0     acc+=a11×b11(done!)
//     (DONE sets done=1, results stable)
//
//   Results after 5 presses:
//     acc00 = a00×b00 + a01×b10 = C[0][0]  
//     acc01 = a00×b01 + a01×b11 = C[0][1]  
//     acc10 = a10×b00 + a11×b10 = C[1][0]  
//     acc11 = a10×b01 + a11×b11 = C[1][1]  
// =============================================================================

module systolic_2x2 (
    input  wire       clk,
    input  wire       rst,
    input  wire       clk_en,   // manual clock enable

    // Matrix A elements (2-bit each)
    input  wire [1:0] a00, a01,
    input  wire [1:0] a10, a11,

    // Matrix B elements (2-bit each)
    input  wire [1:0] b00, b01,
    input  wire [1:0] b10, b11,

    // Control
    input  wire       start,    // level - assert then press clock to begin

    // Live accumulator outputs (updated after each clk_en, shown on LEDs)
    output wire [4:0] acc00,
    output wire [4:0] acc01,
    output wire [4:0] acc10,
    output wire [4:0] acc11,

    // Status
    output reg        done,     // pulses high for one clk_en period when complete
    output reg        busy      // high during computation
);

    // Internal wires (PE-to-PE data paths)
    wire [1:0] a00_to_01, a10_to_11;
    wire [1:0] b00_to_10, b01_to_11;

    // Feed registers (skewed inputs to the PE grid)
    reg [1:0] feed_a0, feed_a1;
    reg [1:0] feed_b0, feed_b1;
    reg       clear_pe;

    // State machine encoding
    localparam IDLE  = 3'd0;
    localparam CY1   = 3'd1;   // clear_pe=1, feed a00/b00 (first column/row)
    localparam CY2   = 3'd2;   // feed diagonal: a01/a10, b10/b01
    localparam CY3   = 3'd3;   // feed tail: a11/b11 to col1/row1 feeds
    localparam FLUSH = 3'd4;   // all feeds=0; PE11 completes; done=1; return to IDLE

    reg [2:0] state;
    // Start latch
    //   Captures the START level signal so the user can press BTN_START and
    //   then press BTN_CLK independently without losing the start request.
    reg start_held;

    always @(posedge clk) begin
        if (rst)
            start_held <= 1'b0;
        else if (start)
            start_held <= 1'b1;
        else if (clk_en && state == IDLE && start_held)
            start_held <= 1'b0;    // consumed - will transition to CY1 this edge
    end

    // State machine  (advances only on clk_en)
    //
    //  The state register holds what was SET LAST cycle.
    //  PEs see the state's registered outputs on the CURRENT clk_en edge.
    //  So the mapping is:
    //    After IDLE -> CY1 transition (press 1): PEs saw IDLE outputs (clear=0, feeds=0)
    //    After CY1 -> CY2  transition (press 2): PEs saw CY1  outputs (clear=1, feed=a00/b00)
    //    etc.
    //
    //  This means:
    //    Press 1 (IDLE): acc unchanged (=0 after reset)     → LED=0000 ✓
    //    Press 2 (CY1) : acc00 = a00×b00                   → LED=a00×b00 ✓
    //    Press 3 (CY2) : acc00 += a01×b10 → DONE           → LED=C[0][0] ✓
    //    Press 4 (CY3) : PE01,PE10 finish; PE11 first MAC   → ...
    //    Press 5 (FLUSH): PE11 gets a11×b11 → ALL DONE     → LED=C[x][x] ✓

    always @(posedge clk) begin
        if (rst) begin
            state    <= IDLE;
            busy     <= 1'b0;
            done     <= 1'b0;
            clear_pe <= 1'b0;
            feed_a0  <= 2'b00;
            feed_a1  <= 2'b00;
            feed_b0  <= 2'b00;
            feed_b1  <= 2'b00;
        end else if (clk_en) begin
            done     <= 1'b0;   // default
            clear_pe <= 1'b0;   // default

            case (state)
                //   Waiting for START
                IDLE: begin
                    busy    <= 1'b0;
                    feed_a0 <= 2'b00;  feed_a1 <= 2'b00;
                    feed_b0 <= 2'b00;  feed_b1 <= 2'b00;
                    if (start_held) begin
                        state    <= CY1;
                        busy     <= 1'b1;
                        // Set clear=1 AND first data simultaneously.
                        // PEs will see this on press #2 (next clk_en).
                        // clear+first-data in one cycle = PE00 gets a00×b00 on press 2.
                        clear_pe <= 1'b1;
                        feed_a0  <= a00;   // column 0 feed → PE(row0)
                        feed_a1  <= 2'b00; // column 1 feed → PE(row1), skewed 1 cycle
                        feed_b0  <= b00;   // row 0 feed → PE(col0)
                        feed_b1  <= 2'b00; // row 1 feed → PE(col1), skewed 1 cycle
                    end
                end

                //   Cycle 1: PE sees clear+a00×b00
                //   Press #2: acc00 = a00×b00; others = 0×0 (cleared)
                CY1: begin
                    clear_pe <= 1'b0;
                    feed_a0  <= a01;   // diagonal: row0 gets col1 element
                    feed_a1  <= a10;   // diagonal: row1 gets col0 element (1 cycle late)
                    feed_b0  <= b10;   // diagonal: col0 gets row1 element
                    feed_b1  <= b01;   // diagonal: col1 gets row0 element (1 cycle late)
                    state    <= CY2;
                end

                //   Cycle 2: PE sees a01/a10, b10/b01 
                //   Press #3: acc00 += a01×b10 → DONE  (C[0][0] complete)
                //             acc01 = a00×b01 (first product, via PE00→PE01)
                //             acc10 = a10×b00 (first product, via PE00→PE10)
                CY2: begin
                    feed_a0  <= 2'b00;  // no more input to col0 feeds
                    feed_a1  <= a11;    // tail: col1 row1 element
                    feed_b0  <= 2'b00;  // no more input to row0 feeds
                    feed_b1  <= b11;    // tail: row1 col1 element
                    state    <= CY3;
                end

                //   Cycle 3: PE sees 0/a11, 0/b11 
                //   Press #4: acc01 += a01×b11 -> DONE  (C[0][1] complete)
                //             acc10 += a11×b10 -> DONE  (C[1][0] complete)
                //             acc11  = a10×b01  (first product via forwarded outputs)
                CY3: begin
                    feed_a0 <= 2'b00;  feed_a1 <= 2'b00;
                    feed_b0 <= 2'b00;  feed_b1 <= 2'b00;
                    state   <= FLUSH;
                end

                //   Cycle 4 (FLUSH): PE11 sees forwarded a11/b11
                //   Press #5: acc11 += a11×b11 -> ALL DONE  (C[1][1] complete!)
                //   done pulses HIGH this cycle; state returns to IDLE immediately.
                //   After press #5 the state machine is back in IDLE, so a new
                //   computation can start without needing a reset between runs.
                FLUSH: begin
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

    // PEs
    pe pe00 (
        .clk   (clk),     .rst   (rst),
        .clk_en(clk_en),  .clear (clear_pe),
        .a_in  (feed_a0), .b_in  (feed_b0),
        .a_out (a00_to_01),
        .b_out (b00_to_10),
        .acc   (acc00)
    );

    pe pe01 (
        .clk   (clk),        .rst   (rst),
        .clk_en(clk_en),     .clear (clear_pe),
        .a_in  (a00_to_01),  .b_in  (feed_b1),
        .a_out (),
        .b_out (b01_to_11),
        .acc   (acc01)
    );

    pe pe10 (
        .clk   (clk),       .rst   (rst),
        .clk_en(clk_en),    .clear (clear_pe),
        .a_in  (feed_a1),   .b_in  (b00_to_10),
        .a_out (a10_to_11),
        .b_out (),
        .acc   (acc10)
    );

    //   a_in comes from PE(1,0).a_out (carries a10 then a11)
    //   b_in comes from PE(0,1).b_out (carries b01 then b11)
    //   PE11 is 2 hops from the inputs so it gets data 2 cycles after PE00.
    //   With the load-clear PE, its accumulation completes on press #5 (FLUSH).
    pe pe11 (
        .clk   (clk),        .rst   (rst),
        .clk_en(clk_en),     .clear (clear_pe),
        .a_in  (a10_to_11),  .b_in  (b01_to_11),
        .a_out (),
        .b_out (),
        .acc   (acc11)
    );

endmodule
