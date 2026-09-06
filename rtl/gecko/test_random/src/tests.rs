use std::rc::Rc;

use rustdv::prelude::*;

use crate::{
    agents::{CorruptingMonitor, ExecutionMonitor, MemoryDriver, StressedMemoryDriver},
    bfm::{CoreBfm, MemoryBfm, Session},
    environment::GeckoEnv,
    sequences::{BaseProgramSeq, CornerProgramSeq, GeckoVirtualSeq, RandomProgramSeq},
    transactions::Config,
};

#[derive(Clone, Copy, PartialEq, Eq)]
enum Variant {
    Random,
    Corners,
    Stress,
    Instance,
    Named,
    Passive,
    Corrupt,
    Timeout,
}

fn build_demo(ctx: &mut RustdvCtx, variant: Variant) -> RustdvComp {
    let mut config = Config::from_context(ctx).expect("valid demo configuration");
    if variant == Variant::Timeout {
        config.max_cycles = 2;
    }
    ConfigDb::set_tracing(config.trace_config);
    let session = Rc::new(Session::new(config));
    let core = Rc::new(CoreBfm::new(&ctx.dut()).expect("random wrapper observation signals"));
    let instruction =
        Rc::new(MemoryBfm::new(&ctx.dut(), 0, session.clone()).expect("instruction interface"));
    let data = Rc::new(MemoryBfm::new(&ctx.dut(), 1, session.clone()).expect("data interface"));
    session.passive_expected.set(variant == Variant::Passive);
    ConfigDb::set(None, "*", "SESSION", session);
    ConfigDb::set(None, "*", "CORE_BFM", core);
    ConfigDb::set(None, "*", "ACTIVITY", Active::Active);
    ConfigDb::set(None, "*", "PASSIVE_OBSERVER", false);
    ConfigDb::set(Some(ctx), "env.instruction*", "MEM_BFM", instruction);
    ConfigDb::set(Some(ctx), "env.data*", "MEM_BFM", data.clone());
    ConfigDb::set(Some(ctx), "env.passive*", "MEM_BFM", data);
    ConfigDb::set(Some(ctx), "env.passive", "ACTIVITY", Active::Passive);
    match variant {
        Variant::Random => set_seq_override::<BaseProgramSeq, RandomProgramSeq>(),
        Variant::Stress => {
            set_seq_override::<BaseProgramSeq, RandomProgramSeq>();
            Factory::set_type_override::<MemoryDriver, StressedMemoryDriver>();
        }
        Variant::Instance => {
            set_seq_override::<BaseProgramSeq, CornerProgramSeq>();
            Factory::set_inst_override::<MemoryDriver, StressedMemoryDriver>(
                ctx,
                "env.data.driver",
            );
        }
        Variant::Named => {
            set_seq_override::<BaseProgramSeq, CornerProgramSeq>();
            Factory::set_type_override_by_name("MemoryDriver", "StressedMemoryDriver");
        }
        Variant::Passive => {
            set_seq_override::<BaseProgramSeq, CornerProgramSeq>();
            ConfigDb::set(Some(ctx), "env", "PASSIVE_OBSERVER", true);
        }
        Variant::Corrupt => Factory::set_type_override::<ExecutionMonitor, CorruptingMonitor>(),
        Variant::Corners | Variant::Timeout => {
            set_seq_override::<BaseProgramSeq, CornerProgramSeq>()
        }
    }
    GeckoEnv::create_comp()
}

async fn run_demo(ctx: &RustdvCtx) -> Result<(), TestError> {
    let session: Rc<Session> = ConfigDb::get(Some(ctx), "", "SESSION")?;
    let mut sequence = GeckoVirtualSeq;
    // The pinned phaser joins child errors before returning them. Releasing
    // the root objection on a failure event prevents an error from being
    // obscured by a still-waiting program sequence.
    let deadline = Timer::ns(session.config.max_cycles * 10 + 1000);
    match first2(
        sequence.start_virtual(),
        first2(session.failed.wait(), deadline),
    )
    .await
    {
        Either::First(result) => result.map_err(TestError::from),
        Either::Second(Either::First(())) => Err(session
            .error
            .borrow()
            .clone()
            .expect("failure event carries error")),
        Either::Second(Either::Second(())) => Err(session.fail(TestError::with_kind(
            "testbench progress watchdog expired",
            "gecko_timeout",
        ))),
    }
}

