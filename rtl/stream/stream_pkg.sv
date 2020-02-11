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

endpackage
