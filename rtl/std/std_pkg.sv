//!no_lint

package std_pkg;

    typedef enum logic {
        STD_CLOCK_EDGE_RISING = 'b0,
        STD_CLOCK_EDGE_FALLING = 'b1
    } std_clock_edge_t;

    typedef enum logic {
        STD_RESET_POLARITY_HIGH = 'b0,
        STD_RESET_POLARITY_LOW = 'b1
    } std_reset_polarity_t;

    typedef enum logic {
        STD_RESET_CLOCKING_SYNC = 'b0,
        STD_RESET_CLOCKING_ASYNC = 'b1
    } std_reset_clocking_t;

    typedef struct packed {
        std_clock_edge_t clock_edge;
        std_reset_polarity_t reset_polarity;
        std_reset_clocking_t reset_clocking;
    } std_clock_info_t;

    function automatic logic std_is_reset_active(
            input std_clock_info_t clk_info,
            input logic rst
    );
        if (clk_info.reset_polarity == STD_RESET_POLARITY_HIGH) begin
            return rst;
        end else begin
            return !rst;
        end
    endfunction

    function automatic logic std_get_reset(
            input std_clock_info_t clk_info,
            input logic is_active
    );
        if (clk_info.reset_polarity == STD_RESET_POLARITY_HIGH) begin
            return is_active;
        end else begin
            return !is_active;
        end
    endfunction

    typedef enum int {
        STD_TECHNOLOGY_SIMULATION = 'h0,
        STD_TECHNOLOGY_FPGA_XILINX = 'h1,
        STD_TECHNOLOGY_FPGA_INTEL = 'h2,
        STD_TECHNOLOGY_ASIC_TSMC = 'h3,
        STD_TECHNOLOGY_ASIC_INTEL = 'h4
    } std_technology_t;

endpackage
