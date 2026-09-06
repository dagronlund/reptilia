# Gecko randomized RustDV methodology demo

This separate workspace crate generates RV32I machine code, serves two independently timed memory interfaces, and checks accepted execution against **rrs-lib = 0.1.0**. It does not load a compiled program. The existing `rtl/gecko/test` crate, wrapper, memory helpers, and invocation are unchanged. The regression discovers this crate's own `test.py` alongside the existing manifests.

The implementation follows the RustDV book's chapters 23–40 and appendices C/D, checked against the repository's pinned RustDV implementation. “Methodology complete” means demonstrating its supported methodology mechanisms, not exhaustive ISA verification or complete UVM parity.

## Run

From the repository root, with the existing Rust, uv, and Verilator prerequisites:

```sh
# Select demo targets through the existing repository runner.
uv run ./main.py --rustdv-tests --targets gecko-generated-corners
uv run ./main.py --rustdv-tests --targets gecko-generated-random gecko-generated-stress
uv run ./main.py --rustdv-tests --targets gecko-generated-instance gecko-generated-named gecko-generated-passive
uv run ./main.py --rustdv-tests --targets gecko-generated-methodology gecko-generated-config-negative gecko-generated-wiring-negative gecko-generated-checker-negative gecko-generated-timeout-negative

# One seed, configuration lookup tracing, hierarchical debug logs, and waveform.
RUSTDV_RANDOM_SEED=1 GECKO_RANDOM_CONFIG_TRACE=1 uv run ./main.py --rustdv-tests --targets gecko-generated-corners --wave vcd

# All existing and new RustDV tests, plus existing Dhrystone.
uv run ./main.py --rustdv-tests --dhrystone
```

Without `--targets`, the repository runner selects all registered RustDV targets, including the demo. `--targets` accepts space-separated manifest target names, implies `--rustdv-tests`, and filters the RustDV regression; the normal repository build preparation still runs. The demo itself generates its instruction image without a compiler or input binary. Default regression seeds are **1 and 24301**. `RUSTDV_RANDOM_SEED` selects one seed. `GECKO_RANDOM_INSTRUCTIONS` sets the number of random image instructions (default 1,000, maximum 4,000), in addition to register initialization and directed cases. Short control-flow blocks remain intact; random ADDI instructions fill a tail too small for a block. Branches skip image instructions and loops repeat instructions, so image length and executed count differ. The watchdog is 200,000 observed cycles, with a separate progress deadline. The timeout-negative variant deliberately uses two cycles.

The random/stress and directed variants pass with JALR target masking and load-to-x0 dispatch/response handling fixed. No ISA cases are marked expected failures. Use the runner for the verdict: the underlying Verilator executable can exit zero after a RustDV failure; the runner also requires `REGRESSION: PASS`.

## Components and book walkthrough

```text
Gecko*Test
└── env: GeckoEnv
    ├── program: ProgramAgent → sequencer, ProgramDriver
    ├── instruction: MemoryAgent → monitor, FIFO, service, sequencer, driver, audit
    ├── data: MemoryAgent → monitor, FIFO, service, sequencer, driver, audit
    ├── passive: MemoryAgent → observer only (passive variant)
    ├── monitor: ExecutionMonitor
    ├── predictor: Predictor → ReferenceModel
    ├── scoreboard: Scoreboard → Checker
    ├── coverage: Coverage
    ├── trace: TraceSubscriber
    └── observation, prediction, and checked-instruction analysis buses
```