#[rustdv::test(timeout_time = 5, timeout_unit = "ms")]
#[derive(Component, Default)]
struct GeckoRandomTest {
    #[component]
    env: RustdvComp,
}
impl Component for GeckoRandomTest {
    fn build(&mut self, ctx: &mut RustdvCtx) {
        self.env = build_demo(ctx, Variant::Random);
    }

    async fn run(&mut self, ctx: &mut RustdvCtx) -> Result<(), TestError> {
        let _objection = ctx.raise_objection("generated program, checking, and protocol drain");
        run_demo(ctx).await
    }
}

#[rustdv::test(timeout_time = 5, timeout_unit = "ms")]
#[derive(Component, Default)]
struct GeckoCornerTest {
    #[component]
    env: RustdvComp,
}
impl Component for GeckoCornerTest {
    fn build(&mut self, ctx: &mut RustdvCtx) {
        self.env = build_demo(ctx, Variant::Corners);
    }

    async fn run(&mut self, ctx: &mut RustdvCtx) -> Result<(), TestError> {
        let _objection = ctx.raise_objection("generated program, checking, and protocol drain");
        run_demo(ctx).await
    }
}

#[rustdv::test(timeout_time = 5, timeout_unit = "ms")]
#[derive(Component, Default)]
struct GeckoStressTest {
    #[component]
    env: RustdvComp,
}
impl Component for GeckoStressTest {
    fn build(&mut self, ctx: &mut RustdvCtx) {
        self.env = build_demo(ctx, Variant::Stress);
    }

    async fn run(&mut self, ctx: &mut RustdvCtx) -> Result<(), TestError> {
        let _objection = ctx.raise_objection("generated program, checking, and protocol drain");
        run_demo(ctx).await
    }
}

#[rustdv::test(timeout_time = 5, timeout_unit = "ms")]
#[derive(Component, Default)]
struct GeckoInstanceTest {
    #[component]
    env: RustdvComp,
}
impl Component for GeckoInstanceTest {
    fn build(&mut self, ctx: &mut RustdvCtx) {
        self.env = build_demo(ctx, Variant::Instance);
    }

    async fn run(&mut self, ctx: &mut RustdvCtx) -> Result<(), TestError> {
        let _objection = ctx.raise_objection("generated program, checking, and protocol drain");
        run_demo(ctx).await
    }
}

#[rustdv::test(timeout_time = 5, timeout_unit = "ms")]
#[derive(Component, Default)]
struct GeckoNamedTest {
    #[component]
    env: RustdvComp,
}
impl Component for GeckoNamedTest {
    fn build(&mut self, ctx: &mut RustdvCtx) {
        self.env = build_demo(ctx, Variant::Named);
    }

    async fn run(&mut self, ctx: &mut RustdvCtx) -> Result<(), TestError> {
        let _objection = ctx.raise_objection("generated program, checking, and protocol drain");
        run_demo(ctx).await
    }
}

#[rustdv::test(timeout_time = 5, timeout_unit = "ms")]
#[derive(Component, Default)]
struct GeckoPassiveTest {
    #[component]
    env: RustdvComp,
}
impl Component for GeckoPassiveTest {
    fn build(&mut self, ctx: &mut RustdvCtx) {
        self.env = build_demo(ctx, Variant::Passive);
    }

    async fn run(&mut self, ctx: &mut RustdvCtx) -> Result<(), TestError> {
        let _objection = ctx.raise_objection("generated program, checking, and protocol drain");
        run_demo(ctx).await
    }
}

#[rustdv::test(
    timeout_time = 5,
    timeout_unit = "ms",
    expect_error = "gecko_injected_writeback"
)]
#[derive(Component, Default)]
struct GeckoCheckerNegativeTest {
    #[component]
    env: RustdvComp,
}
impl Component for GeckoCheckerNegativeTest {
    fn build(&mut self, ctx: &mut RustdvCtx) {
        self.env = build_demo(ctx, Variant::Corrupt);
    }

    async fn run(&mut self, ctx: &mut RustdvCtx) -> Result<(), TestError> {
        let _objection = ctx.raise_objection("generated program, checking, and protocol drain");
        run_demo(ctx).await
    }
}

#[rustdv::test(timeout_time = 5, timeout_unit = "ms", expect_error = "gecko_timeout")]
#[derive(Component, Default)]
struct GeckoTimeoutNegativeTest {
    #[component]
    env: RustdvComp,
}
impl Component for GeckoTimeoutNegativeTest {
    fn build(&mut self, ctx: &mut RustdvCtx) {
        self.env = build_demo(ctx, Variant::Timeout);
    }

