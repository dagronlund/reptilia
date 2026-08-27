use std::{
    env, fs,
    io::{self, Write},
    path::PathBuf,
};

use rustdv::prelude::*;
use rustdv_utils::{
    mem::{MemPort, MemoryPortDual},
    reset::reset,
    stream::StreamPort,
};

const MEMORY_BYTES: usize = 64 * 1024;
const MAX_CYCLES: usize = 200_000;

fn program_path() -> Result<PathBuf, TestError> {
    let mut arguments = env::args_os();
    while let Some(argument) = arguments.next() {
        if argument == "--binary" || argument == "-b" {
            return arguments
                .next()
                .map(PathBuf::from)
                .ok_or_else(|| TestError::new("--binary requires a program path"));
        }
    }
    Err(TestError::new(
        "missing program argument; invoke the simulator with --binary <path>",
    ))
}

fn load_memory() -> Result<Vec<u8>, TestError> {
    let path = program_path()?;
    let program = fs::read(&path).map_err(|error| {
        TestError::new(format!(
            "failed to read program {}: {error}",
            path.display()
        ))
    })?;
    if program.len() > MEMORY_BYTES {
        return Err(TestError::new(format!(
            "program {} is {} bytes and does not fit in {MEMORY_BYTES} bytes",
            path.display(),
            program.len(),
        )));
    }
    let mut memory = vec![0; MEMORY_BYTES];
    memory[..program.len()].copy_from_slice(&program);
    Ok(memory)
}

fn write_tty(tty_out: &StreamPort) -> Result<(), TestError> {
    if !tty_out.valid.is_high() || !tty_out.ready.is_high() {
        return Ok(());
    }
    let byte = tty_out
        .payload
        .get_u64()
        .map_err(|error| TestError::new(error.to_string()))? as u8;
    let mut stdout = io::stdout().lock();
    stdout
        .write_all(&[byte])
        .map_err(|error| TestError::new(error.to_string()))?;
    stdout
        .flush()
        .map_err(|error| TestError::new(error.to_string()))
}

#[rustdv::test(timeout_time = 5, timeout_unit = "ms")]
async fn gecko_core(ctx: RustdvCtx) -> Result<(), TestError> {
    let dut = ctx.dut();
    let mut memory = load_memory()?;
    let mut instruction = MemoryPortDual::new(&dut, "inst_request", "inst_result")?;
    let mut data = MemoryPortDual::new(&dut, "data_request", "data_result")?;
    let float_request = MemPort::new(&dut, "float_mem_request")
        .map_err(|error| TestError::new(error.to_string()))?;
    let float_result = MemPort::new(&dut, "float_mem_result")
        .map_err(|error| TestError::new(error.to_string()))?;
    float_request.ready.set_u64(0);
    float_result.valid.set_u64(0);

    let tty_in =
        StreamPort::new(&dut, "tty_in").map_err(|error| TestError::new(error.to_string()))?;
    let tty_out =
        StreamPort::new(&dut, "tty_out").map_err(|error| TestError::new(error.to_string()))?;
    tty_in.idle_input();
    tty_out.ready.set_u64(1);

    let exit_flag = dut
        .signal("exit_flag")
        .map_err(|error| TestError::new(error.to_string()))?;
    let error_flag = dut
        .signal("error_flag")
        .map_err(|error| TestError::new(error.to_string()))?;
    let exit_code = dut
        .signal("exit_code")
        .map_err(|error| TestError::new(error.to_string()))?;
    let clk = reset(&dut).await?;

    for _ in 0..MAX_CYCLES {
        instruction.start_cycle(&mut memory)?;
        data.start_cycle(&mut memory)?;

        Timer::ns(4).await;
        write_tty(&tty_out)?;
        if error_flag.is_high() {
            return Err(TestError::new("Gecko stopped with its error flag set"));
        }
        if exit_flag.is_high() {
            let code = exit_code
                .get_u64()
                .map_err(|error| TestError::new(error.to_string()))? as u8;
            if code != 0 {
                return Err(TestError::new(format!(
                    "Gecko program exited with status {code}",
                )));
            }
            return Ok(());
        }

        instruction.end_cycle()?;
        data.end_cycle()?;
        clk.falling_edge().await;
    }
    Err(TestError::new(format!(
        "Gecko program did not exit within {MAX_CYCLES} cycles",
    )))
}
