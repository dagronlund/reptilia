package stream_pkg;

    typedef enum logic [1:0] {
        STREAM_PIPELINE_MODE_TRANSPARENT = 'h0,
        STREAM_PIPELINE_MODE_REGISTERED = 'h1,
        STREAM_PIPELINE_MODE_BUFFERED = 'h2,
        STREAM_PIPELINE_MODE_ELASTIC = 'h3
    } stream_pipeline_mode_t;

endpackage
