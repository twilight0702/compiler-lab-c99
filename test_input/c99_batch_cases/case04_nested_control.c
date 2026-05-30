int main(void) {
    int i = 0;
    int j = 0;
    int acc = 0;

    for (i = 0; i < 5; i = i + 1) {
        j = 0;
        while (j < 3) {
            if ((i + j) > 3) {
                acc = acc + i;
            } else {
                acc = acc + j;
            }
            j = j + 1;
        }
    }

    return acc;
}
