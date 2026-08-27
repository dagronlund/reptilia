use rustdv::prelude::*;
use rustdv_utils::stream::StreamPort;

use crate::ordered_flow;

#[rustdv::test(timeout_time = 5, timeout_unit = "ms")]
async fn stream_stage(ctx: RustdvCtx) -> Result<(), TestError> {
    let dut = ctx.dut();
    let input = StreamPort::new(&dut, "stream_in").map_err(|e| TestError::new(e.to_string()))?;
    let output = StreamPort::new(&dut, "stream_out").map_err(|e| TestError::new(e.to_string()))?;
    ordered_flow(&ctx, &[(input, output)], 1024).await
}
