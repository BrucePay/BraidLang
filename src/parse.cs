/////////////////////////////////////////////////////////////////////////////
//
// The Braid Programming Language - Parsing and Tokenizer
//
//
// Copyright (c) 2023 Bruce Payette (see LICENCE file) 
//
////////////////////////////////////////////////////////////////////////////

using System;
using System.Globalization;
using System.Linq;
using System.Numerics;
using System.Collections;
using System.Collections.Specialized;
using System.Text;
using System.Text.RegularExpressions;
using System.Collections.Generic;

namespace BraidLang
{

    ///////////////////////////////////////////////////////
    /// <summary>
    /// Types of tokens returned by the parse() function.
    /// </summary>
    public enum TokenType
    {
        Number = 0,
        String = 1,
        TypeLiteral = 3,
        MemberLiteral = 4,
        KeywordLiteral = 5,
        CharLiteral = 6,
        Comment = 7,
        RegexLiteral = 8,
        ArgIndexLiteral = 9,
        NamedParameterLiteral = 10,
        Symbol = 11,
        FuncCall = 12,
        Macro = 13,
        SpecialForms = 14,
        BuiltInFunction = 15,
        Paren = 16,
        SquareBracket = 17,
        Brace = 18,
    }

    ///////////////////////////////////////////////////////
    /// <summary>
    /// Token type returned by the parser.
    /// </summary>
    public sealed class Token : IComparable, ISourceContext
    {
        public TokenType Type { get; set; }
        public string TokenString { get; set; }
        public int LineNo { get; set; }
        public int Offset { get; set; }
        public int Length { get => TokenString.Length; }
        public string File { get; set; }
        public string Function { get; set; }
        public string Text { get; set; }

        public override string ToString() => TokenString;

        public int CompareTo(object objToCompare)
        {
            if (objToCompare is Token token)
            {
                if (this.Offset < token.Offset)
                {
                    return -1;
                }
                if (this.Offset > token.Offset)
                {
                    return 1;
                }
                return 0;
            }

            return -1;
        }
    }

    ///////////////////////////////////////////////////////
    /// <summary>
    /// The different types of quotes used in Braid.
    /// </summary>
    public enum QuoteType
    {
        None = 0,
        Quoted = 1,         // ' (single-quote) equivalent to (quote foo)
        QuasiQuote = 2,     // ` (backtick)
        Splat = 3,          // @
        UnquoteSplat = 4,   // ~@
        Unquote = 5,        // ~
        Dispatch = 6,       // # used for regexes #"[a-z]+" sets #{ 1 2 3 } function literals #(+ %0 %1)
    };

    //////////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// Partial class containing the parsing and tokenizing code for braid
    /// </summary>
    public static partial class Braid
    {

