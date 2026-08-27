use rustdv::prelude::*;

#[rustdv::test(timeout_time = 5, timeout_unit = "ms")]
async fn mem_split_merge(ctx: RustdvCtx) -> Result<(), TestError> {
    let dut = ctx.dut();
    let clk = dut
        .signal("clk")
        .map_err(|e| TestError::new(e.to_string()))?;
    let rst = dut
        .signal("rst")
        .map_err(|e| TestError::new(e.to_string()))?;
    for name in ["mi[0].valid", "mi[1].valid", "mo[0].ready", "mo[1].ready"] {
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
    let mut input = Vec::new();
    let mut output = Vec::new();
    for i in 0..2 {
        input.push((
            dut.signal(&format!("mi[{i}].valid"))
                .map_err(|e| TestError::new(e.to_string()))?,
            dut.signal(&format!("mi[{i}].ready"))
                .map_err(|e| TestError::new(e.to_string()))?,
            dut.signal(&format!("mi[{i}].read_enable"))
                .map_err(|e| TestError::new(e.to_string()))?,
            dut.signal(&format!("mi[{i}].write_enable"))
                .map_err(|e| TestError::new(e.to_string()))?,
            dut.signal(&format!("mi[{i}].addr"))
                .map_err(|e| TestError::new(e.to_string()))?,
            dut.signal(&format!("mi[{i}].data"))
                .map_err(|e| TestError::new(e.to_string()))?,
            dut.signal(&format!("mi[{i}].id"))
                .map_err(|e| TestError::new(e.to_string()))?,
            dut.signal(&format!("mi[{i}].last"))
                .map_err(|e| TestError::new(e.to_string()))?,
        ));
        output.push((
            dut.signal(&format!("mo[{i}].valid"))
                .map_err(|e| TestError::new(e.to_string()))?,
            dut.signal(&format!("mo[{i}].ready"))
                .map_err(|e| TestError::new(e.to_string()))?,
            dut.signal(&format!("mo[{i}].read_enable"))
                .map_err(|e| TestError::new(e.to_string()))?,
            dut.signal(&format!("mo[{i}].write_enable"))
                .map_err(|e| TestError::new(e.to_string()))?,
            dut.signal(&format!("mo[{i}].addr"))
                .map_err(|e| TestError::new(e.to_string()))?,
            dut.signal(&format!("mo[{i}].data"))
                .map_err(|e| TestError::new(e.to_string()))?,
            dut.signal(&format!("mo[{i}].id"))
                .map_err(|e| TestError::new(e.to_string()))?,
            dut.signal(&format!("mo[{i}].last"))
                .map_err(|e| TestError::new(e.to_string()))?,
        ));
    }
    let mut sent = [0usize; 2];
    let mut recv = [0usize; 2];
    let mut active = [false; 2];
    let mut rng = ctx.rng();
    let input_meta = dut
        .signal("meta_i")
        .map_err(|e| TestError::new(e.to_string()))?;
    let output_meta = dut
        .signal("meta_o")
        .map_err(|e| TestError::new(e.to_string()))?;
    let midv = dut
        .signal("mm.valid")
        .map_err(|e| TestError::new(e.to_string()))?;
    let midr = dut
        .signal("mm.ready")
        .map_err(|e| TestError::new(e.to_string()))?;
    let midi = dut
        .signal("mm.id")
        .map_err(|e| TestError::new(e.to_string()))?;
    let midl = dut
        .signal("mm.last")
        .map_err(|e| TestError::new(e.to_string()))?;
    let mut locked: Option<u64> = None;
    for _ in 0..10000 {
        clk.falling_edge().await;
        input_meta.set_u64(((sent[0] & 1) | (((sent[1] + 1) & 1) << 1)) as u64);
        for i in 0..2 {
            if !active[i] && sent[i] < 32 && rng.bool() {
                active[i] = true;
            }
            input[i].0.set_u64(active[i] as u64);
            input[i].2.set_u64((sent[i] % 2 == 0) as u64);
            input[i]
                .3
                .set_u64((if sent[i] % 2 == 0 { 0 } else { 15 }) as u64);
            input[i].4.set_u64((i * 100 + sent[i]) as u64);
            input[i].5.set_u64((i * 1000 + sent[i]) as u64);
            input[i].6.set_u64((sent[i] & 1) as u64);
            input[i].7.set_u64(((sent[i] + 1) % 4 == 0) as u64);
            output[i].1.set_u64(rng.bool() as u64);
        }
        // Sample the settled request/response routing before the active edge.
        // After the edge, the arbiter may already expose the next input.
        Timer::ns(4).await;
        if midv.is_high() && midr.is_high() {
            let id = midi.get_u64().map_err(|e| TestError::new(e.to_string()))? >> 1;
            if locked.is_some() && locked != Some(id) {
                return Err(TestError::new("packet interleaved before last"));
            }
            locked = if midl.is_high() { None } else { Some(id) };
        }
        for i in 0..2 {
            if active[i] && input[i].1.is_high() {
                sent[i] += 1;
                active[i] = false;
            }
            if output[i].0.is_high() && output[i].1.is_high() {
                let n = recv[i];
                let meta = output_meta
                    .get_u64()
                    .map_err(|e| TestError::new(e.to_string()))?;
                let expected_read = n % 2 == 0;
                let expected_write = if expected_read { 0 } else { 15 };
                if output[i].2.is_high() != expected_read
                    || output[i].3.get_u64() != Ok(expected_write)
                    || output[i].4.get_u64() != Ok((i * 100 + n) as u64)
                    || output[i].5.get_u64() != Ok((i * 1000 + n) as u64)
                    || output[i].6.get_u64() != Ok((n & 1) as u64)
                    || output[i].7.is_high() != ((n + 1) % 4 == 0)
                    || ((meta >> i) & 1 != 0) != ((n + i) & 1 != 0)
                {
                    return Err(TestError::new(format!(
                        "split/merge mismatch on port {i} item {n}"
                    )));
                }
                recv[i] += 1;
            }
        }
        if recv == [32, 32] {
            clk.rising_edge().await;
            return Ok(());
        }
    }
    Err(TestError::new(format!("split/merge timeout {recv:?}")))
}
