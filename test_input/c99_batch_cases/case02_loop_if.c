int sum_to_n(int n) {
    int i = 0;
    int sum = 0;
    while (i <= n) {
        if (i % 2 == 0) {
            sum = sum + i;
        }
        i = i + 1;
    }
    return sum;
}

int main(void) {
    int ans = sum_to_n(10);
    return ans;
}
