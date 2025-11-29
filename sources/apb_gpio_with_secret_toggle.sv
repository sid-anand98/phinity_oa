`timescale 1ns/1ps

module apb_gpio_with_secret_toggle (
    input  logic        pclk,
    input  logic        presetn,
    input  logic        psel,
    input  logic        penable,
    input  logic        pwrite,
    input  logic [31:0] paddr,
    input  logic [31:0] pwdata,
    output logic [31:0] prdata,
    output logic        pready,
    output logic        secret_pin
);
    
    logic do_write = 1'b0;
    logic do_read  = 1'b0;

    always_comb begin
        do_write = psel & penable & pwrite;
        do_read  = psel & penable & ~pwrite;
    end

    // ------------------------------------------------------------------
    // State / registers
    // ------------------------------------------------------------------
    typedef enum logic [1:0] {
        IDLE = 2'b00,
        S1   = 2'b01,
        S2   = 2'b10
    } seq_state_t;

    seq_state_t seq_state;
    logic [7:0]  gpio_reg;
    logic        secret_reg;
    logic [7:0]  last_val;
    logic [31:0] cycle_cnt;   // counts idle cycles between writes
    logic        toggle_req;

    assign pready     = 1'b1;
    assign prdata     = {24'd0, gpio_reg};
    assign secret_pin = secret_reg;

    // Allowed write values
    function automatic logic allowed_even(input logic [7:0] v);
        return (v == 8'd0) || (v == 8'd2) || (v == 8'd4) ||
               (v == 8'd6) || (v == 8'd8) || (v == 8'd10);
    endfunction

    // ------------------------------------------------------------------
    // Main sequential block
    // ------------------------------------------------------------------
    always_ff @(posedge pclk) begin
        if (!presetn) begin
            gpio_reg   <= 8'd0;
            secret_reg <= 1'b0;
            seq_state  <= IDLE;
            last_val   <= 8'd0;
            cycle_cnt  <= 32'd0;
            toggle_req <= 1'b0;
        end else begin
            // Apply toggle one cycle after success
            if (toggle_req) begin
                secret_reg <= ~secret_reg;
                toggle_req <= 1'b0;
            end

            // Normal GPIO operation
            if (do_write && (paddr == 32'h0))
                gpio_reg <= pwdata[7:0];

            // Default next counter value
            logic [31:0] next_cnt = cycle_cnt;

            // Immediate abort on read or wrong address write
            if (do_read || (do_write && paddr != 32'h0)) begin
                seq_state <= IDLE;
                next_cnt  <= 32'd0;
            end else begin
                case (seq_state)
                    // --------------------------------------------------
                    IDLE: begin
                        next_cnt <= 32'd0;
                        if (do_write && allowed_even(pwdata[7:0])) begin
                            seq_state <= S1;
                            last_val  <= pwdata[7:0];
                        end
                    end

                    // --------------------------------------------------
                    S1: begin
                        if (do_write) begin
                            if (!allowed_even(pwdata[7:0]) ||
                                (pwdata[7:0] <= last_val)     ||
                                (cycle_cnt != 32'd2)) begin
                                // Wrong value or wrong timing → abort immediately
                                seq_state <= IDLE;
                                next_cnt  <= 32'd0;
                            end else begin
                                // Correct second write exactly 3 cycles later
                                seq_state <= S2;
                                last_val  <= pwdata[7:0];
                                next_cnt  <= 32'd0;
                            end
                        end else if (cycle_cnt == 32'd2) begin
                            // Timeout with no write
                            seq_state <= IDLE;
                            next_cnt  <= 32'd0;
                        end else begin
                            next_cnt <= cycle_cnt + 1;
                        end
                    end

                    // --------------------------------------------------
                    S2: begin
                        if (do_write) begin
                            if (!allowed_even(pwdata[7:0]) ||
                                (pwdata[7:0] <= last_val)     ||
                                (cycle_cnt != 32'd2)) begin
                                seq_state <= IDLE;
                                next_cnt  <= 32'd0;
                            end else begin
                                // Full sequence satisfied
                                toggle_req <= 1'b1;
                                seq_state  <= IDLE;
                                next_cnt   <= 32'd0;
                            end
                        end else if (cycle_cnt == 32'd2) begin
                            seq_state <= IDLE;
                            next_cnt  <= 32'd0;
                        end else begin
                            next_cnt <= cycle_cnt + 1;
                        end
                    end

                    default: begin
                        seq_state <= IDLE;
                        next_cnt  <= 32'd0;
                    end
                endcase
            end

            cycle_cnt <= next_cnt;
        end
    end
endmodule
