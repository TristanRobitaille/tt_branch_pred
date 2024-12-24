/*
A simple test program to be compiled into a RISC-V binary to test the functional simulator and testbench the design.
*/

__attribute__((section(".data")))
int numbers[] = {1, -2, 3, 4, -5};

int main() {
    // This code calculates the sum of an array of integers, and if the sum is negative, it converts it to its absolute value.
    int total = 0;
    int size = sizeof(numbers) / sizeof(numbers[0]);

    for (int j = 0; j < 10; j++) {
        total += numbers[2];

        for (int i = 0; i < size; i++) {
            total += numbers[i];
            if (i > 2) {
                total += 2;
            }
        }

        if (total < 0) {
            total = -1 * total;
        }

        if (total > 10) {
            total = total / 2;
        }
    }
    return 0;
}