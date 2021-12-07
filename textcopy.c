/*
 * textcopy.c
 * 
 * Space-expand Nixdorf 8820 text files
 *
 * Reads from stdin, writes to stdout
 *
 * Copyright (c) Klaus Kämpf, 2021
 *
 * License: MIT
 */

#include <stdio.h>

int main()
{
    FILE *in = stdin;
    FILE *out = stdout;
    for (;;) {
        int c;
        c = fgetc(in);
        if (c == EOF) {
            break;
        }
        if (c == 0x1c) { /* LF */
            fputc('\n', out);
            continue;
        }
        if (c == 0x1f) { /* EOF */
            fputc('\n', out);
            break;
        }
        if ((c >= 0x20) && (c < 0x7f)) {
            fputc(c, out);
            continue;
        }
        if (c == 0) {   /* assume 00 00 */
            fgetc(in); /* consume 2nd 00 */
            continue;
        }
        if (c < 0xc8) {
            for (int i = 0x80; i < c; i++) {
                fputc(' ', out);
            }
        }
    }
}