    async fn run(&mut self, ctx: &mut RustdvCtx) -> Result<(), TestError> {
        let _objection = ctx.raise_objection("generated program, checking, and protocol drain");
        run_demo(ctx).await
    }
}

#[rustdv::test(expect_error = "config_not_found")]
#[derive(Component, Default)]
struct GeckoConfigNegativeTest;
impl Component for GeckoConfigNegativeTest {
    async fn run(&mut self, ctx: &mut RustdvCtx) -> Result<(), TestError> {
        let _objection = ctx.raise_objection("configuration failure demonstration");
        let _: u32 = ConfigDb::get(Some(ctx), "", "DELIBERATELY_MISSING")?;
        Err(TestError::new(
            "missing configuration unexpectedly resolved",
        ))
    }
}

#[rustdv::test(expect_error = "tlm_unconnected_port")]
#[derive(Component, Default)]
struct GeckoWiringNegativeTest {
    #[port(put)]
    unwired: PutPort<u32>,
}
impl Component for GeckoWiringNegativeTest {}

#[derive(Component, Default)]
struct ReverseResponseDriver {
    #[port(seq_item)]
    items: SeqItemPort<u32, u32>,
}
impl Component for ReverseResponseDriver {
    async fn run(&mut self, _: &mut RustdvCtx) -> Result<(), TestError> {
        let mut pending: Vec<(TxnId, u32, u32)> = Vec::new();
        loop {
            Timer::ns(10).await;
            if let Some(item) = self.items.try_next_item() {
                pending.push((item.txn_id(), *item.payload(), *item.payload()));
                self.items.item_done(None);
            }
            let mut remaining = Vec::new();
            for (ticket, value, ticks) in pending {
                if ticks == 1 {
                    self.items.put_response(ticket, value);
                } else {
                    remaining.push((ticket, value, ticks - 1));
                }
            }
            pending = remaining;
        }
    }
}

#[derive(Default)]
struct TicketSequence {
    reverse: bool,
}
impl Sequence for TicketSequence {
    type Req = u32;
    type Rsp = u32;
    async fn body(&mut self, ctx: &mut SeqCtx<u32, u32>) -> Result<(), SeqError> {
        let mut tickets = Vec::new();
        for mut value in [10, 7, 4, 1] {
            ctx.start_item(&mut value).await?;
            tickets.push((ctx.finish_item(value).await?, value));
        }
        let mut order = Vec::new();
        for _ in 0..50 {
            let mut remaining = Vec::new();
            for (ticket, expected) in tickets {
                if let Some(value) = ctx.try_get_response(Some(ticket)) {
                    if value != expected {
                        return Err(SeqError::from("response delivered under the wrong ticket"));
                    }
                    order.push(value);
                } else {
                    remaining.push((ticket, expected));
                }
            }
            tickets = remaining;
            if tickets.is_empty() {
                if self.reverse && order != [1, 4, 7, 10] {
                    return Err(SeqError::from(format!(
                        "expected reverse completion, got {order:?}"
                    )));
                }
                ctx.info(&format!("ticketed responses: {order:?}"));
                return Ok(());
            }
            Timer::ns(10).await;
        }
        Err(SeqError::from("ticket routing watchdog expired"))
    }
}

#[rustdv::test(timeout_time = 10, timeout_unit = "us")]
#[derive(Component, Default)]
struct GeckoMethodologyTest {
    #[component]
    seqr: Sequencer<u32, u32>,
    #[component]
    driver: RustdvComp,
}
impl Component for GeckoMethodologyTest {
    fn build(&mut self, _: &mut RustdvCtx) {
        self.seqr = Sequencer::new();
        self.driver = ReverseResponseDriver::create_comp();
    }
    fn connect(&mut self, _: &mut RustdvCtx) {
        self.seqr
            .seq_item_export()
            .connect(&self.driver, ReverseResponseDriver::ITEMS);
    }
    async fn run(&mut self, ctx: &mut RustdvCtx) -> Result<(), TestError> {
        let _objection = ctx.raise_objection("ticket reversal and concurrent sequence arbitration");
        TicketSequence { reverse: true }.start(&self.seqr).await?;
        let mut first = TicketSequence::default();
        let mut second = TicketSequence::default();
        let (a, b) = join2(first.start(&self.seqr), second.start(&self.seqr)).await;
        a?;
        b?;
        Ok(())
    }
}
