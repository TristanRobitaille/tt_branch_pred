# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import os
import re
import random
import subprocess

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

#----- CONSTANTS -----#
NUM_BITS_OF_INST_ADDR_LATCHED_IN = 8
HISTORY_LENGTH = 7
BIT_WIDTH_WEIGHTS = 8 # Must be 2, 4 or 8
STORAGE_B = 64
STORAGE_PER_PERCEPTRON = ((HISTORY_LENGTH + 1) * BIT_WIDTH_WEIGHTS)
NUM_PERCEPTRONS = (8 * STORAGE_B / STORAGE_PER_PERCEPTRON)

#----- HELPERS -----#
async def reset(dut):
    dut.rst_n.value = 0
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.new_data_avail.value = 0
    dut.direction_ground_truth.value = 0
    dut.inst_lowest_byte.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1

async def reset_memory(dut):
    for i in range(STORAGE_B):
        dut.branch_pred.mem_data_in.value = 0
        dut.branch_pred.wr_en.value = 1 # Write
        dut.branch_pred.mem_addr.value = i
        await RisingEdge(dut.clk) # Wait for write to complete
        await RisingEdge(dut.clk) # Cycle after write can't be used
    dut.branch_pred.wr_en.value = 0
    dut.branch_pred.mem_addr.value = 0

def start_clock(dut):
    clock = Clock(dut.clk, 100, units="ns") # 10MHz
    cocotb.start_soon(clock.start())

async def send_data(dut, addr, direction):
    dut.inst_lowest_byte.value = addr
    dut.direction_ground_truth.value = direction
    dut.new_data_avail.value = 1
    await RisingEdge(dut.clk)
    dut.new_data_avail.value = 0
    await RisingEdge(dut.clk)

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

def twos_complement_to_int(binary_str, width):
    """Convert two's complement binary string to signed integer."""
    value = int(binary_str, 2)
    if value & (1 << (width - 1)):  # If sign bit is set
        inverted = value ^ ((1 << width) - 1)
        return -(inverted + 1)
    return value

async def check_weights(dut, starting_addr, weights):
    initial_wr_en = dut.branch_pred.wr_en.value
    initial_mem_addr = dut.branch_pred.mem_addr.value    
    initial_uio_in = dut.branch_pred.latch_mem.uio_in.value
    await RisingEdge(dut.clk)

    for i in range(len(weights)):
        dut.branch_pred.wr_en.value = 0 # Read
        dut.branch_pred.mem_addr.value = starting_addr + i
        await ClockCycles(dut.clk, 2)
        value = str(dut.branch_pred.mem_data_out.value)
        assert twos_complement_to_int(value, len(value)) == weights[i]
    
    dut.branch_pred.wr_en.value = initial_wr_en
    dut.branch_pred.mem_addr.value = initial_mem_addr
    dut.branch_pred.latch_mem.uio_in.value = initial_uio_in

# @cocotb.test()
# async def test_constants(dut):
    start_clock(dut)
    await RisingEdge(dut.clk)
    assert dut.uio_oe.value == 0 # All bidirectional pins should be in input mode

@cocotb.test()
async def test_new_data_avail_signals(dut):
    start_clock(dut)
    await reset(dut)

    dut.new_data_avail.value = 1
    await RisingEdge(dut.clk)
    dut.new_data_avail.value = 0
    assert dut.new_data_avail_posedge.value == 1
    await RisingEdge(dut.clk)
    assert dut.new_data_avail_posedge.value == 0
    assert dut.branch_pred.new_data_avail_prev.value == 1
    await RisingEdge(dut.clk)
    assert dut.branch_pred.new_data_avail_prev.value == 0

@cocotb.test()
async def test_send_data(dut):
    NUM_TESTS = 100
    random.seed(42)

    start_clock(dut)
    await reset(dut)

    for _ in range(NUM_TESTS):
        direction = random.randint(0, 1)
        addr = random.randint(0, 2**NUM_BITS_OF_INST_ADDR_LATCHED_IN - 1)
        await send_data(dut, addr, direction)
        assert dut.branch_pred.direction_ground_truth.value == direction
        assert dut.branch_pred.inst_addr.value == addr

@cocotb.test()
async def test_perceptron_index(dut):
    NUM_TESTS = 100
    random.seed(42)

    start_clock(dut)
    await reset(dut)

    for _ in range(NUM_TESTS):
        direction = random.randint(0, 1)
        addr = random.randint(0, 2**NUM_BITS_OF_INST_ADDR_LATCHED_IN - 1)
        await send_data(dut, addr, direction)
        assert int(f"{dut.branch_pred.perceptron_index.value}", base=2) == ((addr >> 2) % NUM_PERCEPTRONS)

@cocotb.test()
async def test_history_buffer(dut):
    NUM_TESTS = -1
    random.seed(42)
    history_buffer = [0] * HISTORY_LENGTH

    start_clock(dut)
    await reset(dut)

    for _ in range(NUM_TESTS):
        direction = random.randint(0, 1)
        # Make FIFO-like history buffer
        history_buffer.pop(0)
        history_buffer.append(direction)
        binary_str = ''.join(str(x) for x in history_buffer)

        await send_data(dut, addr=0, direction=direction)
        while (dut.branch_pred.training_done.value != 1):
            await RisingEdge(dut.clk)
        await RisingEdge(dut.clk)
        assert dut.branch_pred.history_buffer.value == int(binary_str, base=2)

@cocotb.test()
async def test_perceptron_all_registers(dut):
    MAX_NUM_TESTS = -1
    cnt = 0
    start_clock(dut)
    await reset(dut)
    await reset_memory(dut)

    # Run functional sim and capture output
    # Make functional sim
    os.chdir("../func_sim")
    subprocess.run(["cmake", "CMakeLists.txt"], check=True)
    subprocess.run(["make"], check=True)
    os.chdir("../test")
    cmd = ["../func_sim/build/func_sim", "../func_sim/spike_log.txt"]
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, universal_newlines=True)
    stdout = process.communicate()
    for line in stdout[0].splitlines():
        if line.startswith("Branch address:"):
            result = parse_branch_log(line)
            print(result)
            addr = (result['address'] & 0xFF)
            direction = result['taken']
            await send_data(dut, addr=addr, direction=direction)

            assert int(f"{dut.branch_pred.perceptron_index.value}", base=2) == result['hash_index'] # Check index
            assert int(f"{dut.branch_pred.mem_addr.value}", base=2) == result['start_addr'] # Check memory addr

            while (dut.pred_ready.value != 1):
                await RisingEdge(dut.clk)
            assert dut.prediction.value == result['prediction']
            assert twos_complement_to_int(f"{dut.branch_pred.sum.value}", len(dut.branch_pred.sum.value)) == result['y']

            while (dut.training_done.value != 1):
                await RisingEdge(dut.clk)

            # Check the weights (Perform with and without checking the weights)
            await check_weights(dut, result['start_addr'], result['weights'])
            
            cnt += 1
            if (MAX_NUM_TESTS != -1) and (cnt >= MAX_NUM_TESTS):
                break
