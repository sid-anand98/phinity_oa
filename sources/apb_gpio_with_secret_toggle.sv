`timescale 1ns/1ps

module apb_gpio_with_secret_toggle (
    input  logic        pclk,
    input  logic        presetn,   // active-low synchronous reset
    input  logic        psel,
    input  logic        penable,
    input  logic        pwrite,
    input  logic [31:0] paddr,
    input  logic [31:0] pwdata,
    output logic [31:0] prdata,
    output logic        pready,
    output logic        secret_pin
);

    
    logic do_write, do_read;
    assign do_write = psel & penable & pwrite;
    assign do_read  = psel & penable & ~pwrite;

    
    logic [7:0]  gpio_reg;
    logic        secret_reg;

    typedef enum logic [1:0] { IDLE = 2'b00, S1 = 2'b01, S2 = 2'b10 } seq_state_t;
    seq_state_t seq_state;

    logic [31:0] cycle_cnt;   // counts cycles between strobes
    logic [7:0]  last_val;    // last written value in sequence
    logic        toggle_req;  // toggle secret next cycle

    assign pready = 1'b1;
    assign prdata = {24'd0, gpio_reg};
    assign secret_pin = secret_reg;

    // ------------------------------------------------------------------
    // Allowed even values function
    // ------------------------------------------------------------------
    function automatic logic allowed_even(input logic [7:0] v);
        begin
            allowed_even = (v == 8'd0) || (v == 8'd2) || (v == 8'd4) ||
                           (v == 8'd6) || (v == 8'd8) || (v == 8'd10);
        end
    endfunction

    // ------------------------------------------------------------------
    // Synchronous logic
    // ------------------------------------------------------------------
    always_ff @(posedge pclk) begin
        if (!presetn) begin
            gpio_reg   <= 8'd0;
            secret_reg <= 1'b0;
            seq_state  <= IDLE;
            cycle_cnt  <= 32'd0;
            last_val   <= 8'd0;
            toggle_req <= 1'b0;
        end else begin
            // Apply toggle one cycle after success
            if (toggle_req) begin
                secret_reg <= ~secret_reg;
                toggle_req <= 1'b0;
            end

            // Normal GPIO write
            if (do_write && (paddr == 32'h0))
                gpio_reg <= pwdata[7:0];

            // Abort sequence if read occurs or write to other address
            if (do_read || (do_write && paddr != 32'h0)) begin
                seq_state <= IDLE;
                cycle_cnt <= 32'd0;
            end else begin
                // Sequence FSM
                case (seq_state)
                    IDLE: begin
                        if (do_write && allowed_even(pwdata[7:0])) begin
                            seq_state <= S1;
                            last_val  <= pwdata[7:0];
                            cycle_cnt <= 32'd0;
                        end
                    end

                    S1: begin
                        cycle_cnt <= cycle_cnt + 1;
                        if (cycle_cnt > 32'd3) begin
                            seq_state <= IDLE;
                            cycle_cnt <= 32'd0;
                        end else if (do_write && allowed_even(pwdata[7:0]) && pwdata[7:0] > last_val && cycle_cnt == 32'd3) begin
                            seq_state <= S2;
                            last_val  <= pwdata[7:0];
                            cycle_cnt <= 32'd0;
                        end
                    end

                    S2: begin
                        cycle_cnt <= cycle_cnt + 1;
                        if (cycle_cnt > 32'd3) begin
                            seq_state <= IDLE;
                            cycle_cnt <= 32'd0;
                        end else if (do_write && allowed_even(pwdata[7:0]) && pwdata[7:0] > last_val && cycle_cnt == 32'd3) begin
                            toggle_req <= 1'b1;
                            seq_state  <= IDLE;
                            cycle_cnt  <= 32'd0;
                        end
                    end

                    default: begin
                        seq_state <= IDLE;
                        cycle_cnt <= 32'd0;
                    end
                endcase
            end
        end
    end

endmodule
