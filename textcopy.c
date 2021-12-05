#include <stdio.h>

int main()
{
    FILE *in = stdin;
    FILE *out = stdout;
    int in_file;
    in_file = 1;
    while (in_file) {
        int c;
        unsigned char head[3];
        int in_line;
        int ll; /* line length */
        if (fread(head, sizeof(unsigned char), 3, in) < 3)
            break;
/*        for (int i = 0; i < 3; i++)
            fprintf(out, "%02x ", head[i]);
 */
        if (head[2] == 0x1f) { /* EOF */
            in_file = 0;
            break;
        }
        in_line = 1;
        ll = 0;
        while (in_line) {
            c = fgetc(in);
            if (c == EOF) {
                in_file = 0;
                break;
            }
            if ((c >= 0x20) && (c < 0x7f)) {
                ll++;
                fputc(c, out);
            }
            else if (c == 0) {
                ungetc(c, in);
                fputc('\n', out);
                in_line = 0;
            }
            else if (ll == 0) {
                if (c < 0xc8) {
                    for (int i = 0x80; i < c; i++) {
                        ll++;
                        fputc(' ', out);
                    }
                }
                else if (c == 0xc8) {
                    fputc('\n', out);
                    in_line = 0;
                }
                else {
                    fprintf(out, "[%02x]", c);
                }
            }
            else if (c < 0x89) {
                for (int i = 0x80; i < c; i++) {
                    ll++;
                    fputc(' ', out);
                }
            }
            else {
//                    fprintf(out, ">%d/%02x<\n", ll,  c);
                    fputc('\n', out);
                    in_line = 0;                
            }
        }
    }
}
