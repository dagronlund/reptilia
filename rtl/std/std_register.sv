`timescale 1ns/1ps

//!import std/std_pkg

// I hope you hate how verbose this is just as much as I do
module std_register 
    import std_pkg.*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter type T = logic,
    parameter T RESET_VECTOR = 'b0
)(
    input wire clk, 
    input wire rst,

    input wire enable = 'b0,
    input T next = 'b0,
    output T value
);

    // Maybe this will be supported by synthesis?
    logic rst_actual;
    assign rst_actual = std_is_reset_active(CLOCK_INFO, rst);

    generate
    if (CLOCK_INFO.clock_edge == STD_CLOCK_EDGE_RISING) begin
        if (CLOCK_INFO.reset_clocking == STD_RESET_CLOCKING_SYNC) begin
            if (CLOCK_INFO.reset_polarity == STD_RESET_POLARITY_HIGH) begin

                // Rising Edge, Synchronous, Active High
                always_ff @(posedge clk) begin
                    if (rst) begin
                        value <= RESET_VECTOR;
                    end else if (enable) begin
                        value <= next;
                    end
                end

            end else begin // STD_RESET_POLARITY_LOW

                // Rising Edge, Synchronous, Active Low
                always_ff @(posedge clk) begin
                    if (~rst) begin
                        value <= RESET_VECTOR;
                    end else if (enable) begin
                        value <= next;
                    end
                end

            end
        end else begin // STD_RESET_CLOCKING_ASYNC
            if (CLOCK_INFO.reset_polarity == STD_RESET_POLARITY_HIGH) begin

                // Rising Edge, Asynchronous, Active High
                always_ff @(posedge clk or posedge rst) begin
                    if (rst) begin
                        value <= RESET_VECTOR;
                    end else if (enable) begin
                        value <= next;
                    end
                end

            end else begin // STD_RESET_POLARITY_LOW

                // Rising Edge, Asynchronous, Active Low
                always_ff @(posedge clk or negedge rst) begin
                    if (~rst) begin
                        value <= RESET_VECTOR;
                    end else if (enable) begin
                        value <= next;
                    end
                end

            end
        end
    end else begin // STD_CLOCK_EDGE_FALLING
        if (CLOCK_INFO.reset_clocking == STD_RESET_CLOCKING_SYNC) begin
            if (CLOCK_INFO.reset_polarity == STD_RESET_POLARITY_HIGH) begin

                // Falling Edge, Synchronous, Active High
                always_ff @(negedge clk) begin
                    if (rst) begin
                        value <= RESET_VECTOR;
                    end else if (enable) begin
                        value <= next;
                    end
                end

            end else begin // STD_RESET_POLARITY_LOW

                // Falling Edge, Synchronous, Active Low
                always_ff @(negedge clk) begin
                    if (~rst) begin
                        value <= RESET_VECTOR;
                    end else if (enable) begin
                        value <= next;
                    end
                end

            end
        end else begin // STD_RESET_CLOCKING_ASYNC
            if (CLOCK_INFO.reset_polarity == STD_RESET_POLARITY_HIGH) begin

                // Falling Edge, Asynchronous, Active High
                always_ff @(negedge clk or posedge rst) begin
                    if (rst) begin
                        value <= RESET_VECTOR;
                    end else if (enable) begin
                        value <= next;
                    end
                end

            end else begin // STD_RESET_POLARITY_LOW

                // Falling Edge, Asynchronous, Active Low
                always_ff @(negedge clk or negedge rst) begin
                    if (~rst) begin
                        value <= RESET_VECTOR;
                    end else if (enable) begin
                        value <= next;
                    end
                end

            end
        end
    end

endmodule
