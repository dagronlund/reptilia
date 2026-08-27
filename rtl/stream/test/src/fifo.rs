use rustdv::prelude::*;

use crate::{StreamPort, fail, ordered_flow_on_clock, reset};

#[rustdv::test(timeout_time = 10, timeout_unit = "ms")]
async fn stream_fifo(ctx: RustdvCtx) -> Result<(), TestError> {
    let dut = ctx.dut();
    let port = StreamPort::new(&dut, "s", "o").map_err(|e| fail(e.to_string()))?;
    let clk = reset(&dut, &[port]).await?;

    // Pointer-addressed FIFOs promise at least DEPTH-1 usable entries.
    for value in 0..15u64 {
        clk.falling_edge().await;
        port.input_valid.set_u64(1);
        port.input_payload.set_u64(value);
        port.output_ready.set_u64(0);
    }
    clk.falling_edge().await;
    port.input_valid.set_u64(0);
    port.output_ready.set_u64(1);
    for expected in 0..15u64 {
        if expected != 0 {
            clk.falling_edge().await;
        }
        if !port.output_valid.is_high() || port.output_payload.get_u64() != Ok(expected) {
            return Err(fail(format!("fifo: expected fill value {expected}")));
        }
    }
    // Start the randomized phase from a clean pointer/valid state; RAM data
    // itself need not reset because the FIFO validity state gates it.
    let rst = dut.signal("rst").map_err(|e| fail(e.to_string()))?;
    clk.falling_edge().await;
    port.idle();
    rst.set_u64(1);
    for _ in 0..5 {
        clk.falling_edge().await;
    }
    rst.set_u64(0);
    ordered_flow_on_clock(&ctx, &[port], 1024, &clk, true).await
}
