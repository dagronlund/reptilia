mod core;
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

fn pack_fields(fields: &[(u64, usize)]) -> LogicArray {
    let width = fields.into_iter().map(|(_, width)| width).sum::<usize>();
    let mut words = vec![(0, 0); width.div_ceil(32)];
    let mut lsb = 0;

    for &(value, field_width) in fields.into_iter().rev() {
        assert!(field_width <= u64::BITS as usize);
        for bit in 0..field_width {
            if value & (1 << bit) != 0 {
                let index = lsb + bit;
                words[index / 32].0 |= 1 << (index % 32);
            }
        }
        lsb += field_width;
    }

    LogicArray::from_vpi_words(&words, width)
}

fn packed_bits(value: &LogicArray, lsb: usize, width: usize) -> Result<u64, TestError> {
    if width > u64::BITS as usize {
        return Err(TestError::new("packed field exceeds 64 bits"));
    }
    let end = lsb
        .checked_add(width)
        .ok_or_else(|| TestError::new("packed field range overflowed"))?;
    if end > value.len() {
        return Err(TestError::new("packed field extends beyond payload width"));
    }

    let mut result = 0;
    for bit in 0..width {
        match value.bit(lsb + bit) {
            Some(Logic::Zero) => {}
            Some(Logic::One) => result |= 1 << bit,
            Some(Logic::X) | Some(Logic::Z) => {
                return Err(TestError::new("packed field contains an unresolved bit"));
            }
            None => return Err(TestError::new("packed field extends beyond payload width")),
        }
    }
    Ok(result)
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
