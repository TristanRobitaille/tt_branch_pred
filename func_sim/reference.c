__attribute__((section(".data")))
int numbers[] = {1, -2, 3, 4, -5, 6, -7, 8, -9, 10, 1, -2, 3, 4, -5, 6, -7, 8, -9, 10};

int calculate_sum(int *arr, int size) {
    int sum = 0;
    for (int i = 0; i < size; i++) {
        sum += arr[i];
        if (arr[i] < 0) {
            sum -= 1; // Adjust sum if the number is negative
        }
        if ((i & 1) == 0) {  // Replace i % 2 with bitwise AND
            sum += 3; // Add 3 if the index is even
        }
    }
    return sum;
}

int main() {
    int total = 0;
    int size = sizeof(numbers) / sizeof(numbers[0]);

    for (int j = 0; j < 10; j++) {
        total += numbers[j & (size-1)];  // Replace j % size with bitwise AND

        for (int i = 0; i < size; i++) {
            total += numbers[i];
            if (i > 2) {
                total += 2;
            }
            if ((i & 3) == 0) {  // Replace i % 3 with a different condition
                total -= 1;
            }
        }

        if (total < 0) {
            total = -1 * total;
        }

        if (total > 10) {
            total = total / 2;
        }

        total = calculate_sum(numbers, size);

        if ((total & 1) == 0) {  // Replace total % 2 with bitwise AND
            total += 5;
        } else {
            total -= 3;
        }

        if ((j & 1) == 0) {  // Replace j % 2 with bitwise AND
            total *= 2;
        } else {
            total /= 2;
        }
    }
    return 0;
}