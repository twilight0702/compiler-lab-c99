#include <stdio.h>

int sum_array(int arr[], int n)
{
    int sum = 0;
    int i;

    for (i = 0; i < n; i++) {
        sum = sum + arr[i];
    }

    return sum;
}

int max_array(int arr[], int n)
{
    int max = arr[0];
    int i;

    for (i = 1; i < n; i++) {
        if (arr[i] > max) {
            max = arr[i];
        }
    }

    return max;
}

int count_even(int arr[], int n)
{
    int count = 0;
    int i;

    for (i = 0; i < n; i++) {
        if (arr[i] % 2 == 0) {
            count++;
        }
    }

    return count;
}

void print_odd_even(int arr[], int n)
{
    int i;

    for (i = 0; i < n; i++) {
        if (arr[i] % 2 == 0) {
            printf("%d is even\n", arr[i]);
        } else {
            printf("%d is odd\n", arr[i]);
        }
    }
}

int main(void)
{
    int numbers[5] = {3, 8, 2, 7, 10};
    int n = 5;

    int sum = sum_array(numbers, n);
    int max = max_array(numbers, n);
    int even_count = count_even(numbers, n);

    printf("sum = %d\n", sum);
    printf("max = %d\n", max);
    printf("even count = %d\n", even_count);

    print_odd_even(numbers, n);

    return 0;
}