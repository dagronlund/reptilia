mod fifo;
mod merge;
mod split_merge;
mod stage;

#[cfg(test)]
mod tests;

use rustdv::prelude::*;
use rustdv_utils::reset::reset;
use rustdv_utils::stream::StreamPort;

#[cfg(test)]
use rustdv_vpi_stubs as _;

rustdv::vpi_bootstrap!();

fn idle_ports(ports: &[(StreamPort, StreamPort)]) {
    for (input, output) in ports {
        input.idle_input();
        output.idle_output();
    }
}

async fn ordered_flow(
    ctx: &RustdvCtx,
    ports: &[(StreamPort, StreamPort)],
    count: usize,
) -> Result<(), TestError> {
    idle_ports(ports);
    let clk = reset(&ctx.dut()).await?;
    ordered_flow_on_clock(ctx, ports, count, &clk, true).await
}

async fn ordered_flow_on_clock(
    ctx: &RustdvCtx,
    ports: &[(StreamPort, StreamPort)],
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
        for (i, (input, output)) in ports.into_iter().enumerate() {
            if !driving[i] && sent[i] < count && rng.bool() {
                driving[i] = true;
            }
            input.valid.set_u64(driving[i] as u64);
            if driving[i] {
                input.payload.set_u64(sent[i] as u64);
            }
            output.ready.set_u64((!random_ready || rng.bool()) as u64);
        }
        Timer::ns(4).await;
        for (i, (input, output)) in ports.into_iter().enumerate() {
            if driving[i] && input.ready.is_high() {
                sent[i] += 1;
                driving[i] = false;
            }
            if stalled[i].is_some_and(|value| {
                !output.valid.is_high() || output.payload.get_u64() != Ok(value)
            }) {
                return Err(TestError::new(format!(
                    "port {i}: output changed while stalled"
                )));
            }
            stalled[i] = if output.valid.is_high() && !output.ready.is_high() {
                Some(
                    output
                        .payload
                        .get_u64()
                        .map_err(|e| TestError::new(e.to_string()))?,
                )
            } else {
                None
            };
            if output.valid.is_high() && output.ready.is_high() {
                let got = output
                    .payload
                    .get_u64()
                    .map_err(|e| TestError::new(e.to_string()))? as usize;
                if got != received[i] {
                    return Err(TestError::new(format!(
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
    Err(TestError::new(format!(
        "flow timed out: sent={sent:?} received={received:?}"
    )))
}
