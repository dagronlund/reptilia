mod decode;
mod execute;
mod fetch;
mod writeback;

#[cfg(test)]
mod tests;

use rustdv::prelude::*;
use rustdv_utils::reset::reset;

#[cfg(test)]
use rustdv_vpi_stubs as _;

rustdv::vpi_bootstrap!();

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
