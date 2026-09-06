use std::{
    fmt,
    fs::{self, File},
    io::{BufWriter, Write},
    rc::Rc,
};

use rustdv::prelude::*;

use crate::{
    bfm::{CoreBfm, MemoryBfm, Session, accepted, payload},
    reference::disassemble,
    sequences::MemoryResponseSeq,
    transactions::{Completion, Cycle, MemoryPlan, MemoryRequest, Program},
};

/// Analysis inboxes own their data and never await in Subscriber::write.
pub struct Inbox<T: 'static>(pub Queue<T>);
impl<T> Default for Inbox<T> {
    fn default() -> Self {
        Self(Queue::unbounded())
    }
}
impl<T: Clone + 'static> Subscriber<T> for Inbox<T> {
    fn write(&mut self, item: &T) {
        self.0
            .try_put(item.clone())
            .unwrap_or_else(|_| panic!("unbounded analysis inbox full"));
    }
}

#[derive(Component, Default)]
pub struct ProgramDriver {
    #[port(seq_item)]
    items: SeqItemPort<Program, Completion>,
}

impl Component for ProgramDriver {
    async fn run(&mut self, ctx: &mut RustdvCtx) -> Result<(), TestError> {
        let session: Rc<Session> = ConfigDb::get(Some(ctx), "", "SESSION")?;
        let bfm: Rc<CoreBfm> = ConfigDb::get(Some(ctx), "", "CORE_BFM")?;
        let item = self.items.get_next_item().await;
        let ticket = item.txn_id();
        let program = item.payload().clone();
        save_program(&session, &program).map_err(|e| session.fail(e))?;
        ctx.info(&format!("installed {program}"));
        session.install(program);
        self.items.item_done(None);
        bfm.reset().await.map_err(|e| session.fail(e))?;
        session.started.set();
        session.done.wait().await;
        self.items.put_response(
            ticket,
            Completion {
                cycles: session.cycles.get(),
            },
        );
        Ok(())
    }
}

fn save_program(session: &Session, program: &Program) -> Result<(), TestError> {
    let dir = &session.config.artifacts;
    fs::create_dir_all(dir).map_err(|e| TestError::new(e.to_string()))?;
    for name in ["failure.txt", "result.txt", "coverage.txt"] {
        let path = dir.join(name);
        if path.is_file() {
            fs::remove_file(path).map_err(|e| TestError::new(e.to_string()))?;
        }
    }
    fs::write(dir.join("memory.bin"), &program.memory)
        .map_err(|e| TestError::new(e.to_string()))?;
    let mut assembly = String::new();
    for (index, word) in (&program.words).into_iter().enumerate() {
        assembly.push_str(&format!(
            "{:08x}: {word:08x}  {}\n",
            index * 4,
            disassemble((index * 4) as u32, *word)
        ));
    }
    fs::write(dir.join("program.txt"), assembly).map_err(|e| TestError::new(e.to_string()))?;
    fs::write(dir.join("config.txt"), format!("{:#?}\n", session.config))
        .map_err(|e| TestError::new(e.to_string()))?;
    Ok(())
}

#[derive(Component, Default)]
pub struct ExecutionMonitor {
    #[port(publish)]
    observations: PublishPort<Cycle>,
}
impl Component for ExecutionMonitor {
    async fn run(&mut self, ctx: &mut RustdvCtx) -> Result<(), TestError> {
        monitor_cycles(&self.observations, ctx, false).await
    }
}

#[derive(Component, Default)]
pub struct CorruptingMonitor {
    #[port(publish)]
    observations: PublishPort<Cycle>,
}
impl Component for CorruptingMonitor {
    async fn run(&mut self, ctx: &mut RustdvCtx) -> Result<(), TestError> {
        monitor_cycles(&self.observations, ctx, true).await
    }
}

