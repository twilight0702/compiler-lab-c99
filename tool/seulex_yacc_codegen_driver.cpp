#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <iostream>

#include "y.tab.h"

extern "C" int raw_yylex(void);
int yyparse(void);
extern "C" int yyleng;
extern "C" int column;
extern "C" char yytext[];

static FILE* g_tok_out = nullptr;

static const char* token_name(int tok) {
    switch (tok) {
#include "token_cases.inc"
        default:
            return nullptr;
    }
}

static void printable_char_token(int tok, char buf[16]) {
    unsigned char ch = static_cast<unsigned char>(tok);
    if (ch == '\\' || ch == '\'') {
        std::snprintf(buf, 16, "'%c%c'", '\\', ch);
    } else if (std::isprint(ch) != 0) {
        std::snprintf(buf, 16, "'%c'", ch);
    } else {
        std::snprintf(buf, 16, "'\\x%02X'", ch);
    }
}

static void write_escaped_lexeme(FILE* out, const char* s, int len) {
    for (int i = 0; i < len; ++i) {
        unsigned char ch = static_cast<unsigned char>(s[i]);
        if (std::isalnum(ch) != 0 || ch == '_' || std::ispunct(ch) != 0) {
            std::fputc(ch, out);
        } else {
            std::fprintf(out, "\\x%02X", ch);
        }
    }
}

extern "C" int yylex(void) {
    int tok = raw_yylex();
    if (tok == 0 || g_tok_out == nullptr) {
        return tok;
    }

    const char* name = token_name(tok);
    char char_name_buf[16];
    if (name == nullptr) {
        if (tok >= 0 && tok < 256) {
            printable_char_token(tok, char_name_buf);
            name = char_name_buf;
        } else {
            name = "<UNKNOWN>";
        }
    }

    int tok_col = column - yyleng + 1;
    if (tok_col < 1) {
        tok_col = 1;
    }

    std::fprintf(g_tok_out, "%s ", name);
    write_escaped_lexeme(g_tok_out, yytext, yyleng);
    std::fprintf(g_tok_out, " %d %d\n", 0, tok_col);
    return tok;
}

int main(int argc, char** argv) {
    if (argc != 3) {
        std::cerr << "usage: frontend_codegen <input.c> <tokens.out>\n";
        return 2;
    }

    if (!std::freopen(argv[1], "rb", stdin)) {
        std::perror("freopen input");
        return 1;
    }

    g_tok_out = std::fopen(argv[2], "wb");
    if (!g_tok_out) {
        std::perror("fopen tokens");
        return 1;
    }

    int rc = yyparse();
    std::fclose(g_tok_out);
    g_tok_out = nullptr;

    if (rc == 0) {
        std::cout << "frontend_parse_ok\n";
    } else {
        std::cout << "frontend_parse_failed\n";
    }
    return rc;
}
