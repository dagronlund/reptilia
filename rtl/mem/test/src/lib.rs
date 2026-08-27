mod double;
mod read_write;
mod single;
mod split_merge;

#[cfg(test)]
mod tests;

use rustdv::prelude::*;
use rustdv_utils::mem::{MemPort, MemTransaction};
use rustdv_utils::reset::reset;

#[cfg(test)]
use rustdv_vpi_stubs as _;

rustdv::vpi_bootstrap!();

async fn start(
    dut: &HierarchyHandle,
    ports: &[(MemPort, MemPort)],
) -> Result<LogicHandle, TestError> {
    for (input, output) in ports {
        input.idle_input();
        output.idle_output();
    }
    reset(dut).await
}

async fn transact(
    clk: &LogicHandle,
    input: &MemPort,
    output: &MemPort,
    t: MemTransaction,
    expected: Option<(u32, u8, bool)>,
    rng: &mut Rng,
) -> Result<(), TestError> {
    let mut accepted = false;
    for _ in 0..1000 {
        clk.falling_edge().await;
        input.drive(t);
        input.valid.set_u64((!accepted) as u64);
        output.ready.set_u64(rng.bool() as u64);
        Timer::ns(4).await;
        if !accepted && input.ready.is_high() {
            accepted = true;
        }
        if output.valid.is_high() && output.ready.is_high() {
            let Some((data, id, last)) = expected else {
                return Err(TestError::new("unexpected memory response"));
            };
            if output.data.get_u64() != Ok(data as u64)
                || output.id.get_u64() != Ok(id as u64)
                || output.last.is_high() != last
            {
                return Err(TestError::new(format!(
                    "memory response mismatch at {}",
                    t.addr
                )));
            }
            clk.rising_edge().await;
            return Ok(());
        }
        if accepted && expected.is_none() {
            clk.rising_edge().await;
            return Ok(());
        }
    }
    Err(TestError::new(format!(
        "memory transaction timed out at {}",
        t.addr
    )))
}