async fn monitor_cycles(
    port: &PublishPort<Cycle>,
    ctx: &RustdvCtx,
    corrupt: bool,
) -> Result<(), TestError> {
    let session: Rc<Session> = ConfigDb::get(Some(ctx), "", "SESSION")?;
    let bfm: Rc<CoreBfm> = ConfigDb::get(Some(ctx), "", "CORE_BFM")?;
    session.started.wait().await;
    let mut corrupted = false;
    for cycle in 1..=session.config.max_cycles {
        bfm.clk.falling_edge().await;
        Timer::ns(4).await;
        read_only().await;
        let mut sample = bfm.sample(cycle).map_err(|e| session.fail(e))?;
        session.cycles.set(cycle);
        if corrupt
            && !corrupted
            && let Some(write) = &mut sample.writeback
        {
            write.value ^= 1;
            sample.injected_writeback = true;
            corrupted = true;
            ctx.info("injected one bad observed writeback (DUT unchanged)");
        }
        port.write(&sample);
    }
    Err(session.fail(TestError::with_kind(
        "Gecko execution watchdog expired",
        "gecko_timeout",
    )))
}

#[derive(Component, Default)]
pub struct RequestMonitor {
    #[port(put)]
    requests: PutPort<MemoryRequest>,
}

impl Component for RequestMonitor {
    async fn run(&mut self, ctx: &mut RustdvCtx) -> Result<(), TestError> {
        let bfm: Rc<MemoryBfm> = ConfigDb::get(Some(ctx), "", "MEM_BFM")?;
        bfm.session.started.wait().await;
        let mut stalled_request = None;
        let mut stalled_response = None;
        loop {
            bfm.clk.falling_edge().await;
            Timer::ns(4).await;
            read_only().await;
            // Fetch is a cancellable combinational offer: a redirect/halt
            // changes an unaccepted request. Accepted requests are immutable
            // FIFO transactions and must still be answered. Data requests and
            // our driven responses use held-valid handshakes.
            if bfm.index == 1 {
                check_stable(&bfm.request, &mut stalled_request)
                    .map_err(|e| bfm.session.fail(e))?;
            }
            check_stable(&bfm.result, &mut stalled_response).map_err(|e| bfm.session.fail(e))?;
            if let Some(request) = accepted(&bfm.request)? {
                let counter = &bfm.session.accepted[bfm.index];
                counter.set(counter.get() + 1);
                if let Err(request) = self.requests.try_put(request) {
                    self.requests.put(request).await;
                }
            }
            if let Some(response) = accepted(&bfm.result)? {
                bfm.responses
                    .try_put(response)
                    .map_err(|_| TestError::new("response inbox full"))?;
            }
        }
    }
}

fn check_stable(
    port: &rustdv_utils::mem::MemPort,
    stalled: &mut Option<MemoryRequest>,
) -> Result<(), TestError> {
    let current = if port.valid.is_high() {
        Some(payload(port)?)
    } else {
        None
    };
    if stalled.is_some() && *stalled != current {
        return Err(TestError::with_kind(
            "memory payload/valid changed under backpressure",
            "gecko_protocol",
        ));
    }
    *stalled = if !port.ready.is_high() { current } else { None };
    Ok(())
}

#[derive(Component, Default)]
pub struct MemoryService {
    #[port(get)]
    requests: GetPort<MemoryRequest>,
    #[port(peek)]
    preview: PeekPort<MemoryRequest>,
}

impl Component for MemoryService {
    async fn run(&mut self, ctx: &mut RustdvCtx) -> Result<(), TestError> {
        let seqr: Sequencer<MemoryPlan, Completion> = ConfigDb::get(Some(ctx), "", "MEM_SEQR")?;
        loop {
            let preview = match self.preview.try_peek() {
                Some(request) => request,
                None => self.preview.peek().await,
            };
            let request = match self.requests.try_get() {
                Some(request) => request,
                None => self.requests.get().await,
            };
            if request != preview {
                return Err(TestError::new("request FIFO peek/get mismatch"));
            }
            MemoryResponseSeq { request }.start(&seqr).await?;
        }
    }
}

#[derive(Component, Default)]
pub struct MemoryDriver {
    #[port(seq_item)]
    items: SeqItemPort<MemoryPlan, Completion>,
}
impl Component for MemoryDriver {
    async fn run(&mut self, ctx: &mut RustdvCtx) -> Result<(), TestError> {
        serve_memory(&self.items, ctx, false).await
    }
}

