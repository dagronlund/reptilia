use rustdv::prelude::*;

use crate::{StreamPort, fail, ordered_flow};

#[rustdv::test(timeout_time = 5, timeout_unit = "ms")]
async fn stream_stage(ctx: RustdvCtx) -> Result<(), TestError> {
    let dut = ctx.dut();
    let port = StreamPort::new(&dut, "s", "o").map_err(|e| fail(e.to_string()))?;
    ordered_flow(&ctx, &[port], 1024).await
}
