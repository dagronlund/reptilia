use std::rc::Rc;

use rustdv::prelude::*;

use crate::{
    bfm::Session,
    generation::{generate, replay},
    transactions::{Completion, MemoryPlan, MemoryRequest, Program},
};

#[derive(Default)]
pub struct BaseProgramSeq;
#[derive(Default)]
pub struct RandomProgramSeq;
#[derive(Default)]
pub struct CornerProgramSeq;

async fn program_sequence(
    ctx: &mut SeqCtx<Program, Completion>,
    random: bool,
) -> Result<(), SeqError> {
    let session: Rc<Session> = ConfigDb::get(None, "", "SESSION")?;
    let count = if random {
        session.config.instructions
    } else {
        0
    };
    let mut program = match &session.config.replay {
        Some(path) => replay(path, session.config.seed),
        None => generate(session.config.seed, count),
    }
    .map_err(SeqError::from)?;
    ctx.start_item(&mut program).await?;
    let ticket = ctx.finish_item(program).await?;
    let response = ctx.get_response(Some(ticket)).await;
    ctx.info(&format!(
        "checked execution completed after {} cycles",
        response.cycles
    ));
    Ok(())
}

impl Sequence for BaseProgramSeq {
    type Req = Program;
    type Rsp = Completion;
    async fn body(&mut self, ctx: &mut SeqCtx<Program, Completion>) -> Result<(), SeqError> {
        program_sequence(ctx, false).await
    }
}
impl Sequence for RandomProgramSeq {
    type Req = Program;
    type Rsp = Completion;
    async fn body(&mut self, ctx: &mut SeqCtx<Program, Completion>) -> Result<(), SeqError> {
        program_sequence(ctx, true).await
    }
}
impl Sequence for CornerProgramSeq {
    type Req = Program;
    type Rsp = Completion;
    async fn body(&mut self, ctx: &mut SeqCtx<Program, Completion>) -> Result<(), SeqError> {
        program_sequence(ctx, false).await
    }
}

#[derive(Default)]
pub struct GeckoVirtualSeq;
impl Sequence for GeckoVirtualSeq {
    type Req = Program;
    type Rsp = Completion;
    async fn body(&mut self, _: &mut SeqCtx<Program, Completion>) -> Result<(), SeqError> {
        let seqr: Sequencer<Program, Completion> = ConfigDb::get(None, "", "PROGRAM_SEQR")?;
        // The program/control sequence installs memory and resets the DUT.
        // The two reactive memory service components run response sequences
        // concurrently on their own sequencers throughout this operation.
        create_seq::<BaseProgramSeq>().start(&seqr).await
    }
}

pub struct MemoryResponseSeq {
    pub request: MemoryRequest,
}
impl Sequence for MemoryResponseSeq {
    type Req = MemoryPlan;
    type Rsp = Completion;
    async fn body(&mut self, ctx: &mut SeqCtx<MemoryPlan, Completion>) -> Result<(), SeqError> {
        let mut plan = MemoryPlan {
            request: self.request,
            delay: 1,
            stall: 0,
        };
        ctx.start_item(&mut plan).await?;
        let ticket = ctx.finish_item(plan).await?;
        ctx.get_response(Some(ticket)).await;
        Ok(())
    }
}
