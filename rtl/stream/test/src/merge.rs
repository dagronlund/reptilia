use rustdv::prelude::*;

#[rustdv::test(timeout_time = 5, timeout_unit = "ms")]
async fn stream_ordered_merge(ctx: RustdvCtx) -> Result<(), TestError> {
    let dut = ctx.dut();
    let clk = dut
        .signal("clk")
        .map_err(|e| TestError::new(e.to_string()))?;
    let rst = dut
        .signal("rst")
        .map_err(|e| TestError::new(e.to_string()))?;
    for name in [
        "stream_in[0].valid",
        "stream_in[1].valid",
        "stream_in[2].valid",
        "stream_in[3].valid",
        "stream_out.ready",
    ] {
        dut.signal(name)
            .map_err(|e| TestError::new(e.to_string()))?
            .set_u64(0);
    }
    rst.set_u64(1);
    let _clock = Clock::new(&clk, SimDuration::ns(10)).start();
    for _ in 0..5 {
        clk.falling_edge().await;
    }
    rst.set_u64(0);

    // Ordered merge: IDs arrive on deliberately shuffled physical ports.
    let ids = [2u64, 0, 3, 1];
    let payloads = [102u64, 100, 103, 101];
    let mut accepted = [false; 4];
    let mut out = 0usize;
    let mut op = Vec::new();
    for i in 0..4 {
        op.push((
            dut.signal(&format!("stream_in[{i}].valid"))
                .map_err(|e| TestError::new(e.to_string()))?,
            dut.signal(&format!("stream_in[{i}].ready"))
                .map_err(|e| TestError::new(e.to_string()))?,
            dut.signal(&format!("stream_in[{i}].payload"))
                .map_err(|e| TestError::new(e.to_string()))?,
        ));
    }
    let input_id = dut
        .signal("stream_in_id")
        .map_err(|e| TestError::new(e.to_string()))?;
    let input_last = dut
        .signal("stream_in_last")
        .map_err(|e| TestError::new(e.to_string()))?;
    input_id.set_u64(ids[0] | (ids[1] << 2) | (ids[2] << 4) | (ids[3] << 6));
    input_last.set_u64(0xf);
    let ov = dut
        .signal("stream_out.valid")
        .map_err(|e| TestError::new(e.to_string()))?;
    let or = dut
        .signal("stream_out.ready")
        .map_err(|e| TestError::new(e.to_string()))?;
    let opd = dut
        .signal("stream_out.payload")
        .map_err(|e| TestError::new(e.to_string()))?;
    let oid = dut
        .signal("stream_out_id")
        .map_err(|e| TestError::new(e.to_string()))?;
    for _ in 0..100 {
        clk.falling_edge().await;
        for i in 0..4 {
            op[i].0.set_u64((!accepted[i]) as u64);
            op[i].2.set_u64(payloads[i]);
        }
        or.set_u64(1);
        Timer::ns(4).await;
        for i in 0..4 {
            if !accepted[i] && op[i].1.is_high() {
                accepted[i] = true;
            }
        }
        if ov.is_high() && or.is_high() {
            if oid.get_u64() != Ok(out as u64) || opd.get_u64() != Ok(100 + out as u64) {
                return Err(TestError::new("ordered merge mismatch"));
            }
            out += 1;
        }
        if out == 4 {
            clk.rising_edge().await;
            return Ok(());
        }
    }
    Err(TestError::new("ordered merge timeout"))
}