| Book mechanism | Working demonstration and source |
|---|---|
| Components and phases, chapters 23–25 | `tests.rs` builds `GeckoEnv`; `environment.rs` and `agents.rs` build the hierarchy and connect typed ports. End-of-elaboration prints topology, factory, and configuration; start-of-simulation initializes observation policy; run drives/checks; extract collects counts; check requires completion and coverage; report emits statistics/coverage; final phase identifies finalized artifacts. All nine callbacks participate. |
| Logging, chapter 26 | Context-qualified logs; `GeckoEnv::end_of_elaboration` applies hierarchical Info/Debug policy. `GECKO_RANDOM_CONFIG_TRACE=1` enables Debug and database tracing. |
| Configuration, chapters 27–28 | Typed `Config`, shared `Session`, BFM handles, sequencer handles, wildcard activity defaults, subtree BFM settings, passive override, lookup tracing and database dump. |
| Component factory, chapters 29–30 | `stress`: type override of `MemoryDriver`; `instance`: override only `env.data.driver`; `named`: override both drivers by registered name. Topology/factory reports expose the substitutions. |
| Active/passive agents | `MemoryAgent` creates driving/service components only when active. The passive variant independently counts the same accepted data requests, and completion checks exact count agreement. |
| TLM, chapters 31–34 | Memory request FIFO has put/get/peek ports, blocking/nonblocking operations, and independent put/get analysis taps. `FifoAudit` requires equal nonzero accepted/serviced counts. Analysis buses broadcast atomic observations to prediction and a separate synchronous trace subscriber; checked instructions go to coverage. |
| Transactions, chapter 35 | `transactions.rs`: encoded `Program`, `Decode`, `MemoryRequest`, `MemoryPlan`, `Execution`, `Writeback`, `Branch`, `Cycle`, `Expected`, and `Completion`; owned clone/compare/debug values and readable program/memory/cycle displays. |
| Sequences, chapters 36–38 | `sequences.rs`: factory-selected random/corner program sequences, including directed dependency cases; per-agent memory-response sequences. Drivers release requests with `item_done(None)` and return completion later via transaction tickets. |
| Out-of-order response routing | `methodology`: synthetic variable-latency service completes requests in reverse order, claims each response by ticket, then runs two sequences concurrently to verify routing between sequence owners. This is independent of the in-order memory protocol. |
| Virtual sequences, chapter 39 | `GeckoVirtualSeq` launches the selected program sequence. Its driver installs the image, resets, starts observation and both concurrently running memory agents, and returns a ticketed completion only after scoreboard/protocol drain. |
| Objections/events/queues | Root objection spans sequence, checking, and drain. Events coordinate startup, completion, and failure; queues transfer owned observations/acknowledgements. A failure event releases the root objection even though the pinned phaser waits for objections before joining child errors. |
| Negative validation | Missing configuration and disconnected required TLM port expect the specific framework errors. A factory-injected `CorruptingMonitor` changes one observed writeback and must trigger the injection-specific mismatch error. Timeout has its own expected error kind. None changes RTL. |

## Stimulus, oracle, and observation

`generation.rs` encodes instructions directly. It initializes x1–x31, reserves x31 as the data pointer, separates executable memory `[0, 0x8000)` from data `[0x8000, 0xf000)`, and keeps the image stable throughout execution. Directed cases cover 37 operations, both outcomes of all six branches, bounded loops, JALR with both even and odd pre-mask targets, memory widths/lanes, signed boundaries, shifts, x0, forwarding, load-use dependencies, repeated destinations, and status-tag wraparound. Random instructions additionally include odd JALR targets and loads to x0. Generator and per-agent timing RNGs derive independent streams from the effective RustDV seed.

`reference.rs` adapts rrs-lib's instruction executor, hart registers, memory trait, and disassembler. The reference owns a separate memory copy and records register writes, memory effects, and next PCs. DUT writes never update it. EBREAK is an explicit Gecko harness termination operation; it is not stepped as a standard architectural exception. FENCE, privileged instructions, interrupts, general CSR testing, and self-modifying code are outside scope.

The new wrapper adds read-only aliases for accepted decode, allocation tags, execution completion, branch resolution, writeback, and final physical registers. Production ports are unchanged. The execute stage clears bit 0 of jump targets after addition, as required by JALR. Accepted decode includes the first instruction as reset completes; flushed decode is tracked separately. Fetch requests and performance-counter pulses do not advance the reference.

`CoreBfm` takes one atomic sample in the read-only region just before each rising edge. `Checker::observe` processes older writeback, data access, branch resolution, execute completion, then new decode allocation, in that fixed order. Register writebacks may reorder across registers; per-register queues carry monotonically increasing software generations and validate the 3-bit hardware status tag through wraparound. Stores, branches, x0 loads, and other instructions without register writes still owe their effects. Wrong, duplicate, missing, unexpected, or illegally reordered effects fail. This configured Gecko stalls speculative dispatch: flushed instructions must not dispatch, and unexpected killed effects are rejected. Supporting a differently configured speculative pipeline would require extending this bookkeeping.

