use rustdv::prelude::*;
use rustdv_utils::reset::reset;
use rustdv_utils::stream::StreamPort;

use crate::ordered_flow_on_clock;

#[rustdv::test(timeout_time = 10, timeout_unit = "ms")]
async fn stream_fifo(ctx: RustdvCtx) -> Result<(), TestError> {
    let dut = ctx.dut();
    let input = StreamPort::new(&dut, "stream_in").map_err(|e| TestError::new(e.to_string()))?;
    let output = StreamPort::new(&dut, "stream_out").map_err(|e| TestError::new(e.to_string()))?;
    input.idle_input();
    output.idle_output();
    let clk = reset(&dut).await?;

    // Pointer-addressed FIFOs promise at least DEPTH-1 usable entries.
    for value in 0..15u64 {
        clk.falling_edge().await;
        input.valid.set_u64(1);
        input.payload.set_u64(value);
        output.ready.set_u64(0);
    }
    clk.falling_edge().await;
    input.valid.set_u64(0);
    output.ready.set_u64(1);
    for expected in 0..15u64 {
        if expected != 0 {
            clk.falling_edge().await;
        }
        if !output.valid.is_high() || output.payload.get_u64() != Ok(expected) {
            return Err(TestError::new(format!(
                "fifo: expected fill value {expected}"
            )));
        }
    }
    // Start the randomized phase from a clean pointer/valid state; RAM data
    // itself need not reset because the FIFO validity state gates it.
    let rst = dut
        .signal("rst")
        .map_err(|e| TestError::new(e.to_string()))?;
    clk.falling_edge().await;
    input.idle_input();
    output.idle_output();
    rst.set_u64(1);
    for _ in 0..5 {
        clk.falling_edge().await;
    }
    rst.set_u64(0);
    ordered_flow_on_clock(&ctx, &[(input, output)], 1024, &clk, true).await
}
