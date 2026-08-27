use rustdv::prelude::*;

use crate::{StreamInputPort, StreamOutputPort, ordered_flow};

#[rustdv::test(timeout_time = 5, timeout_unit = "ms")]
async fn stream_stage(ctx: RustdvCtx) -> Result<(), TestError> {
    let dut = ctx.dut();
    let input =
        StreamInputPort::new(&dut, "stream_in").map_err(|e| TestError::new(e.to_string()))?;
    let output =
        StreamOutputPort::new(&dut, "stream_out").map_err(|e| TestError::new(e.to_string()))?;
    ordered_flow(&ctx, &[(input, output)], 1024).await
}
