%token INT IF ELSE WHILE RETURN IDENTIFIER NUMBER
%token EQ NE LE GE AND OR

%start program

%%
program
    : function
    ;

function
    : INT IDENTIFIER '(' ')' compound_stmt
    ;

compound_stmt
    : '{' stmt_list '}'
    ;

stmt_list
    : stmt
    | stmt_list stmt
    ;

stmt
    : declaration
    | assignment ';'
    | if_stmt
    | while_stmt
    | return_stmt
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

while_stmt
    : WHILE '(' expr ')' stmt
    ;

return_stmt
    : RETURN expr ';'
    ;

expr
    : logical_or
    ;

logical_or
    : logical_and
    | logical_or OR logical_and
    ;

logical_and
    : equality
    | logical_and AND equality
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
    : multiplicative
    | additive '+' multiplicative
    | additive '-' multiplicative
    ;

multiplicative
    : unary
    | multiplicative '*' unary
    | multiplicative '/' unary
    ;

unary
    : primary
    | '-' unary
    ;

primary
    : IDENTIFIER
    | NUMBER
    | '(' expr ')'
    ;
%%
