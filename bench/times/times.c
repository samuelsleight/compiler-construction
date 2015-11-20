#include <stdio.h>

long add_five(long x) {
    return x + 5;
}

long times(unsigned long n, long(*f)(long), long x) {
    long val = x;
    for(int i = 0; i < n; ++i) {
        val = f(val);
    }

    return val;
}

int main() {
    printf("%d\n", times(1000, add_five, 0));
}
