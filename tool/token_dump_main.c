#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>

#include "y.tab.h"

int yylex(void);
extern char yytext[];
extern int yyleng;
extern int yylineno;
extern int column;

static const char *token_name(int tok) {
  switch (tok) {
#include "token_cases.inc"
    default:
      return NULL;
  }
}

static void printable_char_token(int tok, char buf[16]) {
  unsigned char ch = (unsigned char)tok;
  if (ch == '\\' || ch == '\'') {
    snprintf(buf, 16, "'%c%c'", '\\', ch);
  } else if (isprint(ch)) {
    snprintf(buf, 16, "'%c'", ch);
  } else {
    snprintf(buf, 16, "'\\x%02X'", ch);
  }
}

static void write_escaped_lexeme(FILE *out, const char *src) {
  const unsigned char *p = (const unsigned char *)src;
  while (*p) {
    unsigned char ch = *p++;
    if (ch == '\\') {
      fputs("\\\\", out);
    } else if (ch == '"') {
      fputs("\\\"", out);
    } else if (ch == '\n') {
      fputs("\\n", out);
    } else if (ch == '\t') {
      fputs("\\t", out);
    } else if (ch == '\r') {
      fputs("\\r", out);
    } else if (ch == ' ') {
      fputs("\\s", out);
    } else {
      fputc((int)ch, out);
    }
  }
}

int main(int argc, char **argv) {
  if (argc != 3) {
    fprintf(stderr, "Usage: %s <input.c> <out.tokens>\n", argv[0]);
    return 1;
  }

  if (!freopen(argv[1], "rb", stdin)) {
    perror("freopen stdin");
    return 1;
  }

  FILE *out = fopen(argv[2], "wb");
  if (!out) {
    perror("open out.tokens");
    return 1;
  }

  int tok;
  while ((tok = yylex()) != 0) {
    const char *name = token_name(tok);
    char char_name_buf[16];
    int tok_col;
    if (!name) {
      if (tok >= 0 && tok < 256) {
        printable_char_token(tok, char_name_buf);
        name = char_name_buf;
      } else {
        fprintf(stderr, "Unknown token id: %d\n", tok);
        fclose(out);
        return 2;
      }
    }

    tok_col = column - yyleng + 1;
    if (tok_col < 1) {
      tok_col = 1;
    }
    fprintf(out, "%s ", name);
    write_escaped_lexeme(out, yytext);
    fprintf(out, " %d %d\n", yylineno, tok_col);
  }

  fclose(out);
  return 0;
}
