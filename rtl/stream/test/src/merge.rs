use rustdv::prelude::*;

use crate::fail;

#[rustdv::test(timeout_time = 5, timeout_unit = "ms")]
async fn stream_ordered_merge(ctx: RustdvCtx) -> Result<(), TestError> {
    let dut = ctx.dut();
    let clk = dut.signal("clk").map_err(|e| fail(e.to_string()))?;
    let rst = dut.signal("rst").map_err(|e| fail(e.to_string()))?;
    for name in ["o0_valid", "o1_valid", "o2_valid", "o3_valid", "oo_ready"] {
        dut.signal(name)
            .map_err(|e| fail(e.to_string()))?
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
            dut.signal(&format!("o{i}_valid"))
                .map_err(|e| fail(e.to_string()))?,
            dut.signal(&format!("o{i}_ready"))
                .map_err(|e| fail(e.to_string()))?,
            dut.signal(&format!("o{i}_payload"))
                .map_err(|e| fail(e.to_string()))?,
            dut.signal(&format!("o{i}_id"))
                .map_err(|e| fail(e.to_string()))?,
        ));
    }
    let ov = dut.signal("oo_valid").map_err(|e| fail(e.to_string()))?;
    let or = dut.signal("oo_ready").map_err(|e| fail(e.to_string()))?;
    let opd = dut.signal("oo_payload").map_err(|e| fail(e.to_string()))?;
    let oid = dut.signal("oo_id").map_err(|e| fail(e.to_string()))?;
    for _ in 0..100 {
        clk.falling_edge().await;
        for i in 0..4 {
            op[i].0.set_u64((!accepted[i]) as u64);
            op[i].2.set_u64(payloads[i]);
            op[i].3.set_u64(ids[i]);
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
                return Err(fail("ordered merge mismatch"));
            }
            out += 1;
        }
        if out == 4 {
            clk.rising_edge().await;
            return Ok(());
        }
    }
    Err(fail("ordered merge timeout"))
}
