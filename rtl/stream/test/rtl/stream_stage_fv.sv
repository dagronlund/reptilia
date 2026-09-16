module stream_stage_formal (
    input wire       clk,
    input wire       rst,
    input wire       in_valid,
    input wire [3:0] in_payload,
    input wire       out_ready
);
    stream_intf #(
        .T (logic [3:0])
    ) stream_in (
        .clk,
        .rst
    );
    stream_intf #(
        .T (logic [3:0])
    ) stream_out (
        .clk,
        .rst
    );

    assign stream_in.valid = in_valid;
    assign stream_in.payload = in_payload;
    assign stream_out.ready = out_ready;

    stream_stage #(
        .PIPELINE_MODE (stream_pkg::STREAM_PIPELINE_MODE_REGISTERED),
        .T             (logic [3:0])
    ) dut (
        .clk,
        .rst,
        .stream_in,
        .stream_out
    );

    wire push    = stream_in.valid && stream_in.ready;
    wire pop     = stream_out.valid && stream_out.ready;
    wire stalled = stream_out.valid && !stream_out.ready;

    logic       past_valid = 1'b0;
    logic       occupied;
    logic [3:0] expected_payload;
    logic [1:0] stall_history;
    logic       saw_two_cycle_stall;

    always @(posedge clk) begin
        past_valid <= 1'b1;

        // One reset clock establishes state; all later cycles are unconstrained
        // traffic with reset inactive. In particular, ready can stall forever.
        assume (rst == !past_valid);
        if (past_valid && !rst && !$past(rst)) begin
            if ($past(stream_in.valid && !stream_in.ready)) begin
                assume (stream_in.valid);
                assume (stream_in.payload == $past(stream_in.payload));
            end
        end

        if (rst) begin
            occupied            <= 1'b0;
            stall_history       <= '0;
            saw_two_cycle_stall <= 1'b0;
        end else begin
            // Reference queue: replacing a consumed entry leaves it occupied.
            case ({push, pop})
                2'b10:   occupied <= 1'b1;
                2'b01:   occupied <= 1'b0;
                default: ;
            endcase
            if (push)
                expected_payload <= stream_in.payload;

            stall_history <= {stall_history[0], stalled};
            if (&stall_history)
                saw_two_cycle_stall <= 1'b1;
        end

        if (past_valid && !rst) begin
            assert (stream_out.valid == occupied);
            if (stream_out.valid)
                assert (stream_out.payload == expected_payload);
            assert (!pop || occupied);
            assert (!push || !occupied || pop);
            // A free slot or simultaneous consumption must permit acceptance.
            assert (stream_in.ready == (!occupied || stream_out.ready));

            if ($past(rst))
                assert (!stream_out.valid);
            if (!$past(rst) && $past(stalled)) begin
                assert (stream_out.valid);
                assert (stream_out.payload == $past(stream_out.payload));
            end

            cover (!occupied && push);
            cover (push && pop && stream_in.payload != stream_out.payload);
            cover (&stall_history && pop);
            cover (saw_two_cycle_stall && !occupied);
        end
    end
    // Concurrent SVA versions complement the immediate checks above.
    // |-> checks this sample; |=> checks the following clock sample.
    sva_reset: assume property (@(posedge clk) rst == !past_valid);
    sva_producer_stability: assume property (
        @(posedge clk) disable iff(rst) stream_in.valid && !stream_in.ready
                                           |=> stream_in.valid && $stable(stream_in.payload)
    );

    sva_reset_empty: assert property (@(posedge clk) rst |=> !stream_out.valid);
    sva_valid: assert property (@(posedge clk) disable iff(rst) past_valid |-> stream_out.valid == occupied);
    sva_payload: assert property (
        @(posedge clk) disable iff(rst) past_valid && stream_out.valid |-> stream_out.payload == expected_payload
    );
    sva_no_underflow: assert property (@(posedge clk) disable iff(rst) past_valid && pop |-> occupied);
    sva_no_overflow: assert property (@(posedge clk) disable iff(rst) past_valid && push |-> !occupied || pop);
    sva_ready: assert property (
        @(posedge clk) disable iff(rst) past_valid |-> stream_in.ready == (!occupied || stream_out.ready)
    );
    sva_output_stability: assert property (
        @(posedge clk) disable iff(rst) past_valid && stalled |=> stream_out.valid && $stable(stream_out.payload)
    );
    sva_accepted_payload: assert property (
        @(posedge clk) disable iff(rst) past_valid && push
                                           |=> stream_out.valid && stream_out.payload == $past(stream_in.payload)
    );

    sva_accept: cover property (@(posedge clk) disable iff(rst) past_valid && !occupied && push);
    sva_replace: cover property (@(posedge clk) disable iff(rst) past_valid && push && pop
                                                                    && stream_in.payload != stream_out.payload);
    sva_stall_then_pop: cover property (@(posedge clk) disable iff(rst)(past_valid && stalled)[*2] ## 1 pop);
    sva_fill_stall_drain: cover property (@(posedge clk) disable iff(rst)(past_valid && !occupied
                                                                              && push) ## 1 stalled[*2] ## 1 (pop && !push) ## 1 !occupied);
endmodule