        /// <summary>
        /// Parses a string into s-Expressions, optionally returning all of the tokens.
        /// The tokens can be used for syntax colouring
        /// </summary>
        /// <param name="text">The string to parse.</param>
        /// <returns>The resulting s-Expression.</returns>
        public static s_Expr Parse(string text, List<Token> tokenList)
        {
            // Parser state variables
            Stack<s_Expr> listStack = new Stack<s_Expr>();
            s_Expr list = null;
            s_Expr listStart = null;
            StringBuilder token = new StringBuilder();
            StringBuilder strBldr = new StringBuilder();
            int inString = 0;
            bool tripleString = false;
            bool inComment = false;
            int commentStart = 0;
            Stack<QuoteType> quoteStack = new Stack<QuoteType>();
            QuoteType quoted = QuoteType.None;
            int lineno = 1;
            int inDict = 0;
            int inVector = 0;
            bool gotStringQuote = false;
            bool inTypeLiteral = false;
            int offset = 0;
            char c = '\0';
            object processedToken = null;
            var callStack = CallStack;
            Function fn;

            char nextchar()
            {
                if (offset + 1 >= text.Length)
                {
                    return '\0';
                }

                return text[offset + 1];
            }

            char nextchar2()
            {
                if (offset + 2 >= text.Length)
                {
                    return '\0';
                }

                return text[offset + 2];
            }

            char prevchar()
            {
                if (offset > 0)
                    return text[offset - 1];
                return '\0';
            }

            while (offset < text.Length)
            {
                c = text[offset];

                // Special character handling to make BraidLang JSON-compatible
                // Treat ',' as whitespace in vectors and dictionaries but not after '\'.
                if (c == ',' && (inVector > 0 || inDict > 0) && inString == 0 && !inTypeLiteral && prevchar() != '\\')
                {
                    c = ' ';
                }

                // Treat ':' as whitespace in dictionaries.
                // BUGBUGBUG - this is wrong and should only be done on the top level of a dictionary otherwise
                //             for things like { :a (fn a:b: -> [a b]) }, the trailing ':' will icorrectly be removed.
                else if (c == ':' && (inDict > 0) && inString == 0 && !inTypeLiteral && !char.IsLetterOrDigit(nextchar()))
                {
                    c = ' ';
                }

                if (inComment)
                {
                    if (c == '\r' || c == '\n')
                    {
                        inComment = false;
                        if (tokenList != null)
                        {
                            tokenList.Add(new Token
                            {
                                Type = TokenType.Comment,
                                LineNo = lineno,
                                Offset = commentStart,
                                File = _current_file,
                                Text = text,
                                Function = "",
                                TokenString = text.Substring(commentStart, offset - commentStart)
                            });
                        }
                    }
                    if (c == '\n')
                    {
                        lineno++;
                    }
                }
                else if (inString > 0)
                {
                    if (gotStringQuote)
                    {
                        // whatever the char is, just added it to the string.
                        // quotes will be processed later on.
                        strBldr.Append('\\');
                        strBldr.Append(c);
                        gotStringQuote = false;
                    }
                    else if (c == '"' && (! tripleString  || (nextchar() == '"' && nextchar2() == '"')))
                    {
                        if (tripleString)
                        {
                            offset += 2;
                            tripleString = false;
                        }

                        string str = strBldr.ToString();

                        object obj = null;
                        if (quoted == QuoteType.Dispatch)
                        {
                            if (tokenList != null)
                            {
                                tokenList.Add(new Token
                                {
                                    Type = TokenType.RegexLiteral,
                                    LineNo = lineno,
                                    Offset = offset - str.Length - 2,
                                    File = _current_file,
                                    Text = text,
                                    Function = "",
                                    TokenString = $"#\"{str}\""
                                });
                            }

                            try
                            {
                                str = ProcessStringEscapes(str, forregex: true);
                                obj = new Regex(str, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
                            }
                            catch (Exception e)
                            {
                                BraidRuntimeException($"Error occurred parsing regular expression literal '{str}': {e.Message}", e, new Token
                                {
                                    Type = TokenType.RegexLiteral,
                                    LineNo = lineno,
                                    Offset = offset - str.Length - 2,
                                    File = _current_file,
                                    Text = text,
                                    Function = "",
                                    TokenString = $"#\"{str}\""
                                });
                            }

                            quoted = QuoteType.None;
                        }
                        else
                        {
                            if (tokenList != null)
                            {
                                tokenList.Add(new Token
                                {
                                    Type = TokenType.String,
                                    LineNo = lineno,
                                    Offset = offset - str.Length - 1,
                                    File = _current_file,
                                    Text = text,
                                    Function = "",
                                    TokenString = '"' + str + '"'
                                });
                            }

                            // if the string is @"a\b\c" don't expand the quotes or variable references except for "
                            if (quoted != QuoteType.Splat)
                            {
                                str = ProcessStringEscapes(str, forregex: false);

                                if (str.Contains("${"))
                                {
                                    obj = new ExpandableStringLiteral(str);
                                }
                                else
                                {
                                    obj = str;
                                }
                            }
                            else
                            {
                                // Handle @" \"hi ${bob}\"." with out expanding ${}
                                StringBuilder sb = new StringBuilder(str.Length);
                                bool quote = false;
                                foreach (var ch in str)
                                {
                                    if (quote)
                                    {
                                        switch (ch)
                                        {
                                            case '\\': sb.Append('\\'); break;
                                            case '"': sb.Append('"'); break;
                                            default: sb.Append('\\'); sb.Append(ch); break;
                                        }
                                        quote = false;
                                    }
                                    else if (ch == '\\')
                                    {
                                        quote = true;
                                    }
                                    else
                                    {
                                        sb.Append(ch);
                                    }
                                }

                                if (quote)
                                {
                                    sb.Append('\\');
                                }

                                obj = sb.ToString();
                                quoted = QuoteType.None;
                            }
                        }

                        if (list == null)
                        {
                            listStart = list = new s_Expr(obj)
                            {
                                LineNo = lineno,
                                Offset = offset,
                                Text = text,
                                Function = _current_function,
                                File = _current_file
                            };
                        }
                        else
                        {
                            // add obj to the end of the list
                            var nl = new s_Expr(obj)
                            {
                                LineNo = lineno,
                                Offset = offset,
                                Text = text,
                                Function = _current_function,
                                File = _current_file
                            };
                            list.Cdr = nl;
                            list = nl;
                        }

                        inString = 0;
                        strBldr.Clear();
                    }
                    else if (c == '\\')
                    {
                        gotStringQuote = true;
                    }
                    else
                    {
                        if (c == '\n')
                        {
                            lineno++;
                        }

                        strBldr.Append(c);
                    }
                }
                else if (c == '\'')
                {
                    quoted = QuoteType.Quoted;
                }
                else if (c == '@')
                {
                    if (quoted == QuoteType.Unquote)
                    {
                        quoted = QuoteType.UnquoteSplat;
                    }
                    else
                    {
                        quoted = QuoteType.Splat;
                    }
                }
                else if (c == '#')
                {
                    quoted = QuoteType.Dispatch;
                }
                else if (c == '`')
                {
                    quoted = QuoteType.QuasiQuote;
                }
                else if (c == '~')
                {
                    quoted = QuoteType.Unquote;
                }
                // Handle multi-line comments (; comment text ;)
                else if (c == '(' && nextchar() == ';')
                {
                    int start = offset;
                    offset++;
                    bool closedComment = false;
                    // scan until you hit ';)' or the end of text.
                    while ((c = nextchar()) != '\0')
                    {
                        c = text[++offset];
                        if (c == ';' && nextchar() == ')')
                        {
                            offset += 2;
                            closedComment = true;
                            break;
                        }
                        else if (c == '\n')
                        {
                            lineno++;
                        }
                    }

                    if (!closedComment)
                    {
                        BraidRuntimeException($"End of file in block comment.");
                    }

                    if (tokenList != null)
                    {
                        string ttext = text.Substring(start, offset - start);
                        tokenList.Add(new Token {
                            Type = TokenType.Comment,
                            LineNo = lineno,
                            Offset = offset - 1,
                            File = _current_file,
                            Text = text,
                            Function = "",
                            TokenString = ttext
                        });
                    }
                }
                else if ('(' == c || '{' == c || ('[' == c && !inTypeLiteral))
                {
                    if ('{' == c)
                    {

                        if (tokenList != null)
                        {
                            tokenList.Add(new Token { Type = TokenType.Brace, LineNo = lineno, Offset = offset, File = _current_file, Text = text, Function = "", TokenString = "{" });
                        }

                        inDict++;
                    }
                    else if ('[' == c)
                    {
                        if (tokenList != null)
                        {
                            tokenList.Add(new Token { Type = TokenType.SquareBracket, LineNo = lineno, Offset = offset, File = _current_file, Text = text, Function = "", TokenString = "[" });
                        }

                        inVector++;
                    }
                    else
                    {
                        if (tokenList != null)
                        {
                            tokenList.Add(new Token { Type = TokenType.Paren, LineNo = lineno, Offset = offset, File = _current_file, Text = text, Function = "", TokenString = "(" });
                        }
                    }

                    // Open paren, brace or square bracket terminates a token.
                    if (token.Length > 0)
                    {
                        processedToken = ProcessToken(token.ToString(), lineno, text, offset, tokenList);
                        if (quoted != QuoteType.None)
                        {

                            Symbol symToUse;
                            switch (quoted)
                            {
                                case QuoteType.Splat:
                                    symToUse = Symbol.sym_splat;
                                    break;
                                case QuoteType.Unquote:
                                    symToUse = Symbol.sym_unquote;
                                    break;
                                case QuoteType.QuasiQuote:
                                    symToUse = Symbol.sym_quasiquote;
                                    break;
                                case QuoteType.Dispatch:
                                    symToUse = Symbol.sym_dispatch;
                                    break;
                                case QuoteType.UnquoteSplat:
                                    symToUse = Symbol.sym_unquotesplat;
                                    break;
                                // BUGBUGBUG FINISH THIS
                                default:
                                    symToUse = Symbol.sym_quote;
                                    break;
                            }

                            var nl = new s_Expr(symToUse, processedToken);
                            if (list == null)
                            {
                                listStart = list = new s_Expr(nl);
                            }
                            else
                            {
                                list = list.Add(nl);
                            }

                            list.LineNo = lineno;
                            list.Offset = offset;
                            list.Text = text;
                            list.Offset = offset;
                            list.File = _current_file;
                            list.Function = _current_function;
                        }
                        else
                        {
                            if (list == null)
                            {
                                listStart = list = new s_Expr(processedToken)
                                {
                                    LineNo = lineno,
                                    Offset = offset,
                                    Text = text,
                                    File = _current_file,
                                    Function = _current_function
                                };
                            }
                            else
                            {
                                s_Expr nl = new s_Expr(processedToken)
                                {
                                    LineNo = lineno,
                                    Offset = offset,
                                    Text = text,
                                    File = _current_file,
                                    Function = _current_function
                                };
                                list.Cdr = nl;
                                list = nl;
                            }
                        }

                        quoted = QuoteType.None;
                        token.Clear();
                    }

                    listStack.Push(listStart);
                    quoteStack.Push(quoted);
                    quoted = QuoteType.None;
                    listStart = list = null;
                }
                else if (c == ')' || c == '}' || (c == ']' && !inTypeLiteral))
                {
                    if (listStack.Count == 0)
                    {
                        throw new BraidCompilerException(text, offset, Braid._current_file, lineno,
                            $"There are too many close parens '{c}' in this expression.");
                    }

                    inTypeLiteral = false;

                    if (token.Length > 0)
                    {
                        processedToken = ProcessToken(token.ToString(), lineno, text, offset, tokenList);
                        if (quoted != QuoteType.None)
                        {
                            Symbol symToUse;
                            switch (quoted)
                            {
                                case QuoteType.Splat:
                                    symToUse = Symbol.sym_splat;
                                    break;
                                case QuoteType.Unquote:
                                    symToUse = Symbol.sym_unquote;
                                    break;
                                case QuoteType.QuasiQuote:
                                    symToUse = Symbol.sym_quasiquote;
                                    break;
                                case QuoteType.Dispatch:
                                    symToUse = Symbol.sym_dispatch;
                                    break;
                                case QuoteType.UnquoteSplat:
                                    symToUse = Symbol.sym_unquotesplat;
                                    break;
                                // BUGBUGBUG FINISH THIS
                                default:
                                    symToUse = Symbol.sym_quote;
                                    break;
                            }

                            var nl = new s_Expr(symToUse, processedToken)
                            {
                                LineNo = lineno,
                                Offset = offset,
                                Text = text,
                                File = _current_file,
                                Function = _current_function
                            };


                            if (list == null)
                            {
                                listStart = list = new s_Expr(nl);
                            }
                            else
                            {
                                list = list.Add(nl);
                            }

                            list.LineNo = lineno;
                            list.Offset = offset;
                            list.Text = text;
                            list.File = _current_file;
                            list.Function = _current_function;
                        }
                        else
                        {
                            if (list == null)
                            {
                                listStart = list = new s_Expr(processedToken);
                            }
                            else
                            {
                                var nl = new s_Expr(processedToken);
                                list.Cdr = nl;
                                list = nl;
                            }

                            list.LineNo = lineno;
                            list.Offset = offset;
                            list.Text = text;
                            list.File = _current_file;
                            list.Function = _current_function;
                        }

                        quoted = QuoteType.None;
                        token.Clear();
                    }

                    object current = listStart;

                    if (c == ')')
                    {
                        if (tokenList != null)
                        {
                            tokenList.Add(new Token { Type = TokenType.Paren, LineNo = lineno, Offset = offset, File = _current_file, Text = text, Function = "", TokenString = ")" });
                        }
                    }

                    if (c == '}')
                    {
                        if (tokenList != null)
                        {
                            tokenList.Add(new Token { Type = TokenType.Brace, LineNo = lineno, Offset = offset, File = _current_file, Text = text, Function = "", TokenString = "}" });
                        }

                        if (inDict == 0)
                        {
                            throw new IncompleteParseException(
                                BraidCompilerException.Annotate(text, offset, Braid._current_file, lineno,
                                    $"Unmatched close brace '}}' in dictionary literal at line {lineno}."));
                        }

                        inDict--;

                        if (quoteStack.Peek() == QuoteType.Dispatch)
                        {
                            current = new HashSetLiteral((s_Expr)current, lineno);
                        }
                        else
                        {
                            // generate a dictionary literal
                            current = new DictionaryLiteral((IEnumerable)current, _current_file, lineno, text, offset);
                        }
                    }
                    else if (c == ']')
                    {
                        if (tokenList != null)
                        {
                            tokenList.Add(new Token { Type = TokenType.SquareBracket, LineNo = lineno, Offset = offset, File = _current_file, Text = text, Function = "", TokenString = "]" });
                        }

                        if (inVector == 0)
                        {
                            throw new IncompleteParseException(
                                BraidCompilerException.Annotate(text, offset, Braid._current_file, lineno,
                                    $"Unmatched close square bracket ']' in vector literal at line {lineno}."));
                        }

                        inVector--;

                        current = new VectorLiteral((s_Expr)current, lineno);
                    }
                    else if (tokenList == null && listStart != null && listStart.Car != null &&
                             listStart.Car is Symbol defMacro && defMacro == Symbol.sym_defmacro)
                    {
                        // If the list starts with "defmacro"; evaluate it because macros are bound at compile time.
                        // Don't do this if we're tokenizing.
                        Eval(listStart, true, true);
                        current = null;
                    }
                    else if (tokenList == null && listStart != null && listStart.Car != null && listStart.Car is Symbol fnname)
                    {
                        // Macros are also applied at compile time.
                        // Don't do this if we're tokenizing.
                        var macroVar = CallStack.GetVariable(fnname);
                        if (macroVar != null && macroVar.Value is Callable callable && callable.FType == FunctionType.Macro)
                        {
                            try
                            {
                                if (Braid.Debugger != 0)
                                {
                                    if ((Braid.Debugger & DebugFlags.Trace) != 0)
                                    {
                                        string argstr = string.Join(" ", ((s_Expr)listStart.Cdr).GetEnumerable().Select(x => x?.ToString()));
                                        Console.WriteLine($"BEGIN MACRO APPLICATION: ({fnname} {argstr})");
                                    }
                                }

                                var oldCaller = callStack.Caller;
                                callStack.Caller = (s_Expr)listStart;
                                try
                                {
                                    current = callable.Invoke(new Vector((s_Expr)listStart.Cdr));
                                }
                                finally
                                {
                                    callStack.Caller = oldCaller;
                                }

                                if (Braid.Debugger != 0)
                                {
                                    if ((Braid.Debugger & DebugFlags.Trace) != 0)
                                    {
                                        Console.WriteLine($"END MACRO APPLICATION {fnname} --> {Braid.Truncate(current)}");
                                    }
                                }
                            }
                            catch (BraidBaseException)
                            {
                                throw;
                            }
                            catch (Exception psbe)
                            {
                                throw new BraidCompilerException(text, offset, Braid._current_file, lineno,
                                    $"Error processing macro '{fnname}'\n{psbe.Message}", psbe);
                            }
                        }
                        else if (fnname == Symbol.sym_lambda)
                        {
                            // If it's a lambda i.e. (lambda [x y] (+ x y)), compile it and turn it into a FunctionLiteral
                            var lambda = BuildUserFunction(new Vector((s_Expr)listStart.Cdr));
                            lambda.LineNo = listStart.LineNo;
                            lambda.File = Braid._current_file;
                            lambda.Text = listStart.Text;
                            lambda.Offset = listStart.Offset;
                            lambda.Function = _current_function;
                            current = new FunctionLiteral(lambda);
                        }
                        else if (fnname == Symbol.sym_let && !(((s_Expr)listStart.Cdr).Car is VectorLiteral))
                        {
                            // BUGBUGBUG - need to rethink doing this, maybe replace 'let [a 1 b 2] ...' with 'with [a 1 b 2] ...'
                            // Handle the syntax: (let [-success] [^type] <symbol> <expr>)
                            // In this scenario, 'let' gets turned into 'local'
                            s_Expr next = (s_Expr)listStart.Cdr;

                            if (next.Car == null)
                            {
                                CallStack.Caller = next;
                                BraidRuntimeException("The symbol passed to 'let' cannot be null.");
                            }

                            Symbol varSym;
                            // Let 'let' be type-qualified.
                            TypeLiteral tlit = next.Car as TypeLiteral;
                            if (tlit == null)
                            {
                                varSym = next.Car as Symbol;
                                if (varSym == null)
                                {
                                    varSym = Symbol.FromString(next.Car.ToString());
                                }
                            }
                            else
                            {
                                next = (s_Expr)next.Cdr;
                                varSym = next.Car as Symbol;
                                if (varSym == null)
                                {
                                    varSym = Symbol.FromString(next.Car.ToString());
                                }
                            }

                            next = (s_Expr)next.Cdr;
                            if (next == null)
                            {
                                throw new BraidCompilerException(text, offset, Braid._current_file, lineno,
                                    $"Incomplete 'let' call, this function's syntax is '(let [^type] symbol value)' not : '{listStart}'");
                            }

                            object expr = next.Car;

                            var func = callStack.GetValue(Symbol.sym_local);
                            ((s_Expr)current).Car = func;
                        }
                        // BUGBUGBUG - resolve symbols into functions. We can only resolve the built-ins at
                        // this point since everything else is subject to rebinding. But we really shouldn't be doing it here.
                        // it should be done as part of "compiling" the functions and this code should be removed.
                        // For now however, it needs to be here to make curried functions work in patterns.
                        else
                        {
                            var variable = callStack.GetVariable(fnname);
                            if (variable != null)
                            {
                                object varVal = variable.Value;
                                if (varVal is Function && !(varVal is UserFunction || varVal is PatternFunction))
                                {
                                    listStart.Car = varVal;
                                }
                            }
                        }
                    }
                    else if (listStart != null && listStart.Count == 3 && listStart.Cdr is s_Expr lscdr
                        && lscdr.Car is Symbol lscdrsym && lscdrsym.Value == ".")
                    {
                        // Handle dotted pairs turns a list of 3 items (1 . 2) into a dotted pair.
                        current = new s_Expr(listStart.Car, ((s_Expr)lscdr.Cdr).Car);
                    }

                    // Handle pipeline transformations after macro evaluation, but not for any of the 
                    // function definition forms (see below) so that we can do write pattern functions like: 
                    //  (defn foo | x:xs -> "Hi")
                    var elements = current as s_Expr;
                    Function sf = null;
                    if (elements != null)
                    {
                        sf = elements.Car as Function;
                    }

                    if (elements != null && (sf == null || sf.FType != FunctionType.SpecialForm ||
                            (sf.NameSymbol != Symbol.sym_defn && sf.NameSymbol != Symbol.sym_matchp && sf.NameSymbol != Symbol.sym_lambda &&
                             sf.NameSymbol != Symbol.sym_defspecial && sf.NameSymbol != Symbol.sym_defmacro && sf.NameSymbol != Symbol.sym_deftype))
                    )
                    {
                        fn = new Function("pipe", pipe_function);
                        fn.FType = FunctionType.SpecialForm;
                        var result = new s_Expr(fn)
                        {
                            File = Braid._current_file,
                            LineNo = lineno,
                            Text = text,
                            Offset = offset,
                            Function = _current_function
                        };


                        bool hadPipe = false;
                        s_Expr segStart = null;
                        s_Expr last = null;
                        bool first = true;
                        foreach (var element in elements.GetEnumerable())
                        {
                            if (element != null && element is Symbol sym && sym == Symbol.sym_pipe)
                            {
                                //BUGBUGBUG need an exception for an empty first element
                                if (first && segStart != null && segStart.Count == 1)
                                {
                                    result.Add(segStart.Car);
                                }
                                else
                                {
                                    result.Add(segStart);
                                }

                                result.Function = _current_function;
                                result.File = _current_file;
                                result.Text = text;
                                result.Offset = offset;
                                result.LineNo = lineno;

                                first = false;
                                hadPipe = true;
                                segStart = null;
                            }
                            else
                            {
                                if (segStart == null)
                                {
                                    last = segStart = new s_Expr(element);
                                }
                                else
                                {
                                    last = last.Add(element);
                                }

                                last.LineNo = lineno;
                                last.Function = _current_function;
                                last.Text = text;
                                last.Offset = offset;
                                last.LineNo = lineno;
                                last.File = _current_file;
                            }
                        }

                        if (segStart != null)
                        {
                            // Add the trailing segment
                            result.Add(segStart);
                        }

                        // True if the sexpr contained the pipe (|) symbol
                        // indicating that it's actually a series of commands (a pipeline).
                        if (hadPipe)
                        {
                            current = result;
                        }
                    }

                    quoted = quoteStack.Pop();
                    if (quoted == QuoteType.Quoted)
                    {
                        current = new s_Expr(Symbol.sym_quote, current);
                        s_Expr cse = (s_Expr)current;
                        cse.LineNo = lineno;
                        cse.Offset = offset;
                        cse.Text = text;
                        cse.File = _current_file;
                        cse.Function = _current_function;
                        quoted = QuoteType.None;
                    }
                    else if (quoted == QuoteType.Splat)
                    {
                        // @(1 2 3) becomes @((1 2 3))
                        current = new s_Expr(Symbol.sym_splat, new s_Expr(current));
                        s_Expr cse = (s_Expr)current;
                        cse.LineNo = lineno;
                        cse.Offset = offset;
                        cse.Text = text;
                        cse.File = _current_file;
                        cse.Function = _current_function;
                        quoted = QuoteType.None;
                    }
                    else if (quoted == QuoteType.QuasiQuote)
                    {
                        current = new s_Expr(Symbol.sym_quasiquote, current);
                        s_Expr cse = (s_Expr)current;
                        cse.LineNo = lineno;
                        cse.Offset = offset;
                        cse.Text = text;
                        cse.File = _current_file;
                        cse.Function = _current_function;
                        quoted = QuoteType.None;
                    }
                    else if (quoted == QuoteType.Unquote)
                    {
                        current = new s_Expr(Symbol.sym_unquote, current);
                        s_Expr cse = (s_Expr)current;
                        cse.LineNo = lineno;
                        cse.Offset = offset;
                        cse.Text = text;
                        cse.File = _current_file;
                        cse.Function = _current_function;
                        quoted = QuoteType.None;
                    }
                    else if (quoted == QuoteType.UnquoteSplat)
                    {
                        current = new s_Expr(Symbol.sym_unquotesplat, current);
                        s_Expr cse = (s_Expr)current;
                        cse.LineNo = lineno;
                        cse.Offset = offset;
                        cse.Text = text;
                        cse.File = _current_file;
                        cse.Function = _current_function;
                        quoted = QuoteType.None;
                    }
                    else if (quoted == QuoteType.Dispatch)
                    {
                        // If it's not a BraidLiteral (hashtable, hashset or expandable string) then treat it as a
                        // function literal.
                        if (current != null && !(current is BraidLiteral))
                        {
                            // Handle function literal expansion #(+ %0 %1) becomes (lambda [%0 %1 &args] (+ %0 %1))
                            s_Expr currentSexpr = (s_Expr)current;
                            s_Expr foundArgIndexes =
                                ((s_Expr)(currentSexpr.Visit(new Callable("<visitor>", element => element[0] is ArgIndexLiteral), false)));

                            Vector argIndexes = new Vector();

                            if (foundArgIndexes != null)
                            {
                                argIndexes.AddRange(
                                    foundArgIndexes
                                    .OrderBy(arg => arg)
                                    .Distinct()
                                    .Select(arg => arg.ToString())
                                    .Select(arg => Symbol.FromString(arg))
                                    .Reverse()
                                );
                            }

                            // Make function literals vararg by default.
                            argIndexes.Add(Symbol.sym_and_args);

                            var lambda = new UserFunction(FunctionType.Function, "lambda", argIndexes, null, new s_Expr(currentSexpr), null);
                            lambda.Text = text;
                            lambda.Offset = offset;
                            lambda.LineNo = lineno;
                            lambda.File = _current_file;
                            // BUGBUGBUG - should we extract helpinfo here?
                            current = new FunctionLiteral(lambda);
                        }

                        quoted = QuoteType.None;
                    }

                    listStart = listStack.Pop();
                    if (listStart == null)
                    {
                        listStart = list = new s_Expr(current);
                        list.LineNo = lineno;
                        list.Offset = offset;
                        list.Text = text;
                        list.File = _current_file;
                        list.Function = _current_function;
                    }
                    else
                    {
                        list = listStart.LastNode();
                        list = list.Add(current);
                        list.LineNo = lineno;
                        list.Offset = offset;
                        list.Text = text;
                        list.File = _current_file;
                        list.Function = _current_function;
                    }
                }
                else if (c == '"')
                {
                    inString = lineno;
                    // Handle triple-quoted strings
                    if (nextchar() == '"' && nextchar2() == '"')
                    {
                        tripleString = true;
                        offset += 2;
                    }
                }
                else if (';' == c)
                {
                    inComment = true;
                    commentStart = offset;
                }
                else if ('^' == c)
                {
                    inTypeLiteral = true;
                    token.Append(c);
                }
                else if (char.IsWhiteSpace(c))
                {
                    if (c == '\n')
                    {
                        lineno++;
                    }

                    inTypeLiteral = false;
                    if (token.Length > 0)
                    {
                        processedToken = ProcessToken(token.ToString(), lineno, text, offset, tokenList);
                        if (quoted != QuoteType.None)
                        {
                            s_Expr nl = null;
                            switch (quoted)
                            {
                                case QuoteType.Quoted:
                                    nl = new s_Expr(Symbol.sym_quote, processedToken);
                                    break;

                                case QuoteType.Splat:
                                    nl = new s_Expr(Symbol.sym_splat, processedToken);
                                    break;

                                case QuoteType.QuasiQuote:
                                    nl = new s_Expr(Symbol.sym_quasiquote, processedToken);
                                    break;

                                case QuoteType.Unquote:
                                    nl = new s_Expr(Symbol.sym_unquote, processedToken);
                                    break;

                                case QuoteType.UnquoteSplat:
                                    nl = new s_Expr(Symbol.sym_unquotesplat, processedToken);
                                    break;
                            }

                            if (list == null)
                            {
                                listStart = list = new s_Expr(nl);
                            }
                            else
                            {
                                list = list.Add(nl);
                            }

                            list.LineNo = lineno;
                            list.Offset = offset;
                            list.Text = text;
                            list.File = _current_file;
                            list.Function = _current_function;

                            quoted = QuoteType.None;
                        }
                        else
                        {
                            if (list == null)
                            {
                                listStart = list = new s_Expr(processedToken);
                                list.LineNo = lineno;
                                list.Offset = offset;
                                list.Text = text;
                                list.File = _current_file;
                                list.Function = _current_function;
                            }
                            else
                            {
                                list = list.Add(processedToken);
                                list.LineNo = lineno;
                                list.Offset = offset;
                                list.Text = text;
                                list.File = _current_file;
                                list.Function = _current_function;
                            }
                        }

                        token.Clear();
                    }
                }
                else
                {
                    token.Append(c);
                }
                offset++;
            }

            if (inString > 0)
            {
                if (tripleString)
                {
                    throw new IncompleteParseException(BraidCompilerException.Annotate(text, offset, Braid._current_file, lineno,
                        $"Unterminated triple-quoted string constant starting on line {inString}"));
                }
                else
                {
                    throw new IncompleteParseException(BraidCompilerException.Annotate(text, offset, Braid._current_file, lineno,
                        $"Unterminated string constant starting on line {inString}"));
                }
            }

            // Handle dangling tokens...
            if (token.Length > 0)
            {
                processedToken = ProcessToken(token.ToString(), lineno, text, offset, tokenList);

                if (quoted != QuoteType.None)
                {
                    var nl = new s_Expr(Symbol.sym_quote, processedToken);
                    if (list == null)
                    {
                        listStart = list = new s_Expr(nl);
                        list.LineNo = lineno;
                        list.File = _current_file;
                    }
                    else
                    {
                        list.Add(nl);
                        list.LineNo = lineno;
                        list.File = _current_file;
                        list.Function = _current_function;
                    }
                }
                else
                {
                    if (list == null)
                    {
                        listStart = list = new s_Expr(processedToken);
                        list.LineNo = lineno;
                        list.File = _current_file;
                        list.Function = _current_function;
                    }
                    else
                    {
                        list.Add(processedToken);
                        list.LineNo = lineno;
                        list.File = _current_file;
                        list.Function = _current_function;
                    }
                }
            }

            if (inVector > 0)
            {
                throw new IncompleteParseException(
                    BraidCompilerException.Annotate(text, offset, Braid._current_file, lineno,
                        $"Missing close square bracket ']': ({inVector}) more square brackets " +
                        "are required to complete the vector " +
                        $"literal."));
            }

            if (inDict > 0)
            {
                throw new IncompleteParseException(
                    BraidCompilerException.Annotate(text, offset, Braid._current_file, lineno,
                        $"Missing close brace '}}': ({inDict}) more braces " +
                        $"are required to complete the dictionary literal."));
            }

            if (listStack.Count > 0)
            {

                // BUGBUGBUG this is still not right. Need to keep the open paren around
                var start = listStart != null ? listStart.LineNo : lineno;
                var startOffset = listStart != null ? listStart.Offset : offset;
                throw new IncompleteParseException(
                    BraidCompilerException.Annotate(text, startOffset, Braid._current_file, start,
                        $"Missing close paren ')' for list beginning before line {start}. " +
                        (listStack.Count == 1 ?
                            "1 more paren is " :
                            $"{listStack.Count} more parens are ") +
                        $"required to complete the list."));
            }

            return listStart;
        }

        /// <summary>
        /// Parse overload required for reflection invocation.
        /// </summary>
        /// <param name="text">The text to parse</param>
        /// <returns></returns>
        public static s_Expr Parse(string text)
        {
            return Parse(text, null);
        }
        private static string ProcessStringEscapes(string str, bool forregex)
        {
            StringBuilder sb = new StringBuilder(str.Length);
            bool quote = false;
            foreach (var ch in str)
            {
                if (quote)
                {
                    if (forregex)
                    {
                        switch (ch)
                        {
                            case '\\': sb.Append('\\'); break;
                            case '"': sb.Append('"'); break;
                            default: sb.Append("\\" + ch); break;
                        }
                    }
                    else
                    {
                        switch (ch)
                        {
                            case 'a': sb.Append('\a'); break;
                            case 'b': sb.Append('\b'); break;
                            case 'f': sb.Append('\f'); break;
                            case 'n': sb.Append('\n'); break;
                            case 'r': sb.Append('\r'); break;
                            case 't': sb.Append('\t'); break;
                            case 'v': sb.Append('\v'); break;
                            case 'e': sb.Append((char)0x1b); break; // Escape
                            case '\\': sb.Append('\\'); break;
                            case '"': sb.Append('"'); break;
                            default: sb.Append("\\" + ch); break;
                        }
                    }
                    quote = false;
                }
                else if (ch == '\\')
                {
                    quote = true;
                }
                else
                {
                    sb.Append(ch);
                }
            }

            if (quote)
            {
                sb.Append('\\');
            }

            str = sb.ToString();
            return str;
        }

        static Regex number_regex = new Regex(@"^(-?[0-9][0-9_]*(\.[0-9_]+)?(e[+-]?[_0-9]+)?|[0-9][0-9_]*i?|0x[0-9a-f_]+)$|0b[10_]+$",
            RegexOptions.IgnoreCase | RegexOptions.Compiled | RegexOptions.CultureInvariant);

        //BUGBUGBUG The regex is wrong - it should be much more strict w.r.t. type name syntax.
        static Regex typeliteral_regex = new Regex(@"^\^[_a-z][0-9a-z_,.\[\]+`]*\??$",
            RegexOptions.IgnoreCase | RegexOptions.Compiled | RegexOptions.CultureInvariant);

        static Regex memberliteral_regex = new Regex(@"^\.\??[a-z_][.0-9a-z_/,\[\]]*$",
            RegexOptions.IgnoreCase | RegexOptions.Compiled | RegexOptions.CultureInvariant);

        static Regex charLiteral_regex = new Regex(@"^\\\S+",
            RegexOptions.Compiled | RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

        //
        // Handle processing for individual token types.
        // 
        static object ProcessToken(string tokenStr, int lineno, string text, int offset, List<Token> tokenList)
        {
            // Calculate the start of the token
            offset -= tokenStr.Length;
            char firstc = tokenStr[0];

            // Numbers
            if ((char.IsDigit(firstc) || firstc == '-') && number_regex.IsMatch(tokenStr))
            {
                // Keep the original token string for use in creating token objects.
                string origTokenStr = tokenStr;
                tokenStr = tokenStr.Replace("_", string.Empty);

                if (tokenStr[tokenStr.Length - 1] == 'i')
                {
                    tokenStr = tokenStr.Substring(0, tokenStr.Length - 1);
                    BigInteger bi = BigInteger.Parse(tokenStr);
                    if (tokenList != null)
                    {
                        tokenList.Add(new Token { Type = TokenType.Number, LineNo = lineno, Offset = offset, File = _current_file, Text = text, Function = "", TokenString = origTokenStr });
                    }
                    return bi;
                }
                else if (tokenStr.Contains('.') || (!tokenStr.StartsWith("0x") && tokenStr.Contains('e')))
                {
                    if (tokenList != null)
                    {
                        tokenList.Add(new Token { Type = TokenType.Number, LineNo = lineno, Offset = offset, File = _current_file, Text = text, Function = "", TokenString = origTokenStr });
                    }
                    return double.Parse(tokenStr);
                }
                else
                {
                    int result = 0;
                    if (tokenStr.StartsWith("0x"))
                    {
                        if (int.TryParse(tokenStr.Substring(2), System.Globalization.NumberStyles.HexNumber,
                            CultureInfo.InvariantCulture, out result))
                        {
                            if (tokenList != null)
                            {
                                tokenList.Add(new Token { Type = TokenType.Number, LineNo = lineno, Offset = offset, File = _current_file, Text = text, Function = "", TokenString = origTokenStr });
                            }

                            return BoxInt(result);
                        }
                    }
                    else if (tokenStr.StartsWith("0b"))
                    {
                        if (tokenList != null)
                        {
                            tokenList.Add(new Token { Type = TokenType.Number, LineNo = lineno, Offset = offset, File = _current_file, Text = text, Function = "", TokenString = origTokenStr });
                        }

                        long result64 = Convert.ToInt64(tokenStr.Substring(2), 2);

                        return result64;
                    }
                    else
                    {
                        if (int.TryParse(tokenStr, out result))
                        {
                            if (tokenList != null)
                            {
                                tokenList.Add(new Token { Type = TokenType.Number, LineNo = lineno, Offset = offset, File = _current_file, Text = text, Function = "", TokenString = origTokenStr });
                            }

                            return BoxInt(result);
                        }
                    }

                    // Try long instead.
                    long lresult = 0;
                    if (tokenStr.StartsWith("0x"))
                    {
                        if (long.TryParse(tokenStr.Substring(2), System.Globalization.NumberStyles.HexNumber,
                            CultureInfo.InvariantCulture, out lresult))
                        {
                            if (tokenList != null)
                            {
                                tokenList.Add(new Token { Type = TokenType.Number, LineNo = lineno, Offset = offset, File = _current_file, Text = text, Function = "", TokenString = origTokenStr });
                            }
                            return lresult;
                        }
                    }
                    else
                    {
                        if (long.TryParse(tokenStr, out lresult))
                        {
                            if (tokenList != null)
                            {
                                tokenList.Add(new Token { Type = TokenType.Number, LineNo = lineno, Offset = offset, File = _current_file, Text = text, Function = "", TokenString = origTokenStr });
                            }
                            return lresult;
                        }
                    }

                    // Finally try BigInteger.
                    BigInteger bresult = 0;
                    if (tokenStr.StartsWith("0x", StringComparison.OrdinalIgnoreCase))
                    {
                        bresult = BigInteger.Parse(tokenStr.Substring(2), System.Globalization.NumberStyles.HexNumber);
                    }
                    else
                    {
                        bresult = BigInteger.Parse(tokenStr);
                    }

                    if (tokenList != null)
                    {
                        tokenList.Add(new Token { Type = TokenType.Number, LineNo = lineno, Offset = offset, File = _current_file, Text = text, Function = "", TokenString = origTokenStr });
                    }

                    return bresult;
                }
            }
            else if (firstc == '\\' && charLiteral_regex.IsMatch(tokenStr))
            {
                if (tokenStr.Length == 2)
                {
                    if (tokenList != null)
                    {
                        tokenList.Add(new Token { Type = TokenType.CharLiteral, LineNo = lineno, Offset = offset, File = _current_file, Text = text, Function = "", TokenString = tokenStr });
                    }
                    // Single char
                    return tokenStr[1];
                }
                else if (string.Equals(tokenStr, @"\space", StringComparison.OrdinalIgnoreCase))
                {
                    if (tokenList != null)
                    {
                        tokenList.Add(new Token { Type = TokenType.CharLiteral, LineNo = lineno, Offset = offset, File = _current_file, Text = text, Function = "", TokenString = tokenStr });
                    }
                    return ' ';
                }
                else if (string.Equals(tokenStr, @"\newline", StringComparison.OrdinalIgnoreCase))
                {
                    if (tokenList != null)
                    {
                        tokenList.Add(new Token { Type = TokenType.CharLiteral, LineNo = lineno, Offset = offset, File = _current_file, Text = text, Function = "", TokenString = tokenStr });
                    }
                    return '\n';
                }
                else if (string.Equals(tokenStr, @"\return", StringComparison.OrdinalIgnoreCase))
                {
                    if (tokenList != null)
                    {
                        tokenList.Add(new Token { Type = TokenType.CharLiteral, LineNo = lineno, Offset = offset, File = _current_file, Text = text, Function = "", TokenString = tokenStr });
                    }
                    return '\r';
                }
                else if (string.Equals(tokenStr, @"\esc", StringComparison.OrdinalIgnoreCase))
                {
                    if (tokenList != null)
                    {
                        tokenList.Add(new Token { Type = TokenType.CharLiteral, LineNo = lineno, Offset = offset, File = _current_file, Text = text, Function = "", TokenString = tokenStr });
                    }
                    return (char)0x1b;
                }
                else if (string.Equals(tokenStr, @"\tab", StringComparison.OrdinalIgnoreCase))
                {
                    if (tokenList != null)
                    {
                        tokenList.Add(new Token { Type = TokenType.CharLiteral, LineNo = lineno, Offset = offset, File = _current_file, Text = text, Function = "", TokenString = tokenStr });
                    }
                    return '\t';
                }
                else if (tokenStr[1] == 'u' || tokenStr[1] == 'U')
                {
                    if (tokenList != null)
                    {
                        tokenList.Add(new Token { Type = TokenType.CharLiteral, LineNo = lineno, Offset = offset, File = _current_file, Text = text, Function = "", TokenString = tokenStr });
                    }
                    if (int.TryParse(tokenStr.Substring(2), System.Globalization.NumberStyles.Number,
                        CultureInfo.InvariantCulture, out int result))
                    {
                        return (char)result;
                    }
                }
                else if (tokenStr[1] == 'x' || tokenStr[1] == 'X')
                {
                    if (tokenList != null)
                    {
                        tokenList.Add(new Token { Type = TokenType.CharLiteral, LineNo = lineno, Offset = offset, File = _current_file, Text = text, Function = "", TokenString = tokenStr });
                    }
                    if (int.TryParse(tokenStr.Substring(2), System.Globalization.NumberStyles.HexNumber,
                        CultureInfo.InvariantCulture, out int result))
                    {
                        return (char)result;
                    }
                }

                // everything else is an error
                throw new BraidCompilerException(text, offset, Braid._current_file, lineno,
                    $"invalid character literal '{tokenStr}'");
            }
            else if (firstc == '^' && typeliteral_regex.IsMatch(tokenStr))
            {
                if (tokenList != null)
                {
                    tokenList.Add(new Token { Type = TokenType.TypeLiteral, LineNo = lineno, Offset = offset, File = _current_file, Text = text, Function = "", TokenString = tokenStr });
                }
                return new TypeLiteral(tokenStr.Substring(1), lineno, _current_file);
            }
            else if (firstc == '%' && tokenStr.Length == 2 && Char.IsDigit(tokenStr[1]))
            {
                if (tokenList != null)
                {
                    tokenList.Add(new Token { Type = TokenType.ArgIndexLiteral, LineNo = lineno, Offset = offset, File = _current_file, Text = text, Function = "", TokenString = tokenStr });
                }

                return new ArgIndexLiteral((int)(tokenStr[1] - '0'), lineno, _current_file);
            }
            else if (firstc == '.' && memberliteral_regex.IsMatch(tokenStr))
            {
                if (tokenList != null)
                {
                    tokenList.Add(new Token { Type = TokenType.MemberLiteral, LineNo = lineno, Offset = offset, File = _current_file, Text = text, Function = "", TokenString = tokenStr });
                }

                return new MemberLiteral(tokenStr, lineno, _current_file);
            }
            else if (firstc == ':' && tokenStr.Length > 1)
            {
                if (tokenList != null)
                {
                    tokenList.Add(new Token { Type = TokenType.KeywordLiteral, LineNo = lineno, Offset = offset, File = _current_file, Text = text, Function = "", TokenString = tokenStr });
                }

                return KeywordLiteral.FromString(tokenStr);
            }
            else if (firstc == '-' && tokenStr.Length > 1 && ((tokenStr[1] == '-' && tokenStr.Length > 2) || Char.IsLetter(tokenStr[1])))
            {
                bool takesArgument = tokenStr[tokenStr.Length - 1] == ':';
                int skip = tokenStr[1] == '-' ? 2 : 1;
                string name = takesArgument ? tokenStr.Substring(skip, tokenStr.Length - 1 - skip) : tokenStr.Substring(skip);
                if (tokenList != null)
                {
                    tokenList.Add(new Token { Type = TokenType.NamedParameterLiteral, LineNo = lineno, Offset = offset, File = _current_file, Text = text, Function = "", TokenString = tokenStr });
                }

                return new NamedParameter(name, null, takesArgument, tokenStr[1] == '-');
            }
            else if (tokenStr.Equals("true", StringComparison.OrdinalIgnoreCase))
            {
                if (tokenList != null)
                {
                    tokenList.Add(new Token { Type = TokenType.Symbol, LineNo = lineno, Offset = offset, File = _current_file, Text = text, Function = "", TokenString = "true" });
                }

                return Braid.BoxedTrue;
            }
            else if (tokenStr.Equals("false", StringComparison.OrdinalIgnoreCase))
            {
                if (tokenList != null)
                {
                    tokenList.Add(new Token { Type = TokenType.Symbol, LineNo = lineno, Offset = offset, File = _current_file, Text = text, Function = "", TokenString = "false" });
                }

                return Braid.BoxedFalse;
            }
            else
            {
                Symbol tokenSym = Symbol.FromString(tokenStr);

                if (tokenList != null)
                {
                    var binding = CallStack.GetVariable(tokenSym);
                    if (binding != null && binding.Value is Callable callable)
                    {
                        switch (callable.FType)
                        {
                            case FunctionType.Macro:
                                tokenList.Add(
                                    new Token
                                    {
                                        Type = TokenType.Macro,
                                        LineNo = lineno,
                                        Offset = offset,
                                        File = _current_file,
                                        Text = text,
                                        Function = "",
                                        TokenString = tokenStr,
                                    }
                                );
                                break;

                            case FunctionType.SpecialForm:
                                tokenList.Add(
                                    new Token
                                    {
                                        Type = TokenType.SpecialForms,
                                        LineNo = lineno,
                                        Offset = offset,
                                        File = _current_file,
                                        Text = text,
                                        Function = "",
                                        TokenString = tokenStr,
                                    }
                                );
                                break;

                            case FunctionType.Function:
                                tokenList.Add(
                                    new Token
                                    {
                                        Type = TokenType.BuiltInFunction,
                                        LineNo = lineno,
                                        Offset = offset,
                                        File = _current_file,
                                        Text = text,
                                        Function = "",
                                        TokenString = tokenStr,
                                    }
                                );
                                break;

                            default:
                                tokenList.Add(
                                    new Token
                                    {
                                        Type = TokenType.Symbol,
                                        LineNo = lineno,
                                        Offset = offset,
                                        File = _current_file,
                                        Text = text,
                                        Function = "",
                                        TokenString = tokenStr,
                                    }
                                );
                                break;
                        }
                    }
                    else
                    {
                        tokenList.Add(
                            new Token
                            {
                                Type = TokenType.Symbol,
                                LineNo = lineno,
                                Offset = offset,
                                File = _current_file,
                                Text = text,
                                Function = "",
                                TokenString = tokenStr,
                            }
                        );

                    }
                }

                return tokenSym;
            }
        }
        /// <summary>
        /// 
        /// </summary>
        /// <param name="args"></param>
        /// <returns></returns>
        public static Callable BuildUserFunction(Vector args)
        {
            if (args.Count < 2)
            {
                BraidRuntimeException(
                    "lambda definitions requires at least two arguments e.g. (lambda [args...] body ... )");
            }

            // First handle patterns
            Callable callable;
            if (Symbol.sym_pipe.Equals(args[0]) || Symbol.sym_pipe.Equals(args[1]))
            {
                var matcher = parsePattern("lambda", args, 0);
                matcher.File = Braid._current_file;
                matcher.Name = "lambda";
                matcher.Environment = CallStack;
                callable = matcher;
            }
            else
            {
                var lambda = new UserFunction("lambda");
                lambda = parseFunctionBody(lambda, "lambda", args, 0);
                lambda.File = Braid._current_file;
                lambda.Name = "lambda";
                lambda.Environment = CallStack;
                callable = lambda;
            }

            return callable;
        }

        /// <summary>
        /// Function to process member arguments to the 'deftype' and 'definterface' functions.
        /// </summary>
        /// <param name="funcName">The name of the function calling this routine e.g. 'deftype' or 'definterface'</param>
        /// <param name="args">The arguments to process</param>
        /// <param name="typeName">The name of the type being generated</param>
        /// <param name="memberDict">A dictionary of data members</param>
        /// <param name="methods">A list of methods to define on the types.</param>
        private static void ProcessTypeDefMembers(string funcName, Vector args, string typeName, out OrderedDictionary memberDict, out List<Tuple<Symbol, bool, UserFunction>> methods)
        {
            memberDict = new OrderedDictionary(StringComparer.OrdinalIgnoreCase);
            methods = null;
            object type = null;
            var members = args.GetRange(1, args.Count - 1);
            int mi = 0;

            while (mi < members.Count)
            {
                object val = members[mi];
                if (val is KeywordLiteral klit)
                {
                    if (klit != KeywordLiteral.klit_defm)
                    {
                        BraidRuntimeException($"The keyword '{klit}' is not valid for '{funcName}'. Only ':defm' and ':defs' are allowed.");
                    }

                    if (mi + 2 >= members.Count)
                    {
                        BraidRuntimeException(
                            $"{funcName}: incomplete method definition; a method requires both a name and a lambda. Syntax: :defm methodName (lambda [...] ...)"
                       );
                    }

                    mi++;

                    object nameObject = members[mi++];
                    if (nameObject is s_Expr || nameObject == null)
                    {
                        BraidRuntimeException(
                            $"{funcName}: the name of a method must be a symbol, not '{nameObject}'. (Perhaps you are missing the name?) Syntax: :defm methodName (lambda [...] ...)"
                        );
                    }

                    string nameString = nameObject.ToString();
                    bool isStatic = nameString[0] == '/';
                    if (isStatic)
                    {
                        nameString = nameString.Substring(1);
                    }

                    Symbol methodName = Symbol.FromString(nameString);
                    UserFunction methodBody = null;

                    object lambdaval = null;
                    if (members[mi] is FunctionLiteral mlit)
                    {
                        lambdaval = mlit.Value;
                    }

                    if (lambdaval is PatternFunction)
                    {
                        BraidRuntimeException($"{funcName}: when defining method '{methodName}': pattern lambdas cannot be used " +
                            "as the body for a method at this time. A conventional lambda is required e.g. (fn this args... -> body...)");
                    }

                    if (lambdaval != null)
                    {
                        methodBody = (UserFunction)lambdaval;
                    }
                    else
                    {
                        methodBody = methodBody as UserFunction;
                    }

                    if (methodBody == null)
                    {
                        BraidRuntimeException($"{funcName}: missing method body for method '{methodName}'; a lambda must be provided, not '{members[mi]}'");
                    }

                    var argdecl = methodBody.Arguments;
                    if (!isStatic && argdecl.Count < 1)
                    {
                        BraidRuntimeException(
                            $"Defining method '{methodName}': instance methods must take at least one argument which " +
                            "is the 'this' pointer for the object e.g. (fn this args... -> body...)");
                    }

                    methodBody.Environment = CallStack;

                    if (methods == null)
                    {
                        methods = new List<Tuple<Symbol, bool, UserFunction>>();
                    }

                    methods.Add(new Tuple<Symbol, bool, UserFunction>(methodName, isStatic, methodBody));
                }
                else
                {
                    // Add a data member
                    if (val is Type || val is TypeLiteral)
                    {
                        type = val;
                    }
                    else
                    {
                        if (type == null)
                        {
                            type = typeof(object);
                        }

                        string memberName = val.ToString();
                        if (memberDict.Contains(memberName))
                        {
                            BraidRuntimeException($"{funcName}: duplicate member name '{memberName}' encountered while defining type '{typeName}");
                        }

                        memberDict.Add(memberName, type);
                        type = null;
                    }
                }
                mi++;
            }
        }

        /// <summary>
        /// Parse a vector of elements into a pattern matcher
        /// </summary>
        /// <param name="args">The elements to process</param>
        /// <returns>a compiled matcher object.</returns>
        public static PatternFunction parsePattern(string name, Vector args, int index, bool noEnv = false)
        {
            TypeLiteral returnType = null;
            if (args[index] is TypeLiteral tlit)
            {
                returnType = tlit;
                index++;
            }

            if (!Symbol.sym_pipe.Equals(args[index]))
            {
                BraidRuntimeException(
                    $"Parsing pattern; '|' was expected indicating the start of a pattern, not '{args[index]}'");
            }
            else
            {
                index++;
            }

            var avect = new Vector();
            Vector patElements = new Vector();
            Vector bodyElements = new Vector();
            Vector patterns = new Vector();

            var caller = CallStack.Caller;
            PatternFunction matcher = new PatternFunction(name, caller.File, caller.LineNo, caller.Text, caller.Offset);
            matcher.IsFunction = !noEnv;
            bool readingPattern = true;
            bool allowBacktracking = false;
            s_Expr whereClause = null;
            KeywordLiteral whereKeyword = KeywordLiteral.FromString(":where");

            for (; index < args.Count; index++)
            {
                object arg = args[index];

                if (arg != null)
                {
                    // BUGBUGBUG NEW SUPPORT FOR SYMBOL where
                    if ((arg is KeywordLiteral klit && klit.KeywordId == whereKeyword.KeywordId) || (arg is Symbol symWhere && symWhere == Symbol.sym_keyword))
                    {
                        ++index;
                        if (index >= args.Count || args[index] == null || args[index] is Symbol s && s == Symbol.sym_arrow)
                        {
                            BraidRuntimeException("Missing condition after :where in a pattern clause.", null, matcher);
                        }

                        whereClause = args[index] as s_Expr;
                        if (whereClause == null)
                        {
                            BraidRuntimeException($"The condition after :where in a pattern clause must be an s-expression, not '{args[index]}");
                        }

                        continue;
                    }

                    if (arg is Symbol sym && (sym == Symbol.sym_arrow || sym == Symbol.sym_leftarrow))
                    {
                        if (sym == Symbol.sym_leftarrow)
                        {
                            allowBacktracking = true;
                        }

                        readingPattern = false;
                        continue;
                    }
                }

                if (Symbol.sym_pipe.Equals(arg))
                {
                    if (readingPattern)
                    {
                        // BUGBUGBUG - need to figure out the right conditions to emit this message.
                        // BraidRuntimeException("Incomplete pattern/action: while reading the pattern clause, no '->' was found. Please update the clause to include the actions part starting with '->'."); 
                        patterns.Add(patElements);
                        patElements = new Vector();
                        continue;
                    }
                    else
                    {
                        readingPattern = true;
                        foreach (var pat in patterns)
                        {
                            matcher.AddClause((Vector)pat, bodyElements, whereClause, !noEnv, allowBacktracking);
                        }

                        matcher.AddClause(patElements, bodyElements, whereClause, !noEnv, allowBacktracking);
                        patterns.Clear();
                        patElements = new Vector();
                        bodyElements = new Vector();
                        whereClause = null;
                        allowBacktracking = false;
                        continue;
                    }
                }

                if (readingPattern)
                {
                    object val = args[index];
                    switch (val)
                    {
                        case VectorLiteral vlit:
                            if (vlit.ValueList != null)
                                patElements.Add(vlit);
                            else
                                patElements.Add(new Vector());
                            break;
                        case KeywordLiteral klit:
                            // Treat a keyword in a pattern as a string
                            patElements.Add(klit.Value);
                            break;
                        default:
                            patElements.Add(args[index]);
                            break;
                    }
                }
                else
                {
                    bodyElements.Add(args[index]);
                }
            }

            // Add the trailing patterns
            foreach (var pat in patterns)
            {
                matcher.AddClause((Vector)pat, bodyElements, whereClause, !noEnv, allowBacktracking);
            }

            matcher.AddClause(patElements, bodyElements, whereClause, !noEnv, allowBacktracking);

            matcher.ReturnType = returnType;

            return matcher;
        }

        /// <summary>
        /// Used by "defn" to parse the body of a function
        /// </summary>
        /// <param name="args"></param>
        /// <returns></returns>
        static UserFunction parseFunctionBody(UserFunction lambda, string name, Vector args, int index = 1)
        {
            TypeLiteral returnType = null;
            if (args[index] is TypeLiteral tlit)
            {
                returnType = tlit;
                index++;
            }

            if (!(args[index] is VectorLiteral || args[index] is Vector))
            {
                BraidRuntimeException(
                    $"parsing {name}: arguments should be a vector of symbols not '{args[index]}'.");
                return null;
            }

            // Copy the elements from argument vector
            Vector avect = null;

            // Copy keywords from the argument vector
            Dictionary<string, KeywordLiteral> kwargs = null;

            if (args[index] is Vector vect)
            {
                // BUGBUGBUG - still need to process/validate the vector elements in this case. Or maybe disallow it?
                avect = vect;
            }
            else
            {
                VectorLiteral vlit = args[index] as VectorLiteral;
                avect = new Vector();
                kwargs = null;

                if (vlit.ValueList != null)
                {
                    foreach (var e in vlit.ValueList)
                    {
                        if (e is Symbol syme)
                        {
                            // BUGBUGBUG - need to rationalize this code
                            avect.Add(new VarElement(syme));
                        }
                        else if (e is VectorLiteral vlitn)
                        {
                            var peList = PatternClause.CompilePatternElements(new Vector(vlitn.ValueList), out int patternArity, out bool hasStarFunction);
                            avect.Add(new NestedPatternElement(peList, patternArity, hasStarFunction));
                        }
                        else if (e is TypeLiteral ttlit)
                        {
                            avect.Add(new TypeElement(ttlit, null));
                        }
                        else if (e is DictionaryLiteral dlit)
                        {
                            avect.Add(new PropertyPatternElement(dlit));
                        }
                        else if (e is Regex tre)
                        {
                            avect.Add(new RegexElement(tre, null));
                        }
                        else if (e is s_Expr sexpr)
                        {
                            int scount = sexpr.Count;
                            if (scount < 1 || scount > 3)
                            {
                                BraidRuntimeException($"defining function {name}: args should be a symbol, keyword or list of 2-3 elements, not '{e}'");
                            }

                            var obj = sexpr.Car;
                            var tcons = obj as TypeLiteral;
                            var dcons = obj as DictionaryLiteral;
                            var re = obj as Regex;
                            var psym = obj as Symbol;
                            Symbol var = null;
                            MatchElementBase meb = null;

                            sexpr = (s_Expr)sexpr.Cdr;

                            if (psym != null)
                            {
                                // handle initialized variables like (foo 13)
                                meb = new VarElement(psym);
                                if (sexpr != null)
                                {
                                    meb.SetDefaultValue(sexpr.Car);
                                }
                                avect.Add(meb);
                                continue;
                            }

                            if (sexpr != null && sexpr.Car is Symbol vsym)
                            {
                                var = vsym;
                            }

                            if (re != null)
                            {
                                meb = new RegexElement(re, var);
                            }
                            else if (tcons != null)
                            {
                                meb = new TypeElement(tcons, var);
                            }
                            else if (dcons != null)
                            {
                                meb = new PropertyPatternElement(dcons);
                            }
                            else if (psym != null)
                            {
                                meb = new VarElement(psym, var);
                            }
                            else if (obj != null)
                            {
                                meb = new GenericElement(obj, var);
                            }
                            else
                            {
                                meb = new VarElement(var);
                            }

                            if (sexpr != null)
                            {
                                sexpr = sexpr.Cdr as s_Expr;
                                if (sexpr != null)
                                {
                                    meb.SetDefaultValue(sexpr.Car);
                                }
                            }

                            avect.Add(meb);
                        }
                        else if (e is KeywordLiteral klit)
                        {
                            if (kwargs == null)
                            {
                                kwargs = new Dictionary<string, KeywordLiteral>(new ObjectComparer());
                            }

                            kwargs.Add(klit.BaseName, klit);
                        }
                        else if (e is ArgIndexLiteral alit)
                        {
                            avect.Add(alit);
                        }
                        else
                        {
                            avect.Add(new GenericElement(e, null));
                        }
                    }
                }
            }

            // Now iterate through the body of the function
            index++;
            s_Expr body = null;
            s_Expr end = null;
            while (index < args.Count)
            {
                object element = args[index++];
                if (!(element is s_Expr selement))
                {
                    if (element is IEnumerable eelem && !(element is string || element is IDictionary))
                    {
                        element = s_Expr.FromEnumerable(eelem);
                    }
                }

                if (body == null)
                {
                    body = end = new s_Expr(element);
                }
                else
                {
                    end = end.Add(element);
                }
            }

            lambda.FunctionType = FunctionType.Function;
            lambda.Arguments = avect;
            lambda.Body = body;
            lambda.ReturnType = returnType;
            lambda.Environment = CallStack;
            lambda.Keywords = kwargs;
            return lambda;
        }

    }
}
