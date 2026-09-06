use std::{fs, rc::Rc};

use rustdv::{log::Level, prelude::*};

use crate::{
    agents::{ExecutionMonitor, Inbox, MemoryAgent, ProgramDriver, TraceSubscriber},
    bfm::{CoreBfm, Session},
    coverage::Coverage,
    scoreboard::{CheckedInstruction, Checker},
    transactions::{Completion, Cycle, EBREAK, Expected, Program},
};

#[derive(Clone, Debug)]
pub struct PredictedCycle {
    pub cycle: Cycle,
    pub expected: Option<Expected>,
}

#[derive(Component, Default)]
pub struct Predictor {
    #[port(subscribe)]
    observations: SubscribePort<Cycle>,
    #[port(publish)]
    predictions: PublishPort<PredictedCycle>,
    inbox: RustdvShared<Inbox<Cycle>>,
}
impl Component for Predictor {
    fn build(&mut self, _: &mut RustdvCtx) {
        self.observations.subscribe(self.inbox.clone());
    }
    async fn run(&mut self, ctx: &mut RustdvCtx) -> Result<(), TestError> {
        let session: Rc<Session> = ConfigDb::get(Some(ctx), "", "SESSION")?;
        let queue = self.inbox.get().0.clone();
        loop {
            let cycle = queue.get().await;
            let expected = if let Some(decode) = cycle.decode.filter(|decode| !decode.flushed) {
                let mut reference = session.reference.borrow_mut();
                let reference = reference
                    .as_mut()
                    .expect("image installed before observation");
                if decode.pc != reference.hart.pc {
                    return Err(failure(
                        &session,
                        format!(
                            "cycle {}: decode PC {:#010x}, reference PC {:#010x}",
                            cycle.number, decode.pc, reference.hart.pc
                        ),
                    ));
                }
                if decode.instruction == EBREAK {
                    None
                } else {
                    Some(reference.step().map_err(|e| failure(&session, e))?)
                }
            } else {
                None
            };
            self.predictions.write(&PredictedCycle { cycle, expected });
        }
    }
}

pub fn failure(session: &Session, message: impl Into<String>) -> TestError {
    let message = message.into();
    let report = format!(
        "{message}\nseed={}\nartifacts={}\n",
        session.config.seed,
        session.config.artifacts.display()
    );
    let _ = fs::write(session.config.artifacts.join("failure.txt"), &report);
    session.fail(TestError::with_kind(report, "gecko_check"))
}

#[derive(Component, Default)]
pub struct Scoreboard {
    #[port(subscribe)]
    predictions: SubscribePort<PredictedCycle>,
    #[port(publish)]
    checked: PublishPort<CheckedInstruction>,
    inbox: RustdvShared<Inbox<PredictedCycle>>,
    checker: Checker,
    completed: bool,
}
impl Component for Scoreboard {
    fn build(&mut self, _: &mut RustdvCtx) {
        self.predictions.subscribe(self.inbox.clone());
    }
    async fn run(&mut self, ctx: &mut RustdvCtx) -> Result<(), TestError> {
        let session: Rc<Session> = ConfigDb::get(Some(ctx), "", "SESSION")?;
        let bfm: Rc<CoreBfm> = ConfigDb::get(Some(ctx), "", "CORE_BFM")?;
        let queue = self.inbox.get().0.clone();
        session.started.wait().await;
        let terminal_pc = session
            .program
            .borrow()
            .as_ref()
            .expect("installed program")
            .terminal_pc;
        let mut verified = Vec::new();
        let mut quiet = 0;
        loop {
            let frame = queue.get().await;
            self.checker
                .observe(&frame.cycle, frame.expected.as_ref(), terminal_pc)
                .map_err(|e| {
                    if frame.cycle.injected_writeback && e.contains("expected tag") {
                        return session.fail(TestError::with_kind(e, "gecko_injected_writeback"));
                    }
                    failure(
                        &session,
                        format!(
                            "cycle {}: {e}; {}",
                            frame.cycle.number,
                            self.checker.pending()
                        ),
                    )
                })?;
            if let (Some(expected), Some(decode)) = (frame.expected, frame.cycle.decode) {
                verified.push(CheckedInstruction {
                    expected,
                    tag: decode.tag,
                });
            }
            let drained = self.checker.terminal
                && self.checker.halted
                && self.checker.exit
                && self.checker.drained()
                && session.idle();
            quiet = if drained { quiet + 1 } else { 0 };
            if quiet < 2 {
                continue;
            }
            // A complete following sample is the barrier for the last observed
            // pre-edge write to become visible in the physical register file.
            let reference = session.reference.borrow();
            let reference = reference.as_ref().expect("reference installed");
            self.checker
                .finish(
                    &reference.hart.registers,
                    &session.memory.borrow(),
                    &reference.memory.bytes,
                )
                .map_err(|e| failure(&session, e))?;
            let physical = bfm.registers()?;
            if physical != reference.hart.registers {
                return Err(failure(
                    &session,
                    format!(
                        "physical register file {physical:?} differs from ISS {:?}",
                        reference.hart.registers
                    ),
                ));
            }
            if session.passive_expected.get()
                && session.passive_seen.get() != session.accepted[1].get()
            {
                return Err(failure(&session, "passive observer missed data traffic"));
            }
            for item in &verified {
                self.checked.write(item);
            }
            self.completed = true;
            fs::write(session.config.artifacts.join("result.txt"), format!(
                "Architectural checking complete: {} instructions, {} register writes, {} memory accesses, {} branches; physical registers and memory agree with ISS.\nCoverage and overall verdict are reported separately.\n",
                self.checker.compared, self.checker.writebacks, self.checker.accesses, self.checker.resolved,
            )).map_err(|e| session.fail(TestError::new(e.to_string())))?;
            ctx.info(&format!("{} instructions, {} writes, {} data accesses, {} branch resolutions checked; final state agrees", self.checker.compared, self.checker.writebacks, self.checker.accesses, self.checker.resolved));
            session.done.set();
            return Ok(());
        }
    }
    fn extract(&mut self, ctx: &mut RustdvCtx) {
        ctx.debug(&format!(
            "extract: {} checked instructions",
            self.checker.compared
        ));
    }
    fn check(&mut self, ctx: &mut RustdvCtx, errors: &mut CheckSink) {
        let session: Rc<Session> = ConfigDb::get(Some(ctx), "", "SESSION").expect("session");
        if session.failed.is_set() {
            return;
        }
        if !self.completed || self.checker.compared == 0 || !self.checker.drained() {
            errors.error("scoreboard did not complete non-vacuous checking and drain");
        }
    }
    fn report(&mut self, ctx: &mut RustdvCtx) {
        ctx.info(&format!(
            "scoreboard completed={}, {}",
            self.completed,
            self.checker.pending()
        ));
    }
}

