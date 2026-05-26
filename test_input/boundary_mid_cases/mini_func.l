D      [0-9]
ID     [A-Za-z_][A-Za-z0-9_]*
WS     [ \t\r\n]+

%{
#include "y.tab.h"
%}

%%
"int"                  { return INT; }
"for"                  { return FOR; }
"if"                   { return IF; }
"else"                 { return ELSE; }
"return"               { return RETURN; }

"=="                   { return EQ; }
"!="                   { return NE; }
"<="                   { return LE; }
">="                   { return GE; }

{ID}                    { return IDENTIFIER; }
{D}+                    { return NUMBER; }

"{"                    { return '{'; }
"}"                    { return '}'; }
"("                    { return '('; }
")"                    { return ')'; }
";"                    { return ';'; }
","                    { return ','; }
"="                    { return '='; }
"<"                    { return '<'; }
">"                    { return '>'; }
"+"                    { return '+'; }
"-"                    { return '-'; }
"*"                    { return '*'; }
"/"                    { return '/'; }

"//"[^\n]*             { /* skip line comments */ }
"/*"([^*]|\*+[^*/])*\*+"/" { /* skip block comments */ }
{WS}                    { /* skip whitespace */ }
.                       { return yytext[0]; }
%%

int yywrap(void) { return 1; }
