"""Build and run rustdv testbench libraries against Verilator."""

from __future__ import annotations

import os
import platform
import runpy
import shlex
import subprocess
from dataclasses import dataclass
from inspect import currentframe
from pathlib import Path
from typing import TYPE_CHECKING, Literal, cast

from ninja.ninja_syntax import Writer as NinjaWriter

from .environment import discover_verilator
from .verilator import VerilatorModel

if TYPE_CHECKING:
    from .build import SourceFile

WaveFormat = Literal["vcd", "fst"]


@dataclass(frozen=True)
class RustdvTarget:
    name: str
    family: Literal["gecko", "mem", "stream"]
    crate: str
    testcase: str
    top: str
    files: tuple[str, ...]
    wrapper: str
    parameters: tuple[tuple[str, str | int], ...] = ()


class RustdvTest:
    """Declare and register a rustdv target in the calling manifest."""

    def __init__(
        self,
        *,
        name: str,
        family: Literal["gecko", "mem", "stream"],
        crate: str,
        testcase: str,
        top: str,
        files: tuple[str, ...],
        wrapper: str,
        parameters: tuple[tuple[str, str | int], ...] = (),
    ) -> None:
        self.target = RustdvTarget(
            name=name,
            family=family,
            crate=crate,
            testcase=testcase,
            top=top,
            files=files,
            wrapper=wrapper,
            parameters=parameters,
        )

        frame = currentframe()
        if frame is None or frame.f_back is None:
            raise RuntimeError("could not determine the rustdv manifest scope")
        namespace = frame.f_back.f_globals
        del frame
        declared = namespace.setdefault("_TARGETS", [])
        if not isinstance(declared, list):
            raise TypeError("rustdv manifest _TARGETS must be a list")
        declared.append(self)


def discover_targets(root: Path = Path("rtl")) -> tuple[RustdvTarget, ...]:
    """Load target declarations colocated with RTL family test directories."""
    targets: list[RustdvTarget] = []
    manifests = sorted(root.glob("**/test/test.py"))
    for manifest in manifests:
        namespace = runpy.run_path(str(manifest))
        declared = namespace.get("_TARGETS")
        if not isinstance(declared, list):
            raise TypeError(f"{manifest} did not register any RustdvTest objects")
        for test in declared:
            if not isinstance(test, RustdvTest):
                raise TypeError(
                    f"{manifest} _TARGETS contains {type(test).__name__}, "
                    "expected RustdvTest"
                )
            targets.append(test.target)

    names = [target.name for target in targets]
    if len(names) != len(set(names)):
        raise RuntimeError("duplicate rustdv target names were discovered")
    if not targets:
        raise RuntimeError(f"no rustdv test manifests found below {root}")
    return tuple(targets)


def _library_path(crate: str) -> Path:
    stem = crate.replace("-", "_")
    suffix = ".dylib" if platform.system() == "Darwin" else ".so"
    return Path("target/release") / f"lib{stem}{suffix}"


def _ordered_sources(
    target: RustdvTarget, source_files: dict[str, SourceFile]
) -> list[str]:
    result: list[str] = []
    seen: set[str] = set()
    for source_file in target.files:
        for source in source_files[source_file].get_dependencies():
            if source not in seen:
                seen.add(source)
                result.append(source)
    result.append(target.wrapper)
    return result


def _build_model(
    target: RustdvTarget,
    source_files: dict[str, SourceFile],
    wave: WaveFormat | None,
) -> Path:
    _ = discover_verilator(min_version=(5, 50))
    variant = wave or "fast"
    build = Path("build/rustdv") / target.name / variant
    obj = build / "obj_dir"
    build.mkdir(parents=True, exist_ok=True)

    verilator_args = [
        "-sv",
        "--timing",
        "--vpi",
        "--timescale",
        "1ns/1ps",
        "-Wno-TIMESCALEMOD",
        "-Wno-UNOPTFLAT",
        "--top-module",
        target.top,
        "-Irtl/",
        "+define+__SYNTH_ONLY__=1",
        "+define+__RUSTDV__=1",
    ]
    verilator_args.extend(f"-G{name}={value}" for name, value in target.parameters)
    compile_flags: tuple[str, ...] = ()
    link_flags: tuple[str, ...] = ()
    if wave == "vcd":
        verilator_args.extend(("--trace", "--trace-structs"))
    elif wave == "fst":
        try:
            lz4_flags = subprocess.run(
                ["pkg-config", "--cflags", "--libs", "liblz4"],
                check=True,
                text=True,
                capture_output=True,
            ).stdout.split()
        except (FileNotFoundError, subprocess.CalledProcessError) as error:
            raise RuntimeError(
                "FST waveforms require liblz4 and its pkg-config metadata"
            ) from error
        compile_flags = tuple(flag for flag in lz4_flags if flag.startswith("-I"))
        link_flags = tuple(flag for flag in lz4_flags if not flag.startswith("-I"))
        verilator_args.extend(("--trace-fst", "--trace-structs"))

    host = Path("cpp/rustdv_verilator_main.cpp").resolve()
    model = VerilatorModel(
        prefix="Vrustdv_dut",
        model_directory=obj,
        executable=obj / "rustdv_sim",
        cpp_files=(host,),
        compile_flags=compile_flags,
        link_flags=link_flags,
    )
    model.verilate(
        _ordered_sources(target, source_files),
        verilator_args,
    )
    model.build()
    return model.executable


