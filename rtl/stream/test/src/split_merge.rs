use rustdv::prelude::*;
use rustdv_utils::reset::reset;

#[rustdv::test(timeout_time = 5, timeout_unit = "ms")]
async fn stream_split_merge(ctx: RustdvCtx) -> Result<(), TestError> {
    let dut = ctx.dut();
    let mut signals = Vec::new();
    for name in [
        "ri[0].valid",
        "ri[1].valid",
        "rout[0].ready",
        "rout[1].ready",
    ] {
        let h = dut
            .signal(name)
            .map_err(|e| TestError::new(e.to_string()))?;
        h.set_u64(0);
        signals.push(h);
    }
    let clk = reset(&dut).await?;

    let rr = [
        (
            dut.signal("ri[0].valid"),
            dut.signal("ri[0].ready"),
            dut.signal("ri[0].payload"),
            dut.signal("rout[0].valid"),
            dut.signal("rout[0].ready"),
            dut.signal("rout[0].payload"),
        ),
        (
            dut.signal("ri[1].valid"),
            dut.signal("ri[1].ready"),
            dut.signal("ri[1].payload"),
            dut.signal("rout[1].valid"),
            dut.signal("rout[1].ready"),
            dut.signal("rout[1].payload"),
        ),
    ]
    .into_iter()
    .map(|x| Ok((x.0?, x.1?, x.2?, x.3?, x.4?, x.5?)))
    .collect::<Result<Vec<_>, HandleError>>()
    .map_err(|e| TestError::new(e.to_string()))?;
    let input_id = dut
        .signal("rid")
        .map_err(|e| TestError::new(e.to_string()))?;
    let input_last = dut
        .signal("rlast")
        .map_err(|e| TestError::new(e.to_string()))?;
    let output_last = dut
        .signal("rout_last")
        .map_err(|e| TestError::new(e.to_string()))?;
    input_id.set_u64(0);
    input_last.set_u64(0);
    let mut sent = [0usize; 2];
    let mut recv = [0usize; 2];
    let mut active = [false; 2];
    let packet_len = [3usize, 5];
    let beat_count = 30;
    let mut rng = ctx.rng();
    let mid_valid = dut
        .signal("mid.valid")
        .map_err(|e| TestError::new(e.to_string()))?;
    let mid_ready = dut
        .signal("mid.ready")
        .map_err(|e| TestError::new(e.to_string()))?;
    let mid_id = dut
        .signal("mid_id")
        .map_err(|e| TestError::new(e.to_string()))?;
    let mid_last = dut
        .signal("mid_last")
        .map_err(|e| TestError::new(e.to_string()))?;
    let mut packet_owner: Option<u64> = None;
    for _ in 0..10_000 {
        clk.falling_edge().await;
        input_last.set_u64(
            (((sent[0] + 1) % packet_len[0] == 0) as u64)
                | ((((sent[1] + 1) % packet_len[1] == 0) as u64) << 1),
        );
        for i in 0..2 {
            if !active[i] && sent[i] < beat_count && rng.bool() {
                active[i] = true;
            }
            rr[i].0.set_u64(active[i] as u64);
            rr[i].2.set_u64((i * 1000 + sent[i]) as u64);
            rr[i].4.set_u64(rng.bool() as u64);
        }
        Timer::ns(4).await;
        if mid_valid.is_high() && mid_ready.is_high() {
            let id = mid_id
                .get_u64()
                .map_err(|e| TestError::new(e.to_string()))?;
            if packet_owner.is_some_and(|owner| owner != id) {
                return Err(TestError::new("round-robin merge interleaved a packet"));
            }
            packet_owner = if mid_last.is_high() { None } else { Some(id) };
        }
        let output_last_value = output_last
            .get_u64()
            .map_err(|e| TestError::new(e.to_string()))?;
        for i in 0..2 {
            if active[i] && rr[i].1.is_high() {
                sent[i] += 1;
                active[i] = false;
            }
            if rr[i].3.is_high() && rr[i].4.is_high() {
                let expected = (i * 1000 + recv[i]) as u64;
                if rr[i].5.get_u64() != Ok(expected)
                    || ((output_last_value >> i) & 1 != 0) != ((recv[i] + 1) % packet_len[i] == 0)
                {
                    return Err(TestError::new(format!(
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
        return Err(TestError::new(format!("round-robin timeout: {recv:?}")));
    }
    Ok(())
}
