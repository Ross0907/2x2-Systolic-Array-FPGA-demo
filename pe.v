// =============================================================================
// FILE        : pe.v
// DESCRIPTION : Processing Element for 2x2 Systolic Array
//
//   Each PE performs one MAC per clock-enable pulse:
//     acc = acc + (a_in × b_in)
//
//   a_in flows RIGHT  to a_out   (forwarded to PE on the right)
//   b_in flows DOWN  to  b_out   (forwarded to PE below)
//
//   INPUTS are 2-bit (values 0-3).
//   ACCUMULATOR is 5-bit (max possible = 3×3 + 3×3 = 18 = 5'b10010).
//
//   clk_en: only advances state when HIGH.
//           Driven by the debounced manual-clock button on the board.
//           One button press = one clock cycle through the systolic array.
//
//   clear:  When HIGH, acc is LOADED with a_in×b_in (not zeroed to 0).
//           This combines "clear" and "first MAC" into one cycle so that
//           PE11 (the farthest PE) completes within the 5-press budget.
//           a_out/b_out are always forwarded so downstream PEs propagate data.
// =============================================================================

module pe (
    input  wire       clk,
    input  wire       rst,
    input  wire       clk_en,   // manual clock enable - advance on each press
    input  wire       clear,    // synchronous accumulator load (start of new run)
    input  wire [1:0] a_in,     // 2-bit data from left
    input  wire [1:0] b_in,     // 2-bit data from top
    output reg  [1:0] a_out,    // forward to right PE
    output reg  [1:0] b_out,    // forward to PE below
    output reg  [4:0] acc       // 5-bit accumulator (live - shown on LEDs each step)
);

    // Wide operands to avoid truncation warnings in synthesis
    wire [4:0] product = {3'b000, a_in} * {3'b000, b_in};

    always @(posedge clk) begin
        if (rst) begin
            a_out <= 2'b00;
            b_out <= 2'b00;
            acc   <= 5'h00;
        end else if (clk_en) begin
            a_out <= a_in;
            b_out <= b_in;
            if (clear)
                acc <= product;           // load-clear: fresh start + first MAC
            else
                acc <= acc + product;     // normal accumulate
        end
    end

endmodule
