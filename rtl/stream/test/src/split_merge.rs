use rustdv::prelude::*;

use crate::fail;

#[rustdv::test(timeout_time = 5, timeout_unit = "ms")]
async fn stream_split_merge(ctx: RustdvCtx) -> Result<(), TestError> {
    let dut = ctx.dut();
    let clk = dut.signal("clk").map_err(|e| fail(e.to_string()))?;
    let rst = dut.signal("rst").map_err(|e| fail(e.to_string()))?;
    let mut signals = Vec::new();
    for name in ["rr0_valid", "rr1_valid", "rr0o_ready", "rr1o_ready"] {
        let h = dut.signal(name).map_err(|e| fail(e.to_string()))?;
        h.set_u64(0);
        signals.push(h);
    }
    rst.set_u64(1);
    let _clock = Clock::new(&clk, SimDuration::ns(10)).start();
    for _ in 0..5 {
        clk.falling_edge().await;
    }
    rst.set_u64(0);

    let rr = [
        (
            dut.signal("rr0_valid"),
            dut.signal("rr0_ready"),
            dut.signal("rr0_payload"),
            dut.signal("rr0_last"),
            dut.signal("rr0o_valid"),
            dut.signal("rr0o_ready"),
            dut.signal("rr0o_payload"),
            dut.signal("rr0o_last"),
        ),
        (
            dut.signal("rr1_valid"),
            dut.signal("rr1_ready"),
            dut.signal("rr1_payload"),
            dut.signal("rr1_last"),
            dut.signal("rr1o_valid"),
            dut.signal("rr1o_ready"),
            dut.signal("rr1o_payload"),
            dut.signal("rr1o_last"),
        ),
    ]
    .into_iter()
    .map(|x| Ok((x.0?, x.1?, x.2?, x.3?, x.4?, x.5?, x.6?, x.7?)))
    .collect::<Result<Vec<_>, HandleError>>()
    .map_err(|e| fail(e.to_string()))?;
    let mut sent = [0usize; 2];
    let mut recv = [0usize; 2];
    let mut active = [false; 2];
    let packet_len = [3usize, 5];
    let beat_count = 30;
    let mut rng = ctx.rng();
    let mid_valid = dut
        .signal("rr_mid_valid")
        .map_err(|e| fail(e.to_string()))?;
    let mid_ready = dut
        .signal("rr_mid_ready")
        .map_err(|e| fail(e.to_string()))?;
    let mid_id = dut.signal("rr_mid_id").map_err(|e| fail(e.to_string()))?;
    let mid_last = dut.signal("rr_mid_last").map_err(|e| fail(e.to_string()))?;
    let mut packet_owner: Option<u64> = None;
    for _ in 0..10_000 {
        clk.falling_edge().await;
        for i in 0..2 {
            if !active[i] && sent[i] < beat_count && rng.bool() {
                active[i] = true;
            }
            rr[i].0.set_u64(active[i] as u64);
            rr[i].2.set_u64((i * 1000 + sent[i]) as u64);
            rr[i].3.set_u64(((sent[i] + 1) % packet_len[i] == 0) as u64);
            rr[i].5.set_u64(rng.bool() as u64);
        }
        Timer::ns(4).await;
        if mid_valid.is_high() && mid_ready.is_high() {
            let id = mid_id.get_u64().map_err(|e| fail(e.to_string()))?;
            if packet_owner.is_some_and(|owner| owner != id) {
                return Err(fail("round-robin merge interleaved a packet"));
            }
            packet_owner = if mid_last.is_high() { None } else { Some(id) };
        }
        for i in 0..2 {
            if active[i] && rr[i].1.is_high() {
                sent[i] += 1;
                active[i] = false;
            }
            if rr[i].4.is_high() && rr[i].5.is_high() {
                let expected = (i * 1000 + recv[i]) as u64;
                if rr[i].6.get_u64() != Ok(expected)
                    || rr[i].7.is_high() != ((recv[i] + 1) % packet_len[i] == 0)
                {
                    return Err(fail(format!(
                        "round-robin output {i} mismatch at {}",
                        recv[i]
                    )));
                }
                recv[i] += 1;
            }
        }
        if recv == [beat_count, beat_count] {
            clk.rising_edge().await;
            break;
        }
    }
    if recv != [beat_count, beat_count] {
        return Err(fail(format!("round-robin timeout: {recv:?}")));
    }
    Ok(())
}