#[derive(Component, Default)]
pub struct ProgramAgent {
    #[component]
    seqr: Sequencer<Program, Completion>,
    #[component]
    driver: RustdvComp,
}
impl Component for ProgramAgent {
    fn build(&mut self, _: &mut RustdvCtx) {
        self.seqr = Sequencer::new();
        self.driver = ProgramDriver::create_comp();
        ConfigDb::set(None, "*", "PROGRAM_SEQR", self.seqr.handle());
    }
    fn connect(&mut self, _: &mut RustdvCtx) {
        self.seqr
            .seq_item_export()
            .connect(&self.driver, ProgramDriver::ITEMS);
    }
}

#[derive(Component, Default)]
pub struct GeckoEnv {
    #[component]
    program: RustdvComp,
    #[component]
    instruction: RustdvComp,
    #[component]
    data: RustdvComp,
    #[component]
    passive: RustdvComp,
    #[component]
    monitor: RustdvComp,
    #[component]
    predictor: RustdvComp,
    #[component]
    scoreboard: RustdvComp,
    #[component]
    coverage: RustdvComp,
    #[component]
    trace: RustdvComp,
    #[component]
    observation_bus: AnalysisBus<Cycle>,
    #[component]
    prediction_bus: AnalysisBus<PredictedCycle>,
    #[component]
    checked_bus: AnalysisBus<CheckedInstruction>,
}
impl Component for GeckoEnv {
    fn build(&mut self, ctx: &mut RustdvCtx) {
        self.program = ProgramAgent::create_comp();
        self.instruction = MemoryAgent::create_comp();
        self.data = MemoryAgent::create_comp();
        let passive: bool =
            ConfigDb::get(Some(ctx), "", "PASSIVE_OBSERVER").expect("passive default");
        if passive {
            self.passive = MemoryAgent::create_comp();
        }
        self.monitor = ExecutionMonitor::create_comp();
        self.predictor = Predictor::create_comp();
        self.scoreboard = Scoreboard::create_comp();
        self.coverage = Coverage::create_comp();
        self.trace = TraceSubscriber::create_comp();
        self.observation_bus = AnalysisBus::new();
        self.prediction_bus = AnalysisBus::new();
        self.checked_bus = AnalysisBus::new();
    }
    fn connect(&mut self, _: &mut RustdvCtx) {
        self.observation_bus
            .pub_export()
            .connect(&self.monitor, ExecutionMonitor::OBSERVATIONS);
        self.observation_bus
            .sub_export()
            .connect(&self.predictor, Predictor::OBSERVATIONS);
        self.observation_bus
            .sub_export()
            .connect(&self.trace, TraceSubscriber::OBSERVATIONS);
        self.prediction_bus
            .pub_export()
            .connect(&self.predictor, Predictor::PREDICTIONS);
        self.prediction_bus
            .sub_export()
            .connect(&self.scoreboard, Scoreboard::PREDICTIONS);
        self.checked_bus
            .pub_export()
            .connect(&self.scoreboard, Scoreboard::CHECKED);
        self.checked_bus
            .sub_export()
            .connect(&self.coverage, Coverage::CHECKED);
    }
    fn end_of_elaboration(&mut self, ctx: &mut RustdvCtx) {
        let session: Rc<Session> = ConfigDb::get(Some(ctx), "", "SESSION").expect("session");
        ctx.set_logging_level_hier(if session.config.trace_config {
            Level::Debug
        } else {
            Level::Info
        });
        print_hierarchy(self);
        Factory::print();
        ConfigDb::print();
        ctx.info("elaboration complete: required TLM ports are checked by RustDV");
    }
    fn start_of_simulation(&mut self, ctx: &mut RustdvCtx) {
        ctx.info("observation subscriptions installed; waiting for image and reset");
    }
    fn final_phase(&mut self, ctx: &mut RustdvCtx) {
        let session: Rc<Session> = ConfigDb::get(Some(ctx), "", "SESSION").expect("session");
        ctx.info(&format!(
            "artifacts: {}",
            session.config.artifacts.display()
        ));
    }
}
