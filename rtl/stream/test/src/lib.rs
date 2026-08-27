#![allow(clippy::into_iter_on_ref)]

mod fifo;
mod merge;
mod split_merge;
mod stage;

#[cfg(test)]
mod tests;

use rustdv::prelude::*;

#[cfg(test)]
use rustdv_vpi_stubs as _;

rustdv::vpi_bootstrap!();

fn fail(message: impl Into<String>) -> TestError {
    TestError::new(message.into())
}

#[derive(Clone, Copy)]
struct StreamPort {
    input_valid: LogicHandle,
    input_ready: LogicHandle,
    input_payload: LogicHandle,
    output_valid: LogicHandle,
    output_ready: LogicHandle,
    output_payload: LogicHandle,
}

impl StreamPort {
    fn new(dut: &HierarchyHandle, input: &str, output: &str) -> Result<Self, HandleError> {
        Ok(Self {
            input_valid: dut.signal(&format!("{input}_valid"))?,
            input_ready: dut.signal(&format!("{input}_ready"))?,
            input_payload: dut.signal(&format!("{input}_payload"))?,
            output_valid: dut.signal(&format!("{output}_valid"))?,
            output_ready: dut.signal(&format!("{output}_ready"))?,
            output_payload: dut.signal(&format!("{output}_payload"))?,
        })
    }

    fn idle(&self) {
        self.input_valid.set_u64(0);
        self.input_payload.set_u64(0);
        self.output_ready.set_u64(0);
    }
}

async fn reset(dut: &HierarchyHandle, ports: &[StreamPort]) -> Result<LogicHandle, TestError> {
    let clk = dut.signal("clk").map_err(|e| fail(e.to_string()))?;
    let rst = dut.signal("rst").map_err(|e| fail(e.to_string()))?;
    for port in ports {
        port.idle();
    }
    rst.set_u64(1);
    let _clock = Clock::new(&clk, SimDuration::ns(10)).start();
    for _ in 0..5 {
        clk.falling_edge().await;
    }
    rst.set_u64(0);
    clk.falling_edge().await;
    Ok(clk)
}

async fn ordered_flow(
    ctx: &RustdvCtx,
    ports: &[StreamPort],
    count: usize,
) -> Result<(), TestError> {
    let clk = reset(&ctx.dut(), ports).await?;
    ordered_flow_on_clock(ctx, ports, count, &clk, true).await
}

async fn ordered_flow_on_clock(
    ctx: &RustdvCtx,
    ports: &[StreamPort],
    count: usize,
    clk: &LogicHandle,
    random_ready: bool,
) -> Result<(), TestError> {
    let mut rng = ctx.rng();
    let mut sent = vec![0usize; ports.len()];
    let mut received = vec![0usize; ports.len()];
    let mut driving = vec![false; ports.len()];
    let mut stalled: Vec<Option<u64>> = vec![None; ports.len()];

    for _cycle in 0..100_000 {
        clk.falling_edge().await;
        for (i, port) in ports.into_iter().enumerate() {
            if !driving[i] && sent[i] < count && rng.bool() {
                driving[i] = true;
            }
            port.input_valid.set_u64(driving[i] as u64);
            if driving[i] {
                port.input_payload.set_u64(sent[i] as u64);
            }
            port.output_ready
                .set_u64((!random_ready || rng.bool()) as u64);
        }
        Timer::ns(4).await;
        for (i, port) in ports.into_iter().enumerate() {
            if driving[i] && port.input_ready.is_high() {
                sent[i] += 1;
                driving[i] = false;
            }
            if stalled[i].is_some_and(|value| {
                !port.output_valid.is_high() || port.output_payload.get_u64() != Ok(value)
            }) {
                return Err(fail(format!("port {i}: output changed while stalled")));
            }
            stalled[i] = if port.output_valid.is_high() && !port.output_ready.is_high() {
                Some(
                    port.output_payload
                        .get_u64()
                        .map_err(|e| fail(e.to_string()))?,
                )
            } else {
                None
            };
            if port.output_valid.is_high() && port.output_ready.is_high() {
                let got = port
                    .output_payload
                    .get_u64()
                    .map_err(|e| fail(e.to_string()))? as usize;
                if got != received[i] {
                    return Err(fail(format!(
                        "port {i}: expected {}, got {got}",
                        received[i]
                    )));
                }
                received[i] += 1;
            }
        }
        if (&received).into_iter().all(|&n| n == count) {
            clk.rising_edge().await;
            return Ok(());
        }
    }
    Err(fail(format!(
        "flow timed out: sent={sent:?} received={received:?}"
    )))
}
