mod core;
mod decode;
mod execute;
mod fetch;
mod types;
mod writeback;

#[cfg(test)]
mod tests;

#[cfg(test)]
use rustdv_vpi_stubs as _;

rustdv::vpi_bootstrap!();
