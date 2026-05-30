int sum_ptr_array(int *p, int n) {
    int i = 0;
    int acc = 0;
    while (i < n) {
        if (*(p + i) > 0) {
            acc = acc + *(p + i);
        } else {
            acc = acc - 1;
        }
        i = i + 1;
    }
    return acc;
}

int main(void) {
    int arr[4] = {3, -2, 5, 0};
    int *p = arr;
    int r = sum_ptr_array(p, 4);
    return r;
}