#[derive(Component, Default)]
pub struct StressedMemoryDriver {
    #[port(seq_item)]
    items: SeqItemPort<MemoryPlan, Completion>,
}
impl Component for StressedMemoryDriver {
    async fn run(&mut self, ctx: &mut RustdvCtx) -> Result<(), TestError> {
        serve_memory(&self.items, ctx, true).await
    }
}

async fn serve_memory(
    items: &SeqItemPort<MemoryPlan, Completion>,
    ctx: &RustdvCtx,
    stress: bool,
) -> Result<(), TestError> {
    let bfm: Rc<MemoryBfm> = ConfigDb::get(Some(ctx), "", "MEM_BFM")?;
    let mut rng = Rng::new(bfm.session.config.seed ^ (0x6d65_6d6f_7279_0000 + bfm.index as u64));
    ctx.info(if stress {
        "stressed memory: response latency 1..8, admission stalls 0..3"
    } else {
        "memory: one-cycle response"
    });
    bfm.session.started.wait().await;
    bfm.clk.falling_edge().await;
    bfm.request.ready.set_u64(1);
    loop {
        let item = items.get_next_item().await;
        let ticket = item.txn_id();
        let mut plan = item.payload().clone();
        if stress {
            plan.delay = 1 + rng.below(8);
            plan.stall = rng.below(4);
        }
        items.item_done(None);
        bfm.session.busy[bfm.index].set(true);
        bfm.clk.falling_edge().await;
        bfm.request.ready.set_u64(0);
        let data = bfm.access(plan.request).map_err(|e| bfm.session.fail(e))?;
        for _ in 1..plan.delay {
            bfm.clk.falling_edge().await;
        }
        if plan.request.read {
            bfm.result.read_enable.set_u64(1);
            bfm.result.write_enable.set_u64(0);
            bfm.result.addr.set_u64(plan.request.address as u64);
            bfm.result.data.set_u64(data as u64);
            bfm.result.id.set_u64(plan.request.id as u64);
            bfm.result.last.set_u64(plan.request.last as u64);
            bfm.result.valid.set_u64(1);
            let response = bfm.responses.get().await;
            if response.address != plan.request.address
                || response.data != data
                || response.id != plan.request.id
                || response.last != plan.request.last
            {
                return Err(TestError::new(
                    "observed memory response differs from driven response",
                ));
            }
            bfm.clk.falling_edge().await;
            bfm.result.valid.set_u64(0);
        }
        for _ in 0..plan.stall {
            bfm.clk.falling_edge().await;
        }
        let count = &bfm.session.serviced[bfm.index];
        count.set(count.get() + 1);
        bfm.session.busy[bfm.index].set(false);
        bfm.request.ready.set_u64(1);
        items.put_response(
            ticket,
            Completion {
                cycles: plan.delay + plan.stall,
            },
        );
    }
}

#[derive(Component, Default)]
pub struct PassiveMonitor;
impl Component for PassiveMonitor {
    async fn run(&mut self, ctx: &mut RustdvCtx) -> Result<(), TestError> {
        let bfm: Rc<MemoryBfm> = ConfigDb::get(Some(ctx), "", "MEM_BFM")?;
        bfm.session.started.wait().await;
        loop {
            bfm.clk.falling_edge().await;
            Timer::ns(4).await;
            read_only().await;
            if accepted(&bfm.request)?.is_some() {
                bfm.session
                    .passive_seen
                    .set(bfm.session.passive_seen.get() + 1);
            }
        }
    }
}

#[derive(Default)]
struct Count {
    value: u64,
}
impl Subscriber<MemoryRequest> for Count {
    fn write(&mut self, _: &MemoryRequest) {
        self.value += 1;
    }
}

