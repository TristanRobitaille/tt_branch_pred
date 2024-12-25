#include "func_sim.hpp"

using namespace std;

/*----- PERCEPTRON -----*/
Perceptron::Perceptron() : weights(HISTORY_LENGTH+1, 0) { }

void Perceptron::reset() {
    fill(weights.begin(), weights.end(), 0);
}

void Perceptron::predict(const std::vector<bool>& global_history, bool* pred, int* y_sum) {
    int32_t y = weights[0];

    // Compute the weighted sum of the global history values.
    for (size_t i = 1; i < HISTORY_LENGTH+1; i++) {
        y += weights[i] * global_history[i-1];
        
        // Check for overflow in y and wrap around if necessary (to simulate hardware)
        if (CHECK_OVERFLOW_Y(y)) {
            cout << "Overflow in y: " << dec << (int)y << endl;
            if (y > 0) {
                int32_t overflow_amount = y - Y_MAX;
                y = (-Y_MAX - 1) + (overflow_amount - 1);
            } else {
                int32_t overflow_amount = abs(y) - (Y_MAX + 1);
                y = Y_MAX - (overflow_amount - 1);
            }
        }
    }
    *pred = (y >= 0); // Taken if greater than or equal to 0
    *y_sum = y;
}

bool Perceptron::update(bool branch_direction, const vector<bool>& global_history) {
    bool pred = false;
    int y = 0;
    predict(global_history, &pred, &y);

    int t = branch_direction ? 1 : -1;

    // If the prediction is incorrect or the absolut e value of the weighted sum (y; "confidence") is
    // less than or equal to the threshold, adjust the weights.

    if (pred != branch_direction || abs(y) <= TRAINING_THRESHOLD) {
        weights[0] += t;
        for (size_t i = 1; i <= HISTORY_LENGTH; i++) {  // HISTORY_LENGTH = 7
            // Map weight[i] to global_history[i-1]
            int x_i = global_history[i - 1] ? 1 : -1;

            // Update weight
            weights[i] += t * x_i;

            // Check for overflow in weight and wrap around if necessary (to simulate hardware)
            if (CHECK_OVERFLOW_WEIGHT(weights[i])) {
                cout << "Overflow in weight: " << dec << (int)weights[i] << endl;
                if (weights[i] > 0) {
                    int32_t overflow_amount = weights[i] - WEIGHT_MAX;
                    weights[i] = (-WEIGHT_MAX - 1) + (overflow_amount - 1);
                } else {
                    int32_t overflow_amount = abs(weights[i]) - (WEIGHT_MAX + 1);
                    weights[i] = WEIGHT_MAX - (overflow_amount - 1);
                }
            }
        
        }
        return true;
    }
    return false;
}

vector<int> Perceptron::get_weights() {
    return weights;
}

/*----- BRANCH PREDICTOR -----*/
BranchPredictor::BranchPredictor() : perceptrons(NUM_PERCEPTRONS), global_history(HISTORY_LENGTH, false) {
    for (auto& perceptron : perceptrons) {
        perceptron.reset();
    }
}

uint32_t BranchPredictor::branch_address_hash(uint32_t branch_address) {
    return (branch_address >> 2) % NUM_PERCEPTRONS;
}

void BranchPredictor::predict(uint32_t branch_address, bool* pred, int* y_sum, int* hash_index) {
    uint32_t index = branch_address_hash(branch_address);
    *hash_index = index;
    perceptrons[index].predict(global_history, pred, y_sum);
}

bool BranchPredictor::update(uint32_t branch_address, bool branch_direction) {
    uint32_t index = branch_address_hash(branch_address);
    bool trained = perceptrons[index].update(branch_direction, global_history);

    // Updates the global history by shifting it and inserting the latest branch outcome.
    for (size_t i = HISTORY_LENGTH - 1; i > 0; i--) {
        global_history[i] = global_history[i - 1];
    }
    global_history[0] = branch_direction;

    return trained;
}

