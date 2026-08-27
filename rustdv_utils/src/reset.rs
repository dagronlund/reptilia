use rustdv::prelude::*;

/// Resets the DUT by asserting the reset signal for a few clock cycles and then
/// deasserting it
pub async fn reset(dut: &HierarchyHandle) -> Result<LogicHandle, TestError> {
    let clk = dut
        .signal("clk")
        .map_err(|error| TestError::new(error.to_string()))?;
    let rst = dut
        .signal("rst")
        .map_err(|error| TestError::new(error.to_string()))?;
    rst.set_u64(1);
    let _clock = Clock::new(&clk, SimDuration::ns(10)).start();
    for _ in 0..5 {
        clk.falling_edge().await;
    }
    rst.set_u64(0);
    clk.falling_edge().await;
    Ok(clk)
}
