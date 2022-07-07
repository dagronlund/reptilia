//!no_lint

package stream_pkg;

    typedef enum logic [1:0] {
        STREAM_PIPELINE_MODE_TRANSPARENT = 'h0,
        STREAM_PIPELINE_MODE_REGISTERED = 'h1,
        STREAM_PIPELINE_MODE_BUFFERED = 'h2,
        STREAM_PIPELINE_MODE_ELASTIC = 'h3
    } stream_pipeline_mode_t;

    typedef enum logic {
        STREAM_SELECT_MODE_ROUND_ROBIN = 'h0,
        STREAM_SELECT_MODE_ORDERED = 'h1
    } stream_select_mode_t;

    typedef enum logic [1:0] {
        STREAM_FIFO_MODE_COMBINATIONAL = 'h0,
        STREAM_FIFO_MODE_COMBINATIONAL_REGISTERED = 'h1,
        STREAM_FIFO_MODE_SEQUENTIAL = 'h2,
        STREAM_FIFO_MODE_SEQUENTIAL_REGISTERED = 'h3
    } stream_fifo_mode_t;

    typedef enum logic {
        STREAM_FIFO_ADDRESS_MODE_POINTERS = 'h0,
        STREAM_FIFO_ADDRESS_MODE_FLAGS = 'h1
    } stream_fifo_address_mode_t;

    typedef struct packed {
        logic [7:0] valid_input;
        logic [7:0] ready_output;
        logic [7:0] consume;
        logic [7:0] produce;
    } stream_controller8_input_t;

    typedef struct packed {
        logic [7:0] ready_input;
        logic [7:0] valid_output;
        logic       enable;
    } stream_controller8_output_t;

    function automatic stream_controller8_output_t stream_controller8(
        input stream_controller8_input_t in
    );
        logic output_enable = '1;
        logic input_enable = '1;
        logic [7:0] output_enables = '1;
        logic [7:0] input_enables = '1;
        stream_controller8_output_t out = '{default: 'b0};

        for (int i = 0; i < 8; i++) begin
            // Enable if all outputs are either not being produced or ready
            output_enable &= (!in.produce[i]) || (in.ready_output[i]);
            // Enable if all inputs are either not being consumed or valid
            input_enable  &= (!in.consume[i]) || (in.valid_input[i]);
            for (int j = 0; j < 8; j++) begin
                if (i != j) begin
                    output_enables[j] &= (!in.produce[i]) || (in.ready_output[i]);
                    input_enables[j]  &= (!in.consume[i]) || (in.valid_input[i]);
                end
            end
        end

        for (int i = 0; i < 8; i++) begin
            // Set output valid signals if enabled and being produced
            out.valid_output[i] = in.produce[i] && output_enables[i] && input_enable;
            // Set input ready signals if enabled and being consumed
            out.ready_input[i]  = in.consume[i] && input_enables[i]  && output_enable;
        end

        // Collapse individual enable signals for primary enable
        out.enable = output_enable && input_enable;

        return out;
    endfunction

endpackage