string BranchPredictor::get_perceptron_weights(int index) {
    string weights = "";
    vector<int> perceptron_weights = perceptrons[index].get_weights();
    for (size_t i = 0; i < HISTORY_LENGTH+1; i++) {
        weights += to_string(perceptron_weights[i]) + ", ";
    }
    return weights;
}

int main(int argc, char** argv) {
    if (BIT_WIDTH_WEIGHTS != 2 && BIT_WIDTH_WEIGHTS != 4 && BIT_WIDTH_WEIGHTS != 8 && BIT_WIDTH_WEIGHTS != 16) {
        cerr << "BIT_WIDTH_WEIGHTS must be 2, 4 or 8" << endl;
        return 1;
    }

    cout << "NUM_PERCEPTRONS: " << NUM_PERCEPTRONS << endl;
    cout << "STORAGE_PER_PERCEPTRON: " << STORAGE_PER_PERCEPTRON << endl;
    cout << "WEIGHT_MAX: " << WEIGHT_MAX << endl;

    if (argc != 2) {
        printf("Usage: %s <file.txt>\n", argv[0]);
        return 1;
    }

    // Initialize the branch predictor
    BranchPredictor branch_predictor;
    uint32_t total_branches = 0;
    uint32_t correct_predictions = 0;

    // Open the text file
    ifstream file(argv[1]);
    if (!file.is_open()) {
        cerr << "Error opening file: " << argv[1] << endl;
        return 1;
    }

    // Define a regex pattern to match the branch address and instruction
    regex pattern(R"(core\s+\d+:\s+\d+\s+(0x[0-9a-fA-F]+)\s+\((0x[0-9a-fA-F]+)\))");
    smatch matches;

    vector<uint32_t> branch_addresses; // Store branch addresses to determine branch outcomes
    vector<uint32_t> instructions; // Store instructions for B-type check

    // Read and parse each line from the file
    string line;
    while (getline(file, line)) {
        if (regex_search(line, matches, pattern)) {
            if (matches.size() == 3) { // Ensure we have two capture groups
                uint32_t branch_addr = stoul(matches[1].str(), nullptr, 16);
                uint32_t instruction = stoul(matches[2].str(), nullptr, 16);
                branch_addresses.push_back(branch_addr);
                instructions.push_back(instruction);
            }
        }
    }
    file.close();

    // Determine branch outcomes and use the branch predictor
    for (size_t i = 0; i < branch_addresses.size() - 1; ++i) {
        uint32_t current_branch_addr = branch_addresses[i];
        uint32_t next_branch_addr = branch_addresses[i + 1];
        uint32_t instruction = instructions[i];

        // Check if the instruction is a B-type instruction
        if ((instruction & B_TYPE_INST_MASK) == B_TYPE_OPCODE) {
            bool branch_taken = (next_branch_addr != current_branch_addr + 4); // Branch taken if next address is not current address + 4

            // Predict branch direction
            bool prediction = false;
            int y = 0;
            int hash_index;
            branch_predictor.predict(current_branch_addr, &prediction, &y, &hash_index);

            // Update the branch predictor with the actual outcome
            bool trained = branch_predictor.update(current_branch_addr, branch_taken);

            string weights = branch_predictor.get_perceptron_weights(hash_index);

            cout << "Branch address: " << hex << current_branch_addr
                 << ", \tHash index: " << dec << hash_index
                 << ", \tStarting address: " << dec << (STORAGE_PER_PERCEPTRON/8 * hash_index)
                 << ", \tBranch Taken: " << branch_taken
                 << ", \tPrediction: " << prediction
                 << ", \tY: " << dec << y
                 << ", \t\tWeights after training: " << weights
                 << ", \tTrained: " << trained << endl;

            total_branches++;
            if (branch_taken == prediction) {
                correct_predictions++;
            }
        }
    }

    float accuracy = (float)correct_predictions / total_branches;
    cout << "Accuracy: " << accuracy << endl;

    return 0;
}