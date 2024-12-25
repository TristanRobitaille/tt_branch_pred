<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

This project implements a very minimal perceptron-based branch predictor. Using basic SPI, it reads in the lower part of the address of a branch instruction and its ground truth branch direction (taken or not taken). Once the computation is done, it pulse the pin "pred_ready" and outputs its prediction on the pin "direction_pred". Due to constraints on the memory architecture (namely, 1 byte read per cycle), the prediciton is not single-cycle.

The branch predictor is based on this paper: [Dynamic Branch Prediction with Perceptrons](https://www.cs.utexas.edu/~lin/papers/hpca01.pdf).

This project uses latch-based memory from Michael Dell, available at: [tt06-memory](https://github.com/MichaelBell/tt06-memory)

It's best to run this project in its Docker container.
Build: `docker build -t tt_brand_predictor .` (Takes >30 minutes, and ~25GB of space)
Run: ``docker run -it -v `pwd`:/tmp tt_brand_predictor``

The `func_sim` directory contains a C++ functional simulation of the infrastructure. It parses a log file of a simulated execution of a RISC-V reference program and predicts the branch direction on each branch instruction.
From the `func_sim` directory:
-Compile the reference: `riscv32-unknown-elf-gcc -O0 start.S reference.c -o reference -march=rv32i_zicsr_zifencei -T link.ld -nostartfiles -nostdlib`
-Disassemble reference: `riscv32-unknown-elf-objdump -d reference > reference_dis.txt` (for info only)
-Run Spike on reference: `spike --log=spike_log.txt --log-commits --isa=rv32i_zicsr_zifencei --priv=m -m128 reference` (to generate execution log)
-Make Makefile: `cmake CMakeLists.txt`
-Compile functional simulation: `make`
-Run: `./build/func_sim ./spike_log.txt`

The `tests` directory includes all CocoTB test for this design.
Run them with `make`.

## How to test

Explain how to use your project

## External hardware

List external hardware used in your project (e.g. PMOD, LED display, etc), if any
