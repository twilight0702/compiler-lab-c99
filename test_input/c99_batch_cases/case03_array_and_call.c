int mul_add(int a, int b, int c) {
    return a * b + c;
}

int main(void) {
    int arr[3] = {2, 4, 6};
    int x = mul_add(arr[0], arr[1], arr[2]);
    return x;
}
