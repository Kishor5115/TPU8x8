# Contributing to the 8×8 TPU ASIC

First off, thank you for taking the time to contribute! This project is an
open-source **RTL-to-GDSII** implementation of an 8×8 systolic-array TPU on the
IHP SG13G2 130 nm Open PDK, and contributions of all kinds are welcome — bug
reports, documentation fixes, RTL improvements, and physical-design tweaks.

By participating, you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md).

---

## Table of Contents
- [Ways to Contribute](#ways-to-contribute)
- [Development Setup](#development-setup)
- [Project Conventions](#project-conventions)
- [Verifying Your Changes](#verifying-your-changes)
- [Commit & Pull Request Guidelines](#commit--pull-request-guidelines)
- [Reporting Bugs](#reporting-bugs)
- [License](#license)

---

## Ways to Contribute
- **Report bugs** or unexpected flow behavior via [issues](../../issues).
- **Improve documentation** — README, `docs/CHALLENGES.md`, verification guides.
- **Enhance the RTL** — readability, parameterization, or functional fixes.
- **Tune the physical-design flow** — floorplan, PDN, CTS, routing, signoff.
- **Add tests** to the verification suite under `sym/`.

## Development Setup
1. Install the prerequisites listed in the [README](README.md#prerequisites):
   OSS CAD Suite (Yosys, Icarus Verilog, GTKWave), OpenROAD, and KLayout.
2. Configure your environment:
   ```bash
   cp env.sh.example env.sh   # then edit tool paths for your machine
   source env.sh
   ```
3. Run a quick sanity simulation:
   ```bash
   cd sym/pre_synth && make sim
   ```

> `env.sh` is intentionally git-ignored. Never commit machine-specific or
> absolute tool paths — put them in your local `env.sh` only.

## Project Conventions
- **Verilog / SystemVerilog**
  - Keep the existing module-header comment block style (module name, purpose,
    technology, interface notes).
  - Use clear, descriptive signal names; comment non-obvious timing/skew logic.
  - Target the `-g2012` (SystemVerilog-2012) dialect; the design must elaborate
    cleanly under Icarus Verilog and lint under Verilator.
  - Do not introduce hardcoded absolute paths in RTL, TCL, or Makefiles.
- **TCL / flow scripts**
  - Follow the staged `00_…` → `07_…` structure under `pnr/`.
  - Keep scripts headless-safe (wrap GUI/`save_image` calls in `catch`).
- **Documentation** — Markdown with fenced code blocks; prefer Mermaid for diagrams.

## Verifying Your Changes
Before opening a pull request, please ensure:
- [ ] RTL elaborates cleanly: `cd sym/pre_synth && make sim`
- [ ] Verilator lint is clean for any RTL you touched (see the
      [`rtl-lint`](.github/workflows/rtl-lint.yml) CI workflow).
- [ ] If you changed the flow, the affected stage(s) run end-to-end and the
      signoff reports under `pnr/reports/signoff/` are regenerated.
- [ ] Documentation is updated to reflect behavioral or metric changes.

CI (GitHub Actions) runs RTL linting on every push and pull request; please make
sure it passes.

## Commit & Pull Request Guidelines
- Write clear, imperative commit messages (e.g., `rtl: fix accumulator sign extension`).
- Keep pull requests focused on a single logical change.
- In the PR description, explain **what** changed, **why**, and **how you tested it**.
- Reference any related issues (e.g., `Closes #12`).
- Do not commit large generated artifacts (GDS, DEF, ODB, logs). These are
  covered by `.gitignore`.

## Reporting Bugs
Open an issue using the **Bug Report** template and include:
- A clear description and the stage where the problem occurs (sim / synth / PnR).
- Tool versions (Yosys, OpenROAD, KLayout, Icarus Verilog).
- Exact commands run and the relevant log output.

## License
By contributing, you agree that your contributions will be licensed under the
[Apache License 2.0](LICENSE), the same license that covers this project.
