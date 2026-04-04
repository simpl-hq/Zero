#include "hs_init.h"

extern void hs_init_with_rtsopts(int * argc, char **argv[]);

void haskell_init(void) {
    int argc = 5;
    char *argv[] = {
        "zero",
        "+RTS",
        "-A64m",
        "-H64m",
        "-xn",
        0
    };
    char **pargv = argv;
    hs_init_with_rtsopts(&argc, &pargv);
}

void haskell_init_nse(void) {
    int argc = 7;
    char *argv[] = {
        "zero",
        "+RTS",
        "-A256k",
        "-H512k",
        "-F0.5",
        "-Fd0.3",
        "-c",
        0
    };
    char **pargv = argv;
    hs_init_with_rtsopts(&argc, &pargv);
}

void haskell_init_se(void) {
    int argc = 7;
    char *argv[] = {
        "zero",
        "+RTS",
        "-A1m",
        "-H1m",
        "-F0.5",
        "-Fd1",
        "-c",
        0
    };
    char **pargv = argv;
    hs_init_with_rtsopts(&argc, &pargv);
}