#[derive(Component, Default)]
pub struct FifoAudit {
    #[port(subscribe)]
    enqueued: SubscribePort<MemoryRequest>,
    #[port(subscribe)]
    dequeued: SubscribePort<MemoryRequest>,
    puts: RustdvShared<Count>,
    gets: RustdvShared<Count>,
}
impl Component for FifoAudit {
    fn build(&mut self, _: &mut RustdvCtx) {
        self.enqueued.subscribe(self.puts.clone());
        self.dequeued.subscribe(self.gets.clone());
    }
    fn check(&mut self, ctx: &mut RustdvCtx, errors: &mut CheckSink) {
        let bfm: Rc<MemoryBfm> = ConfigDb::get(Some(ctx), "", "MEM_BFM").expect("memory agent BFM");
        if bfm.session.failed.is_set() {
            return;
        }
        if self.puts.get().value == 0
            || self.puts.get().value != self.gets.get().value
            || self.puts.get().value != bfm.session.serviced[bfm.index].get()
        {
            errors.error("request FIFO taps/serviced counts disagree or saw no traffic");
        }
    }
    fn report(&mut self, ctx: &mut RustdvCtx) {
        ctx.info(&format!(
            "FIFO taps: {} put, {} get",
            self.puts.get().value,
            self.gets.get().value
        ));
    }
}

#[derive(Component, Default)]
pub struct MemoryAgent {
    #[component]
    monitor: RustdvComp,
    #[component]
    service: RustdvComp,
    #[component]
    driver: RustdvComp,
    #[component]
    fifo: TlmFifo<MemoryRequest>,
    #[component]
    seqr: Sequencer<MemoryPlan, Completion>,
    #[component]
    audit: RustdvComp,
    active: bool,
}
impl Component for MemoryAgent {
    fn build(&mut self, ctx: &mut RustdvCtx) {
        let activity: Active = ConfigDb::get(Some(ctx), "", "ACTIVITY").expect("activity default");
        self.active = activity == Active::Active;
        if self.active {
            self.monitor = RequestMonitor::create_comp();
            self.service = MemoryService::create_comp();
            self.driver = MemoryDriver::create_comp();
            self.fifo = TlmFifo::new(1);
            self.seqr = Sequencer::new();
            self.audit = FifoAudit::create_comp();
            ConfigDb::set(Some(ctx), "*", "MEM_SEQR", self.seqr.handle());
        } else {
            self.monitor = PassiveMonitor::create_comp();
        }
    }
    fn connect(&mut self, _: &mut RustdvCtx) {
        if self.active {
            self.fifo
                .put_export()
                .connect(&self.monitor, RequestMonitor::REQUESTS);
            self.fifo
                .get_export()
                .connect(&self.service, MemoryService::REQUESTS);
            self.fifo
                .peek_export()
                .connect(&self.service, MemoryService::PREVIEW);
            self.seqr
                .seq_item_export()
                .connect(&self.driver, MemoryDriver::ITEMS);
            self.fifo.put_ap().connect(&self.audit, FifoAudit::ENQUEUED);
            self.fifo.get_ap().connect(&self.audit, FifoAudit::DEQUEUED);
        }
    }
}

impl<T: 'static> fmt::Debug for Inbox<T> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Inbox({} pending)", self.0.len())
    }
}

/// A synchronous analysis subscriber preserves the final failing cycle even
/// when a checker terminates the run immediately afterwards.
#[derive(Default)]
struct TraceSink {
    session: Option<Rc<Session>>,
    output: Option<BufWriter<File>>,
}
impl Subscriber<Cycle> for TraceSink {
    fn write(&mut self, sample: &Cycle) {
        let session = self.session.as_ref().expect("trace configured");
        let result = (|| -> std::io::Result<()> {
            if self.output.is_none() {
                self.output = Some(BufWriter::new(File::create(
                    session.config.artifacts.join("observed.log"),
                )?));
            }
            if sample.decode.is_some()
                || sample.execution.is_some()
                || sample.writeback.is_some()
                || sample.branch.is_some()
                || sample.data.is_some()
                || sample.exit
                || sample.error
            {
                let output = self.output.as_mut().unwrap();
                writeln!(output, "{sample}")?;
                output.flush()?;
            }
            Ok(())
        })();
        if let Err(error) = result {
            session.fail(TestError::new(format!("trace artifact: {error}")));
        }
    }
}

#[derive(Component, Default)]
pub struct TraceSubscriber {
    #[port(subscribe)]
    observations: SubscribePort<Cycle>,
    sink: RustdvShared<TraceSink>,
}
impl Component for TraceSubscriber {
    fn build(&mut self, ctx: &mut RustdvCtx) {
        self.sink.get_mut().session =
            Some(ConfigDb::get(Some(ctx), "", "SESSION").expect("session"));
        self.observations.subscribe(self.sink.clone());
    }
}
