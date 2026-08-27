mod decode;
mod execute;
mod fetch;
mod writeback;

#[cfg(test)]
mod tests;

use rustdv::prelude::*;

#[cfg(test)]
use rustdv_vpi_stubs as _;

rustdv::vpi_bootstrap!();

#[derive(Clone, Copy)]
struct StreamPort {
    valid: LogicHandle,
    ready: LogicHandle,
    payload: LogicHandle,
}

impl StreamPort {
    fn new(dut: &HierarchyHandle, name: &str) -> Result<Self, TestError> {
        Ok(Self {
            valid: signal(dut, &format!("{name}.valid"))?,
            ready: signal(dut, &format!("{name}.ready"))?,
            payload: signal(dut, &format!("{name}.payload"))?,
        })
    }
}

#[derive(Clone, Copy)]
struct MemPort {
    valid: LogicHandle,
    ready: LogicHandle,
    read_enable: LogicHandle,
    write_enable: LogicHandle,
    addr: LogicHandle,
    data: LogicHandle,
}

impl MemPort {
    fn new(dut: &HierarchyHandle, name: &str) -> Result<Self, TestError> {
        Ok(Self {
            valid: signal(dut, &format!("{name}.valid"))?,
            ready: signal(dut, &format!("{name}.ready"))?,
            read_enable: signal(dut, &format!("{name}.read_enable"))?,
            write_enable: signal(dut, &format!("{name}.write_enable"))?,
            addr: signal(dut, &format!("{name}.addr"))?,
            data: signal(dut, &format!("{name}.data"))?,
        })
    }
}

fn set_packed(signal: &LogicHandle, value: &str) {
    signal.set(&LogicArray::from_binstr(value));
}

fn packed_bits(signal: &LogicHandle, lsb: usize, width: usize) -> Result<u64, TestError> {
    let value = signal.get_binstr();
    let end = value
        .len()
        .checked_sub(lsb)
        .ok_or_else(|| TestError::new("packed field starts beyond payload width"))?;
    let start = end
        .checked_sub(width)
        .ok_or_else(|| TestError::new("packed field extends beyond payload width"))?;
    u64::from_str_radix(&value[start..end], 2)
        .map_err(|error| TestError::new(format!("invalid packed value {value}: {error}")))
}

fn signal(dut: &HierarchyHandle, name: &str) -> Result<LogicHandle, TestError> {
    dut.signal(name)
        .map_err(|error| TestError::new(error.to_string()))
}

async fn reset(dut: &HierarchyHandle) -> Result<LogicHandle, TestError> {
    let clk = signal(dut, "clk")?;
    let rst = signal(dut, "rst")?;
    rst.set_u64(1);
    let _clock = Clock::new(&clk, SimDuration::ns(10)).start();
    for _ in 0..5 {
        clk.falling_edge().await;
    }
    rst.set_u64(0);
    clk.falling_edge().await;
    Ok(clk)
}

fn expect(signal: &LogicHandle, expected: u64, context: &str) -> Result<(), TestError> {
    let actual = signal
        .get_u64()
        .map_err(|error| TestError::new(error.to_string()))?;
    if actual != expected {
        return Err(TestError::new(format!(
            "{context}: expected {expected:#x}, got {actual:#x}"
        )));
    }
    Ok(())
}
