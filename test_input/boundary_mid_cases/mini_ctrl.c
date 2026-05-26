int main() {
    int a = 3;
    int b = 10;
    int acc = 0;

    while (a < b && b != 0) {
        if ((a + 1) * 2 <= b) {
            acc = acc + a;
            a = a + 2;
        } else {
            acc = acc - 1;
            b = b - 1;
        }
    }

    if (acc > 5 || a == b) {
        acc = acc + 100;
    } else {
        acc = -acc;
    }

    return acc;
}
