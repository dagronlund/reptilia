# reptilia
SystemVerilog RISC-V implementation and libraries

## Build/Verify

Before building, install [uv](https://docs.astral.sh/uv/), the RISC-V GNU
toolchain, and Verilator. Add both tools' `bin` directories to `PATH`:

```sh
export PATH="<verilator-prefix>/bin:<riscv-prefix>/bin:$PATH"
```

The build discovers `riscv64-unknown-elf-gcc`,
`riscv64-unknown-elf-objcopy`, `riscv64-unknown-elf-objdump`, and `verilator`
from `PATH`. It queries Verilator for its runtime include directory.

Install the locked Python environment with `uv sync`. Ninja and the other
Python dependencies are provided by the uv environment.

`build` lints the RTL and compiles the selected program binaries, Rust plugins,
and Verilator models, without running tests. `test` performs those same build
steps and then runs the selected tests. Both commands default to all discovered
targets and accept `--targets` to select a subset:

```sh
uv run main.py build
uv run main.py build --targets gecko-dhrystone
```

Use `uv run main.py --format` to format the RTL without building or testing.

Run all discovered RustDV targets, including the Gecko pipeline, memory,
stream, supported RV32UI tests, and Dhrystone, with:

```sh
uv run main.py test
```

Use `--targets` to run specific tests:

```sh
uv run main.py test --targets gecko-dhrystone
uv run main.py test --targets gecko-riscv-add gecko-riscv-sub
```

The program tests use the same binary-loading harness and simulated memory as
`gecko-core`. FENCE.I and misaligned data-access tests are excluded because
Gecko does not implement them. Testbenches use
[rustdv](https://github.com/rustdv/rustdv).

These runs are deterministic through `RUSTDV_RANDOM_SEED`. Optional waveforms
are available as VCD or FST, with one file per test target and seed:

```sh
uv run main.py test --wave fst
uv run main.py test --wave vcd --wave-dir build/my-waves
```

FST tracing requires `liblz4`; untraced and VCD runs do not.
Test manifests are discovered as `rtl/**/test.py`. The Gecko program suites
live in `rtl/gecko/test_riscv/test.py` and `rtl/gecko/test_dhrystone/test.py`;
they declare their build recipes and reuse the existing `gecko_tb` Rust crate
and core simulation top. Only binaries needed by the selected targets are built.

`--targets` also supports optional waveforms:

```sh
uv run main.py test --targets gecko-riscv-add gecko-dhrystone --wave vcd
```

Use `--output` to show successful test output, including Dhrystone's report.
Logs and XML results are written per target and seed under `build/rustdv/logs`.

## Cores

### Gecko
Small RV32I core with flexible memory interfaces and lightweight AXI interfaces

<img src="media/gecko.svg" alt="gecko" width="200"/>

### Basilisk
Gecko core with both integer math, floating point, and vector extensions

## Repository Structure

- `rtl/`
	SystemVerilog modules/packages that are going to be synthesized into logic
- `tb/`
	SystemVerilog testbenches for verifying the RTL behavior
- `cpp/`
	Shared C++ Verilator host for RustDV testbenches
- `tests/`
	C/C++/Assembly code for verifying RISC-V core behavior
- `wrappers/`
	SystemVerilog wrappers for verilating/linting RTL files with top-level interfaces
