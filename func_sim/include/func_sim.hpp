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
#define HISTORY_LENGTH 7 // Must be power of 2 - 1
#define TRAINING_THRESHOLD 15
#define BIT_WIDTH_WEIGHTS 8 // Must be 2, 4 or 8 so that we can store it in one byte
#define BIT_WIDTH_Y (int)ceil(log2(HISTORY_LENGTH * (1 << (BIT_WIDTH_WEIGHTS-1))))

#define STORAGE_B 64
#define STORAGE_PER_PERCEPTRON ((HISTORY_LENGTH + 1) * BIT_WIDTH_WEIGHTS)
#define NUM_PERCEPTRONS (int)floor(8 * STORAGE_B / STORAGE_PER_PERCEPTRON) 

// Utilities
#define Y_MAX                    ((1 << (BIT_WIDTH_Y - 1)) - 1)
#define WEIGHT_MAX               ((1 << (BIT_WIDTH_WEIGHTS - 1)) - 1)
#define CHECK_OVERFLOW_Y(x)      ((x) > Y_MAX || (x) < (-Y_MAX - 1))
#define CHECK_OVERFLOW_WEIGHT(x) ((x) > WEIGHT_MAX || (x) < (-WEIGHT_MAX - 1))

/*----- CLASSES -----*/
class Perceptron {
    public:
        Perceptron();
        bool update(bool branch_direction, const std::vector<bool>& global_history);
        void predict(const std::vector<bool>& global_history, bool *pred, int *y_sum);
        void reset();
        std::vector<int> get_weights();
    private:
        std::vector<int> weights;
};

class BranchPredictor {
    public:
        BranchPredictor();
        bool update(uint32_t branch_address, bool branch_direction);
        void predict(uint32_t branch_address, bool* pred, int* y_sum, int* hash_index);
        std::string get_perceptron_weights(int index);
    private:
        uint32_t branch_address_hash(uint32_t branch_address);
        std::vector<Perceptron> perceptrons;
        std::vector<bool> global_history;
};