def _check_waveform(path: Path, wave: WaveFormat) -> None:
    if not path.is_file() or path.stat().st_size == 0:
        raise RuntimeError(f"rustdv did not produce waveform {path}")
    with path.open("rb") as waveform:
        header = waveform.read(16)
    if wave == "vcd" and not header.startswith(b"$version"):
        raise RuntimeError(f"waveform {path} does not have a VCD header")
    if wave == "fst" and not header.startswith(b"\0\0\0\0\0\0\0\1"):
        raise RuntimeError(f"waveform {path} does not have an FST header")


def _quote(path_or_value: object) -> str:
    return shlex.quote(str(path_or_value))


def _write_test_ninja(
    writer: str,
    targets: tuple[RustdvTarget, ...],
    simulators: dict[str, Path],
    seeds: tuple[str, ...],
    wave: WaveFormat | None,
    wave_dir: Path,
    log_dir: Path,
) -> tuple[Path, ...]:
    ninja_writer = NinjaWriter(writer)
    ninja_writer.comment("Run rustdv tests against Verilator models")
    ninja_writer.rule(
        name="rustdv_test",
        command=(
            "env RUSTDV_TESTCASE=$testcase RUSTDV_RANDOM_SEED=$seed "
            "RUSTDV_RESULTS_XML=$results $wave_env "
            "$simulator $plugin > $log 2>&1 || "
            "{ status=$$?; cat $log; exit $$status; }; "
            "cat $log; grep -q 'REGRESSION: PASS' $log"
        ),
        description="RUSTDV $name seed $seed",
    )

    ninja_targets: list[str] = []
    waveforms: list[Path] = []
    for target in targets:
        simulator = simulators[target.name].resolve()
        library = _library_path(target.crate).resolve()
        for seed_index, seed in enumerate(seeds):
            name = f"{target.name}-seed-{seed}"
            log = (log_dir / f"{name}.log").resolve()
            results = (log_dir / f"{name}.xml").resolve()
            variables = {
                "name": target.name,
                "testcase": _quote(target.testcase),
                "seed": _quote(seed),
                "results": _quote(results),
                "simulator": _quote(simulator),
                "plugin": _quote(f"+verilator+vpi+{library}"),
                "log": _quote(log),
                "wave_env": "",
            }
            if wave is not None:
                waveform = (wave_dir / f"{name}.{wave}").resolve()
                variables["wave_env"] = f"RUSTDV_WAVE={_quote(waveform)}"
                waveforms.append(waveform)

            ninja_target = f"rustdv-test-{target.name}-{seed_index}"
            ninja_writer.build(
                outputs=[ninja_target],
                rule="rustdv_test",
                implicit=[str(simulator), str(library)],
                variables=variables,
            )
            ninja_targets.append(ninja_target)

    ninja_writer.default(ninja_targets)
    ninja_writer.newline()
    return tuple(waveforms)


def run_rustdv_tests(
    source_files: dict[str, SourceFile],
    *,
    wave: WaveFormat | None,
    wave_dir: Path,
) -> None:
    targets = discover_targets()
    crates = sorted({target.crate for target in targets})
    for crate in crates:
        subprocess.run(["cargo", "build", "--release", "-p", crate], check=True)

    requested_seed = os.environ.get("RUSTDV_RANDOM_SEED")
    seeds = (requested_seed,) if requested_seed is not None else ("1", "24301")
    log_dir = Path("build/rustdv/logs")
    log_dir.mkdir(parents=True, exist_ok=True)
    if wave is not None:
        wave_dir.mkdir(parents=True, exist_ok=True)

    simulators: dict[str, Path] = {}
    for target in targets:
        simulators[target.name] = _build_model(target, source_files, wave)

    ninja_path = Path("build/rustdv/tests.ninja")
    with ninja_path.open("w", encoding="utf-8") as ninja_file:
        waveforms = _write_test_ninja(
            cast(str, ninja_file),
            targets,
            simulators,
            seeds,
            wave,
            wave_dir,
            log_dir,
        )
    jobs = os.cpu_count() or 1
    subprocess.run(
        ["ninja", "-f", str(ninja_path), f"-j{jobs}", "-k", "0"],
        check=True,
    )

    if wave is not None:
        for waveform in waveforms:
            _check_waveform(waveform, wave)