Memory monitors observe accepted external handshakes independently. Services retain accepted requests and response payloads, preserve response order, and audit FIFO traffic. Default responses use one cycle; the stressed driver uses 1–8 cycles plus bounded 0–3-cycle request stalls. The instruction request interface is a cancellable combinational offer before acceptance (redirect/halt may withdraw it), so only accepted fetches are obligations. Data requests and held responses are checked for stability under backpressure.

Completion requires the expected terminal decode and halt, exit, all expected execution/write/memory/branch effects, drained memory services, nonzero comparisons, and agreement of physical registers and the complete DUT/reference memories. Two quiet samples allow the last synchronous write to commit. Coverage receives observations only after the entire run has been checked successfully. It requires operation, branch-outcome, width/lane, dependency and selected operand-boundary bins; operation/operand-sign crosses are reported without demanding every cross. Failed runs do not receive coverage credit for merely generated instructions.

## Artifacts and replay

Each test/seed writes beneath `build/rustdv/gecko-random/<test>-seed-<seed>/`:

- `config.txt`: effective seed, instruction budget, timeout and replay configuration.
- `memory.bin`: exact initial 64 KiB image, including randomized data.
- `program.txt`: address, encoding, independent disassembly.
- `observed.log`: atomic observed events, flushed synchronously through an analysis subscriber.
- `result.txt`: successful architectural comparison counts (not the overall coverage verdict).
- `coverage.txt`: observed checked bins and missing bins.
- `failure.txt`: first failure with reproduction context, when applicable.

Runner logs/XML live in `build/rustdv/logs`; waveforms in `build/waves`. `GECKO_RANDOM_ARTIFACTS` changes the artifact root. A repeat of the same test/seed replaces its artifacts, so use a different root for replays or experiments. Save `memory.bin` elsewhere before replaying into the same output directory.

```sh
RUSTDV_RANDOM_SEED=1 GECKO_RANDOM_ARTIFACTS=build/rustdv/replay GECKO_RANDOM_REPLAY=build/rustdv/gecko-random/GeckoRandomTest-seed-1/memory.bin uv run ./main.py --rustdv-tests --targets gecko-generated-random
```

`GECKO_RANDOM_REPLAY` accepts an exact saved `.bin` or a hexadecimal word list with `#` comments. Focused replay reports partial coverage without requiring the full directed suite; all architectural/protocol checks remain enabled.

## Load-to-x0 regression

Loads dispatch regardless of their destination register. At the memory response boundary, loads to x0 consume their command and response together without forwarding a register write or advancing a writeback status tag. A delayed response cannot cause the command to be consumed early. Normal directed stimulus covers signed and unsigned byte/halfword loads and word loads to x0, across all naturally aligned lanes; random generation also includes them.

## Validation and limits

Rust unit tests exercise known encodings/independent decoding, deterministic bounded generation, complete directed reference coverage, signed byte loads and separate memory, legal cross-register writeback reordering, illegal same-register reordering, duplicate/stale writes and tag wraparound, wrong memory-address effects, missing work, flushed dispatch, cycle reordering, and the load-x0 architectural expectation using the normal directed image. Simulator variants exercise delayed service/backpressure, passive noninterference, factories, concurrent sequence response routing, and specific negative outcomes.

The repository formatting and lint commands are `cargo fmt`, `cargo test`, `cargo check`, `cargo clippy`, `uvx ruff check .`, and `uv run ./main.py --format`. The combined `--rustdv-tests --dhrystone` run executes existing tests and all registered demo variants. The fixes were validated with both default seeds. The waveform-enabled corner run passes and produces a validated VCD header/nonempty file.

RustDV has no sequencer locking/priority arbitration equivalent in these pinned APIs, no UVM register abstraction layer here, and no SV constraint solver or covergroup DSL. Constraints/bins are ordinary Rust, and composition/traits/factories replace class inheritance. The methodology routing self-test demonstrates supported concurrent sequencing, not an invented arbitration policy. This demo verifies one Gecko configuration and a bounded RV32I subset, not exception behavior, all microarchitectural configurations, or exhaustive coverage.
