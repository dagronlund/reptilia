mod agents;
mod bfm;
mod coverage;
mod environment;
mod generation;
mod reference;
mod scoreboard;
mod sequences;
mod tests;
mod transactions;

#[cfg(test)]
mod unit_tests;

#[cfg(test)]
use rustdv_vpi_stubs as _;

rustdv::vpi_bootstrap!();
