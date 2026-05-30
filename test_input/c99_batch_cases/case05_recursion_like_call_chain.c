int inc(int x) { return x + 1; }
int dec(int x) { return x - 1; }

int chain(int n) {
    int r = n;
    r = inc(r);
    r = inc(r);
    r = dec(r);
    return r;
}

int main(void) {
    int v = chain(41);
    return v;
}
