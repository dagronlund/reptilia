package cache_pkg;

    typedef enum logic [1:0] {
        CACHE_MESI_INVALID = 'h0,
        CACHE_MESI_SHARED = 'h1,
        CACHE_MESI_EXCLUSIVE = 'h2,
        CACHE_MESI_MODIFIED = 'h3
    } cache_mesi_state_t;

    typedef enum logic [1:0] {
        CACHE_MESI_OPERATION_SHARED = 'h0,
        CACHE_MESI_OPERATION_EXCLUSIVE = 'h1,
        CACHE_MESI_OPERATION_EXCLUSIVE_DATA = 'h2,
        CACHE_MESI_OPERATION_EVICTION = 'h3
    } cache_mesi_operation_t;

    typedef struct packed {
        cache_mesi_operation_t op;
    } cache_mesi_request_t;

    typedef struct packed {
        cache_mesi_operation_t op;
    } cache_mesi_response_t;

    function automatic logic cache_is_mesi_valid(
        input cache_mesi_state_t state
    );
        return (state == CACHE_MESI_SHARED) || (state == CACHE_MESI_EXCLUSIVE) || (state == CACHE_MESI_MODIFIED);
    endfunction

    function automatic logic cache_is_mesi_dirty(
        input cache_mesi_state_t state
    );
        return (state == CACHE_MESI_MODIFIED);
    endfunction

endpackage
