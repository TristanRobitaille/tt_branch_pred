#pragma once
#include <stdlib.h>
#include <stdbool.h>
#include <stdio.h>
#include <iostream>
#include <fstream>
#include <cmath>
#include <vector>
#include <regex>

/*----- DEFINES -----*/
// RISC-V ISA branch instruction
#define B_TYPE_INST_MASK 0b1111111 // Opcode is 7 least-significant bits of instruction
#define B_TYPE_OPCODE 0b1100011

// Branch predictor
#define HISTORY_LENGTH 4
#define TRAINING_THRESHOLD 2
#define BIT_WIDTH_WEIGHTS 4 // Must be 2, 4 or 8 so that we can store it in one byte
#define BIT_WIDTH_Y 9

#define STORAGE_B 128
#define STORAGE_PER_PERCEPTRON (HISTORY_LENGTH * BIT_WIDTH_WEIGHTS)
#define NUM_PERCEPTRONS (int)floor(STORAGE_B / STORAGE_PER_PERCEPTRON) 

// Utilities
#define Y_MAX ((1 << (BIT_WIDTH_Y - 1)) - 1)
#define WEIGHT_MAX ((1 << (BIT_WIDTH_WEIGHTS - 1)) - 1)
#define CHECK_OVERFLOW_Y(x)      ((x) > Y_MAX || (x) < (-Y_MAX - 1))
#define CHECK_OVERFLOW_WEIGHT(x) ((x) > WEIGHT_MAX || (x) < (-WEIGHT_MAX - 1))

/*----- CLASSES -----*/
class Perceptron {
    public:
        Perceptron();
        void update(bool branch_direction, const std::vector<bool>& global_history);
        bool predict(const std::vector<bool>& global_history);
        void reset();
    private:
        std::vector<int8_t> weights;
};

class BranchPredictor {
    public:
        BranchPredictor();
        void update(uint32_t branch_address, bool branch_direction);
        bool predict(uint32_t branch_address);
    private:
        uint32_t branch_address_hash(uint32_t branch_address);
        std::vector<Perceptron> perceptrons;
        std::vector<bool> global_history;
};