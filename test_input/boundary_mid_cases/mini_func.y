%token INT FOR IF ELSE RETURN IDENTIFIER NUMBER
%token EQ NE LE GE

%start program

%%
program
    : function_list
    ;

function_list
    : function
    | function_list function
    ;

function
    : INT IDENTIFIER '(' params_opt ')' compound_stmt
    ;

params_opt
    :
    | param_list
    ;

param_list
    : INT IDENTIFIER
    | param_list ',' INT IDENTIFIER
    ;

compound_stmt
    : '{' stmt_list_opt '}'
    ;

stmt_list_opt
    :
    | stmt_list
    ;

stmt_list
    : stmt
    | stmt_list stmt
    ;

stmt
    : declaration
    | assignment ';'
    | expr ';'
    | return_stmt
    | if_stmt
    | for_stmt
    | compound_stmt
    ;

declaration
    : INT IDENTIFIER ';'
    | INT IDENTIFIER '=' expr ';'
    ;

assignment
    : IDENTIFIER '=' expr
    ;

if_stmt
    : IF '(' expr ')' stmt
    | IF '(' expr ')' stmt ELSE stmt
    ;

for_stmt
    : FOR '(' assignment ';' expr ';' assignment ')' stmt
    ;

return_stmt
    : RETURN expr ';'
    ;

expr
    : equality
    ;

equality
    : relational
    | equality EQ relational
    | equality NE relational
    ;

relational
    : additive
    | relational '<' additive
    | relational '>' additive
    | relational LE additive
    | relational GE additive
    ;

additive
    : term
    | additive '+' term
    | additive '-' term
    ;

term
    : factor
    | term '*' factor
    | term '/' factor
    ;

factor
    : IDENTIFIER
    | NUMBER
    | '(' expr ')'
    | IDENTIFIER '(' args_opt ')'
    ;

args_opt
    :
    | arg_list
    ;

arg_list
    : expr
    | arg_list ',' expr
    ;
%%
