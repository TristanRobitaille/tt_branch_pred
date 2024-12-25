# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import re
import random
import subprocess

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

#----- CONSTANTS -----#
NUM_BITS_OF_INST_ADDR_LATCHED_IN = 16
HISTORY_LENGTH = 15
BIT_WIDTH_WEIGHTS = 8 # Must be 2, 4 or 8
STORAGE_B = 128
STORAGE_PER_PERCEPTRON = ((HISTORY_LENGTH + 1) * BIT_WIDTH_WEIGHTS)
NUM_PERCEPTRONS = (8 * STORAGE_B / STORAGE_PER_PERCEPTRON)

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

async def send_spi_data(dut, addr, direction):
    await RisingEdge(dut.spi_clk)
    dut.spi_cs.value = 0
    for i in range(NUM_BITS_OF_INST_ADDR_LATCHED_IN):
        await RisingEdge(dut.spi_clk)
        dut.spi_mosi.value = (addr >> (15 - i)) & 0x1
    dut.spi_cs.value = 1
    await RisingEdge(dut.spi_clk)
    dut.spi_mosi.value = direction

def parse_branch_log(line):
    pattern = r"""
    Branch\saddress:\s*(?P<addr>[0-9a-fA-F]+),\s*
    Hash\sindex:\s*(?P<hash>\d+),\s*
    Starting\saddress:\s*(?P<start_addr>\d+),\s*
    Branch\sTaken:\s*(?P<taken>\d+),\s*
    Prediction:\s*(?P<pred>\d+),\s*
    Y:\s*(?P<y>-?\d+),\s*
    Weights\safter\straining:\s*(?P<weights>[-\d,\s]+)
    """
    match = re.search(pattern, line, re.VERBOSE)
    if match:
        return {
            'address': int(match.group('addr'), 16),
            'hash_index': int(match.group('hash')),
            'start_addr': int(match.group('start_addr')),
            'taken': bool(int(match.group('taken'))),
            'prediction': bool(int(match.group('pred'))),
            'y': int(match.group('y')),
            'weights': [int(x) for x in match.group('weights').strip().split(',') if x.strip()]
        }
    return None

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
        while (dut.branch_pred.data_input_done.value != 1):
            await RisingEdge(dut.clk)
        assert int(f"{dut.branch_pred.perceptron_index.value}", base=2) == ((addr >> 2) % NUM_PERCEPTRONS)

@cocotb.test()
async def test_history_buffer(dut):
    NUM_TESTS = 100
    random.seed(42)
    history_buffer = [0] * HISTORY_LENGTH

    start_clocks(dut)
    await reset(dut)

    for _ in range(HISTORY_LENGTH):
        await send_spi_data(dut, addr=0x0, direction=0) # Fill history with 0s

    for _ in range(NUM_TESTS):
        direction = random.randint(0, 1)
        # Make FIFO-like history buffer
        history_buffer.pop(0)
        history_buffer.append(direction)
        binary_str = ''.join(str(x) for x in history_buffer)

        await send_spi_data(dut, addr=0, direction=direction)
        while (dut.branch_pred.data_input_done.value != 1):
            await RisingEdge(dut.clk)
        await RisingEdge(dut.clk)
        assert dut.branch_pred.history_buffer.value == int(binary_str, base=2)

@cocotb.test()
async def test_perceptron_weights(dut):
    start_clocks(dut)
    await reset(dut)

    for _ in range(HISTORY_LENGTH):
        await send_spi_data(dut, addr=0x0, direction=0) # Fill history with 0s

    # Run functional sim and capture output
    cmd = ["../func_sim/build/func_sim", "../func_sim/spike_log.txt"]
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, universal_newlines=True)
    stdout = process.communicate()
    for line in stdout[0].splitlines():
        if line.startswith("Branch address:"):
            result = parse_branch_log(line)
            addr = (result['address'] & 0xFF)
            hash_index = (addr >> 2) % NUM_PERCEPTRONS
            direction = result['taken']
            await send_spi_data(dut, addr=addr, direction=direction)
            while (dut.branch_pred.data_input_done.value != 1):
                await RisingEdge(dut.clk)

            # Check index
            assert int(f"{dut.branch_pred.perceptron_index.value}", base=2) == hash_index

            # Check memory addr
            await RisingEdge(dut.clk)
            assert int(f"{dut.branch_pred.mem_addr.value}", base=2) == result['start_addr']

            while (dut.branch_pred.pred_ready.value != 1):
                await RisingEdge(dut.clk)
            # TODO: Check sum
            # TODO: Check prediction
