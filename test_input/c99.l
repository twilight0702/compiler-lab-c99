/* Regular Definition，不构成完整的词法单元，没有对应的action */
D			[0-9]
L			[a-zA-Z_]   /* 字母 */
H			[a-fA-F0-9]  /* 十六进制数 */
E			([Ee][+-]?{D}+)    /* 十进制数的指数部分 */
P           ([Pp][+-]?{D}+)  /* 十六进制数的指数部分 */
FS			(f|F|l|L)     /*浮点数后缀*/
IS          ((u|U)|(u|U)?(l|L|ll|LL)|(l|L|ll|LL)(u|U))  /*无符号数，长整数的后缀 */

%{
#include <stdio.h>
#include "y.tab.h"

void count(void);   /* 计算词法元素所占用的列，在规则部分被使用，函数体在第二个%%之后 */
%}

%%
"/*"			{ comment(); }
"//"[^\n]*              { /* consume //-comment */ }


"auto"			{ count(); return(AUTO); }
"_Bool"			{ count(); return(BOOL); }
"break"			{ count(); return(BREAK); }
"case"			{ count(); return(CASE); }
"char"			{ count(); return(CHAR); }
"_Complex"		{ count(); return(COMPLEX); }
"const"			{ count(); return(CONST); }
"continue"		{ count(); return(CONTINUE); }
"default"		{ count(); return(DEFAULT); }
"do"			{ count(); return(DO); }
"double"		{ count(); return(DOUBLE); }
"else"			{ count(); return(ELSE); }
"enum"			{ count(); return(ENUM); }
"extern"		{ count(); return(EXTERN); }
"float"			{ count(); return(FLOAT); }
"for"			{ count(); return(FOR); }
"goto"			{ count(); return(GOTO); }
"if"			{ count(); return(IF); }
"_Imaginary"		{ count(); return(IMAGINARY); }
"inline"		{ count(); return(INLINE); }
"int"			{ count(); return(INT); }
"long"			{ count(); return(LONG); }
"register"		{ count(); return(REGISTER); }
"restrict"		{ count(); return(RESTRICT); }
"return"		{ count(); return(RETURN); }
"short"			{ count(); return(SHORT); }
"signed"		{ count(); return(SIGNED); }
"sizeof"		{ count(); return(SIZEOF); }
"static"		{ count(); return(STATIC); }
"struct"		{ count(); return(STRUCT); }
"switch"		{ count(); return(SWITCH); }
"typedef"		{ count(); return(TYPEDEF); }
"union"			{ count(); return(UNION); }
"unsigned"		{ count(); return(UNSIGNED); }
"void"			{ count(); return(VOID); }
"volatile"		{ count(); return(VOLATILE); }
"while"			{ count(); return(WHILE); }

[A-Za-z_][A-Za-z0-9_]*	{ count(); return(check_type()); }                   /* identifier, 也可能是保留字*/

0[xX]{H}+{IS}?		{ count(); return(CONSTANT); }             /* 16进制数 */
0[0-7]*{IS}?		{ count(); return(CONSTANT); }             /* 8进制数 */
[1-9]{D}*{IS}?		{ count(); return(CONSTANT); }             /* 10进制数 */
L?'(\\.|[^\\'\n])+'	{ count(); return(CONSTANT); }             // 6.4.4.4 Character constants p59

{D}+{E}{FS}?		{ count(); return(CONSTANT); }              /* 10进制浮点数 */  
{D}*"."{D}+{E}?{FS}?	{ count(); return(CONSTANT); }          /* 10进制浮点数 */  
{D}+"."{D}*{E}?{FS}?	{ count(); return(CONSTANT); }          /* 10进制浮点数 */  
0[xX]{H}+{P}{FS}?	{ count(); return(CONSTANT); }               /* 16进制浮点数 */  
0[xX]{H}*"."{H}+{P}?{FS}?     { count(); return(CONSTANT); }     /* 16进制浮点数 */ 
0[xX]{H}+"."{H}*{P}?{FS}?     { count(); return(CONSTANT); }     /* 16进制浮点数 */ 


L?\"(\\.|[^\\"\n])*\"	{ count(); return(STRING_LITERAL); }  // 6.4.5 String literals p62

"..."			{ count(); return(ELLIPSIS); }
">>="			{ count(); return(RIGHT_ASSIGN); }
"<<="			{ count(); return(LEFT_ASSIGN); }
"+="			{ count(); return(ADD_ASSIGN); }
"-="			{ count(); return(SUB_ASSIGN); }
"*="			{ count(); return(MUL_ASSIGN); }
"/="			{ count(); return(DIV_ASSIGN); }
"%="			{ count(); return(MOD_ASSIGN); }
"&="			{ count(); return(AND_ASSIGN); }
"^="			{ count(); return(XOR_ASSIGN); }
"|="			{ count(); return(OR_ASSIGN); }
">>"			{ count(); return(RIGHT_OP); }
"<<"			{ count(); return(LEFT_OP); }
"++"			{ count(); return(INC_OP); }
"--"			{ count(); return(DEC_OP); }
"->"			{ count(); return(PTR_OP); }
"&&"			{ count(); return(AND_OP); }
"||"			{ count(); return(OR_OP); }
"<="			{ count(); return(LE_OP); }
">="			{ count(); return(GE_OP); }
"=="			{ count(); return(EQ_OP); }
"!="			{ count(); return(NE_OP); }
";"			{ count(); return(';'); }
("{"|"<%")		{ count(); return('{'); }
("}"|"%>")		{ count(); return('}'); }
","			{ count(); return(','); }
":"			{ count(); return(':'); }
"="			{ count(); return('='); }
"("			{ count(); return('('); }
")"			{ count(); return(')'); }
("["|"<:")		{ count(); return('['); }
("]"|":>")		{ count(); return(']'); }
"."			{ count(); return('.'); }
"&"			{ count(); return('&'); }
"!"			{ count(); return('!'); }
"~"			{ count(); return('~'); }
"-"			{ count(); return('-'); }
"+"			{ count(); return('+'); }
"*"			{ count(); return('*'); }
"/"			{ count(); return('/'); }
"%"			{ count(); return('%'); }
"<"			{ count(); return('<'); }
">"			{ count(); return('>'); }
"^"			{ count(); return('^'); }
"|"			{ count(); return('|'); }
"?"			{ count(); return('?'); }

[ \t\v\n\f]		{ count(); }
.			{ /* Add code to complain about unmatched characters */ }

%%

int yywrap(void)
{
	return 1;
}


void comment(void)
{
	char c, prev = 0;   /* 存放当前和前一个字符 */
  
	while ((c = input()) != 0)      /* (EOF maps to 0) */
	{
		if (c == '/' && prev == '*')     /* 读到了注释的右边界 */
			return;
		prev = c;
	}
	error("unterminated comment");
}


int column = 0;

void count(void) /*记录当前位于第几列*/
{
	int i;

	for (i = 0; yytext[i] != '\0'; i++)         /* '\0'表示结束符或空格符*/
		if (yytext[i] == '\n')
			column = 0;
		else if (yytext[i] == '\t')
			column += 8 - (column % 8);
		else
			column++;

	ECHO;
}


int check_type(void)
{
/*
* pseudo code --- this is what it should check
*
*	if (yytext == type_name)
*		return TYPE_NAME;
*
*	return IDENTIFIER;
*/

/*
*	it actually will only return IDENTIFIER
*/

	return IDENTIFIER;
}
