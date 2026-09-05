pub mod convert;
pub mod mem;
pub mod reset;
pub mod stream;

use rustdv::prelude::*;

pub fn expect_equal<T: PartialEq + std::fmt::Debug>(
    actual: T,
    expected: T,
) -> Result<(), TestError> {
    if actual != expected {
        return Err(TestError::new(format!(
            "Expected: {expected:?}\nActual: {actual:?}"
        )));
    }
    Ok(())
}
