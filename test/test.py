# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import random
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

#----- CONSTANTS -----#
NUM_BITS_OF_INST_ADDR_LATCHED_IN = 16
HISTORY_LENGTH = 16
BIT_WIDTH_WEIGHTS = 8 # Must be 2, 4 or 8
STORAGE_B = 128 # Ensure this is a multiple of STORAGE_PER_PERCEPTRON
STORAGE_PER_PERCEPTRON = (HISTORY_LENGTH * BIT_WIDTH_WEIGHTS)
NUM_PERCEPTRONS = (STORAGE_B / STORAGE_PER_PERCEPTRON)

#----- HELPERS -----#
async def reset(dut):
    dut.rst_n.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.spi_cs.value = 0
    dut.spi_mosi.value = 0
    await ClockCycles(dut.spi_clk, 5)
    dut.spi_cs.value = 1
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

async def clear_spi_registers(dut):
    dummy_addr = 0x0000
    dummy_direction = 0
    await send_spi_data(dut, dummy_addr, dummy_direction)

def start_clocks(dut):
    clock = Clock(dut.clk, 100, units="ns") # 10MHz
    spi_clock = Clock(dut.spi_clk, 1000, units="ns") # 1MHz
    cocotb.start_soon(clock.start())
    cocotb.start_soon(spi_clock.start())

@cocotb.test()
async def test_constants(dut):
    start_clocks(dut)
    await RisingEdge(dut.clk)
    assert dut.uio_oe.value == 0 # All bidirectional pins should be in input mode

@cocotb.test()
async def test_reset(dut):
    start_clocks(dut)
    await reset(dut)

    # TODO: Add more tests

async def send_spi_data(dut, addr, direction):
    await RisingEdge(dut.spi_clk)
    dut.spi_cs.value = 0
    for i in range(NUM_BITS_OF_INST_ADDR_LATCHED_IN):
        await RisingEdge(dut.spi_clk)
        dut.spi_mosi.value = (addr >> (15 - i)) & 0x1
    dut.spi_cs.value = 1
    await RisingEdge(dut.spi_clk)
    dut.spi_mosi.value = direction

@cocotb.test()
async def test_spi(dut):
    NUM_TESTS = 100
    random.seed(42)

    start_clocks(dut)
    await reset(dut)

    # First transmit is to clear SPI registers (since we don't reset)
    await clear_spi_registers(dut)

    for _ in range(NUM_TESTS):
        direction = random.randint(0, 1)
        addr = random.randint(0, 2**NUM_BITS_OF_INST_ADDR_LATCHED_IN - 1)
        await send_spi_data(dut, addr, direction)
        while (dut.branch_pred.data_input_done.value != 1):
            await RisingEdge(dut.clk)
        assert dut.branch_pred.direction_ground_truth.value == direction
        assert dut.direction_ground_truth.value == direction
        assert dut.branch_pred.inst_addr.value == addr
        assert dut.data_input_done.value == 1
        await ClockCycles(dut.clk, 1)
        assert dut.data_input_done.value == 0

    await ClockCycles(dut.spi_clk, 10)

@cocotb.test()
async def test_perceptron_index(dut):
    NUM_TESTS = 100
    random.seed(42)

    start_clocks(dut)
    await reset(dut)

    for _ in range(NUM_TESTS):
        direction = random.randint(0, 1)
        addr = random.randint(0, 2**NUM_BITS_OF_INST_ADDR_LATCHED_IN - 1)
        await send_spi_data(dut, addr, direction)
        await send_spi_data(dut, addr, direction)
        while (dut.branch_pred.data_input_done.value != 1):
            await RisingEdge(dut.clk)
        assert dut.branch_pred.perceptron_index.value == ((addr >> 2) % NUM_PERCEPTRONS)