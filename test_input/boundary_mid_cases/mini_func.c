int add(int x, int y) {
    return x + y;
}

int mix(int base) {
    int i = 0;
    int sum = 0;

    for (i = 0; i < 5; i = i + 1) {
        if (i == 3) {
            sum = sum + add(base, i * 2);
        } else {
            sum = sum + add(base, i);
        }
    }

    return sum;
}

int main() {
    int ans = mix(4);
    if (ans >= 30) {
        ans = ans - add(1, 2);
    }
    return ans;
}
