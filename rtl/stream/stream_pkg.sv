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

endpackage
