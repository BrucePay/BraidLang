/////////////////////////////////////////////////////////////////////////////
//
// The Braid Programming Language - Init routine that defines built-ins and
//                                  sets up other interpreter state.
//
// Copyright (c) 2023 Bruce Payette (see LICENCE file) 
//
////////////////////////////////////////////////////////////////////////////

using System;
using System.Linq;
using System.Numerics;
using System.Collections;
using System.Collections.Specialized;
using System.Text;
using System.Text.RegularExpressions;
using System.Collections.ObjectModel;
using System.Collections.Generic;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Threading.Tasks;
using System.IO;
using System.Reflection;
using System.Reflection.Emit;
using Microsoft.PowerShell.Commands;

namespace BraidLang
{

    //////////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// Partial class for the init() routine
    /// </summary>
    public static partial class Braid
    {
        public static Dictionary<Symbol, Func<Vector, object>> FunctionTable =
            new Dictionary<Symbol, Func<Vector, object>>();

        public static Dictionary<Symbol, Func<Vector, object>> SpecialForms =
            new Dictionary<Symbol, Func<Vector, object>>();

        //BUGBUGBUG - this only works if it's called before init()
        // Used by the PowerShell "loadbraid.ps1" script
        public static void SetFunction(string funcName, Func<Vector, object> func)
        {
            FunctionTable[Symbol.FromString(funcName)] = func;
        }

        public static void SetSpecialForm(string funcName, Func<Vector, object> func)
        {
            SpecialForms[Symbol.FromString(funcName)] = func;
        }

        // Initialize the random number generator used by the "random" function.
        public static Random _rnd = new Random((int)(System.Diagnostics.Process.GetCurrentProcess().Id
                          + System.DateTime.Now.Ticks));

        /// <summary>
        /// Predicate that returns true if it's argument is a number
        /// </summary>
        /// <param name="val"></param>
        /// <returns></returns>
        public static bool Numberp(object val)
        {
            return val is int || val is long || val is float || val is double || val is BigInteger
                || val is BigDecimal|| val is byte || val is sbyte || val is UInt32 || val is UInt64;
        }

        /// <summary>
        /// The Init() routine should only be run once. This variable controls that.
        /// </summary>
        static bool _runInit = true;

        /// <summary>
        /// Initialize the Braid interpreter tables. Only do this once.
        /// </summary>
        public static void Init()
        {
            if (!_runInit)
            {
                return;
            }

            _runInit = false;

            CallStack.SetTypeAlias("BraidType", typeof(BraidLang.BraidTypeBuilder));
            CallStack.SetTypeAlias("List", typeof(BraidLang.s_Expr));
            CallStack.SetTypeAlias("Symbol", typeof(Symbol));
            CallStack.SetTypeAlias("Keyword", typeof(KeywordLiteral));
            CallStack.SetTypeAlias("ISeq", typeof(ISeq));
            CallStack.SetTypeAlias("Any", typeof(object));
            CallStack.SetTypeAlias("TypeLiteral", typeof(BraidLang.TypeLiteral));
            CallStack.SetTypeAlias("Vector", typeof(Vector));
            CallStack.SetTypeAlias("HashSet", typeof(System.Collections.Generic.HashSet<object>));
            CallStack.SetTypeAlias("VectorLiteral", typeof(BraidLang.VectorLiteral));
            CallStack.SetTypeAlias("IDictionary", typeof(System.Collections.IDictionary));
            CallStack.SetTypeAlias("Lambda", typeof(UserFunction));
            CallStack.SetTypeAlias("UserFunction", typeof(UserFunction));
            CallStack.SetTypeAlias("Function", typeof(Function));
            CallStack.SetTypeAlias("Pattern", typeof(PatternFunction));
            CallStack.SetTypeAlias("PatternFunction", typeof(PatternFunction));
            CallStack.SetTypeAlias("Callable", typeof(Callable));
            CallStack.SetTypeAlias("Task", typeof(Task));
            CallStack.SetTypeAlias("IEnumerable", typeof(System.Collections.IEnumerable));
            CallStack.SetTypeAlias("ICollection", typeof(System.Collections.ICollection));
            CallStack.SetTypeAlias("keyword", typeof(BraidLang.KeywordLiteral));
            CallStack.SetTypeAlias("Slice", typeof(BraidLang.Slice));
            CallStack.SetTypeAlias("Channel", typeof(System.Collections.Concurrent.BlockingCollection<object>));
            CallStack.SetTypeAlias("TokenList", typeof(System.Collections.Generic.List<BraidLang.Token>));
            CallStack.SetTypeAlias("NamedParameter", typeof(BraidLang.NamedParameter));
            CallStack.SetTypeAlias("Braid", typeof(BraidLang.Braid));
            CallStack.SetTypeAlias("uint", typeof(System.UInt32));
            CallStack.SetTypeAlias("ObjectComparer", typeof(BraidLang.ObjectComparer));
            CallStack.SetTypeAlias("IEnumerable", typeof(System.Collections.IEnumerable));
            CallStack.SetTypeAlias("BraidComparer", typeof(BraidLang.BraidComparer));
            CallStack.SetTypeAlias("ExpandableString", typeof(BraidLang.ExpandableStringLiteral));
            CallStack.SetTypeAlias("ExpandableStringLiteral", typeof(BraidLang.ExpandableStringLiteral));
            CallStack.SetTypeAlias("BigDecimal", typeof(BraidLang.BigDecimal));

            CallStack.Set("args", null);           // Create the args variable at the top level  

            // Built-in Braid variables. This will throw if they are already initialized.
            CallStack.Const(Symbol.sym_nil, null);
            CallStack.Const(Symbol.sym_null, null);
            CallStack.Sink(Symbol.sym_underbar);
            CallStack.Const("true", BoxedTrue);
            CallStack.Const("false", BoxedFalse);
            CallStack.Const("BraidHome", BraidHome); // The directory containing the braid binaries
            CallStack.Const("PI", Math.PI);

            /////////////////////////////////////////////////////////////////////
            ///
            /// Implement the recur and recur-to function.
            /// 
            FunctionTable[Symbol.sym_recur] =
                recur_function = (Vector args) => new BraidRecurOperation(args);

            FunctionTable[Symbol.sym_recur_to] =
                recur_to_function = (Vector args) => new BraidRecurOperation((Callable)args[0], args.GetRangeVect(1));

            /////////////////////////////////////////////////////////////////////
            ///
            /// Fork the lambda environment so continuation passing works
            /// 
            FunctionTable[Symbol.FromString("continuation")] = (Vector args) =>
            {
                if (args != null && args.Count == 1 && args[0] is Callable lambda)
                {
                    lambda.Environment = (PSStackFrame)Braid.CallStack.Fork();
                    return lambda;
                }
                BraidRuntimeException($"The 'continuation' function requires 1 argument which must be the lambda to fork");
                return null;
            };

            /// Get the actual arguments for the current function.
            FunctionTable[Symbol.FromString("get-args")] = (Vector args) =>
            {
                var stackArgs = CallStack.Arguments;
                if (stackArgs != null && stackArgs.Count > 0)
                {
                    return stackArgs;
                }

                if (_callStackStack != null && _callStackStack.Count > 0)
                {
                    var tos = _callStackStack.Peek();
                    if (tos != null && tos.Arguments != null)
                    {
                        return tos.Arguments;
                    }
                }

                return new Vector();
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Implement the 'loop' function.
            /// 
            SpecialForms[Symbol.sym_loop] = (Vector args) =>
            {
                object userFuncResult = null;
                int funindex = 0;
                int funcount = args.Count;
                Vector newArgs = null;
                List<BraidVariable> loopvars = new List<BraidVariable>();

                VectorLiteral loopargs = args[funindex] as VectorLiteral;
                if (loopargs == null)
                {
                    Braid.BraidRuntimeException($"the first argument to loop must be a vector of name/value pairs, not '${args[0]}'");
                }

                if (loopargs.ValueList != null && loopargs.ValueList.Count() % 2 != 0)
                {
                    Braid.BraidRuntimeException($"The argument list for 'loop' must contain an even number of items, "
                        + $"the current list contains ${loopargs.ValueList.Count()} elements.");
                }

                // Set up a new stack frame for the loop execution.
                PSStackFrame callStack = null;

                try
                {
                    callStack = PushCallStack(new PSStackFrame(_current_file, "loop", CallStack.Caller, CallStack));

                    if (loopargs.ValueList != null)
                    {
                        // Get all of the variables upfront so subsequent binds don't require a lookup.
                        Symbol argSym = null;
                        foreach (var e in loopargs.ValueList)
                        {
                            if (argSym == null && e is Symbol loopsym)
                            {
                                argSym = loopsym;
                            }
                            else if (argSym != null)
                            {
                                object valToBind = Eval(e);
                                var loopvar = callStack.GetOrCreateLocalVar(argSym);
                                loopvar.Value = valToBind;
                                loopvars.Add(loopvar);
                                argSym = null;
                            }
                            else
                            {
                                BraidRuntimeException($"The pattern for loop arguments is [ sym1 val1 sym2 val 2]");
                            }
                        }
                    }

                loop:
                    if (_stop)
                    {
                        return null;
                    }

                    if (newArgs != null)
                    {
                        if (newArgs.Count != loopvars.Count)
                        {
                            BraidRuntimeException("wrong number of args in loop. Calls to recur must pass the same number "
                                + "of args that are defined at the top of the 'loop'.");
                        }

                        int naoffset = 0;
                        for (var index = 0; index < loopvars.Count; index++)
                        {
                            loopvars[index].Value = newArgs[naoffset++];
                        }
                    }

                    funindex = 1;
                    while (funindex < funcount)
                    {
                        if (_stop)
                        {
                            break;
                        }

                        userFuncResult = Eval(args[funindex++]);
                        if (userFuncResult is BraidRecurOperation re)
                        {
                            if (re.Target == null)
                            {
                                newArgs = re.RecurArgs;
                                goto loop;
                            }
                            else
                            {
                                return re;
                            }
                        }
                        else if (userFuncResult is BraidReturnOperation retop)
                        {
                            return retop;
                        }
                        else if (userFuncResult is BraidFlowControlOperation)
                        {
                            return userFuncResult;
                        }
                    }
                }
                finally
                {
                    PopCallStack();
                }

                return userFuncResult;
            };

            /////////////////////////////////////////////////////////////////////
            // Dump the symbol table to the screen
            FunctionTable[Symbol.FromString("show-symbols")] = (Vector args) =>
            {
                Symbol.DumpSymbols();
                return null;
            };

            /////////////////////////////////////////////////////////////////////
            FunctionTable[Symbol.FromString("scs")] =
            FunctionTable[Symbol.FromString("show-callstack")] = (Vector args) =>
            {
                Regex filter;

                if (args.Count == 1)
                {
                    if (args[0] == null)
                    {
                        BraidRuntimeException("The first argument to 'Show-CallStack' must be a string or regular expression, not null.");
                    }

                    if (args[0] is Regex re)
                    {
                        filter = re;
                    }
                    else
                    {
                        filter = new Regex(args[0].ToString(), RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
                    }
                }
                else
                {
                    filter = new Regex(".", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
                }

                if (CallStack.NamedParameters != null && CallStack.NamedParameters.ContainsKey("verbose"))
                {
                    Braid.PrintCallStack(true, filter);
                }
                else
                {
                    Braid.PrintCallStack(false, filter);
                }

                return null;
            };

            /////////////////////////////////////////////////////////////////////
            // Function to return the list of defined symbols
            FunctionTable[Symbol.FromString("get-symbols")] = (Vector args) =>
            {
                return new Vector(Symbol._symbolTable.Values.OrderBy((it) => it.Value));
            };

            /////////////////////////////////////////////////////////////////////
            /// Breaks out of a loop.
            FunctionTable[Symbol.FromString("break")] = (Vector args) =>
            {
                if (args.Count > 1)
                {
                    BraidRuntimeException($"The break function takes 0 or 1 arguments; not {args.Count}");
                }

                var breakOp = new BraidBreakOperation();
                if (args.Count == 1)
                {
                    breakOp.BreakResult = args[0];
                }

                return breakOp;
            };

            /////////////////////////////////////////////////////////////////////
            /// Function to quit the Braid interpreter.
            FunctionTable[Symbol.FromString("quit")] = (Vector args) =>
            {
                if (args.Count > 1)
                {
                    BraidRuntimeException($"the 'quit' function takes 0 or 1 parameters, not {args.Count}.");
                }

                ExitBraid = true;

                object result = args.Count == 1 ? args[0] : null;
                throw new BraidExitException(result);
            };

            /////////////////////////////////////////////////////////////////////
            /// Continues the next iteration of a loop.
            FunctionTable[Symbol.FromString("continue")] = (Vector args) =>
            {
                return new BraidContinueOperation();
            };

            /////////////////////////////////////////////////////////////////////
            FunctionTable[Symbol.sym_fail] = (Vector args) =>
            {
                return new BraidFailOperation();
            };

            /////////////////////////////////////////////////////////////////////
            /// Return from a function/lambda optionally returning a value
            FunctionTable[Symbol.FromString("return")] = (Vector args) =>
            {
                object valToReturn = null;
                if (args.Count > 0)
                {
                    // If there is one value to return, return it as a scalar
                    // Multiple values are returned as a vector
                    if (args.Count == 1)
                    {
                        valToReturn = args[0];
                    }
                    else
                    {
                        valToReturn = args;
                    }
                }

                return new BraidReturnOperation(valToReturn);
            };

            /////////////////////////////////////////////////////////////////////
            /// Get the value associated with the argument key.
            FunctionTable[Symbol.FromString("Get-Assoc")] = (Vector args) =>
            {
                if (args.Count < 1 || args.Count > 2 || args[0] == null)
                {
                    BraidRuntimeException("The 'get-assoc' command takes an key object and an optional " +
                                        "property name: (get-assoc keyobj propertyName])");
                }

                if (args.Count == 1)
                {
                    return GetAssoc(args[0]);
                }
                else
                {
                    return GetAssoc(args[0], args[1].ToString());
                }
            };

            /////////////////////////////////////////////////////////////////////
            /// Set up an association between a key and a value.
            FunctionTable[Symbol.FromString("Set-Assoc")] = (Vector args) =>
            {
                if (args.Count != 3 || args[0] == null || args[1] == null)
                {
                    BraidRuntimeException("The 'set-assoc' command takes an key object, a property name and the " +
                                        "value to set: (set-assoc keyobj propertyName val])");
                }

                PutAssoc(args[0], args[1].ToString(), args[2]);
                return null;
            };

            /////////////////////////////////////////////////////////////////////
            FunctionTable[Symbol.FromString("load")] = (Vector args) =>
            {
                if (args.Count != 1 || args[0] == null)
                {
                    BraidRuntimeException("The 'load' function takes exactly one parameter: the name of the file to load.");
                }

                string scriptName = args[0].ToString();
                if (scriptName.LastIndexOf(".tl") == -1)
                {
                    scriptName += ".tl";
                }

                string scriptPath = ResolvePath(scriptName);
                string script = File.ReadAllText(scriptPath);

                string old_FileName = Braid._current_file;
                Braid._current_file = scriptPath;
                string old_Function = Braid._current_function;
                Braid._current_function = "load";
                try
                {
                    // Parse the file
                    s_Expr parsedScript = Parse(script);
                    if (parsedScript == null)
                    {
                        return null;
                    }

                    // Evaluate in the current scope
                    foreach (var expr in parsedScript.GetEnumerable())
                    {
                        if (Eval(expr) is BraidReturnOperation retop)
                        {
                            return null;
                        }
                    }
                }
                finally
                {
                    Braid._current_file = old_FileName;
                    Braid._current_function = old_Function;
                }

                return null;
            };

            /////////////////////////////////////////////////////////////////////

            FunctionTable[Symbol.FromString("file/parse")] = (Vector args) =>
            {
                if (args.Count != 1 || args[0] == null)
                {
                    BraidRuntimeException("The 'file/parse' function takes exactly one parameter: the name of the file to parse.");
                }

                string scriptName = args[0].ToString();
                if (scriptName.LastIndexOf(".tl") == -1 && scriptName.LastIndexOf(".json") == -1)
                {
                    scriptName += ".tl";
                }

                string scriptPath = ResolvePath(scriptName);
                string script = File.ReadAllText(scriptPath);

                string old_FileName = Braid._current_file;
                string old_Function = Braid._current_function;
                Braid._current_file = scriptPath;
                Braid._current_function = "file/parse";
                try
                {
                    // Parse the file
                    var tree = Parse(script);
                    if (tree != null && tree.IsLambda && tree.Environment == null)
                    {
                        tree.Environment = CallStack;
                    }

                    return tree;
                }
                catch (Exception e)
                {
                    while (e is TargetInvocationException tie)
                    {
                        e = tie.InnerException;
                    }

                    if (e is BraidUserException)
                    {
                        throw e;
                    }

                    BraidRuntimeException($"The 'file/parse' function encountered an error parsing file '{scriptName}': {e.Message}", e);
                    return null;
                }
                finally
                {
                    Braid._current_file = old_FileName;
                    Braid._current_function = old_Function;
                }
            };
            FunctionTable[Symbol.FromString("parse-file")] = FunctionTable[Symbol.FromString("file/parse")];


            /////////////////////////////////////////////////////////////////////
            FunctionTable[Symbol.FromString("tokenize-text")] = (Vector args) =>
            {
                if (args.Count < 1 || args.Count > 3 || args[0] == null)
                {
                    BraidRuntimeException("The 'tokenize-text' function takes 1-3 parameters: (tokenize-text <text> <low> <upper>).");
                }

                List<Token> tokenList = new List<Token>();

                try
                {
                    Parse(args[0].ToString(), tokenList);
                }
                catch
                {
                    // do nothing
                }

                if (args.Count == 2)
                {
                    int low = ConvertToHelper<int>(args[1]);
                    return tokenList.Where(n => n.Offset >= low);
                }

                if (args.Count == 3)
                {
                    int low = ConvertToHelper<int>(args[1]);
                    int high = ConvertToHelper<int>(args[2]);
                    return tokenList.Where(n => n.Offset + n.Length >= low && n.Offset <= high);
                }

                return tokenList;
            };

            /////////////////////////////////////////////////////////////////////
            CallStack.Const(Symbol.FromString("using-module"),
                new Macro("using-module", (Vector args) =>
                {
                    if (args.Count != 1 || args[0] == null)
                    {
                        BraidRuntimeException("The 'using-module' macro takes exactly one parameter: the name of the module to load.");
                    }

                    string scriptName = args[0].ToString();
                    if (scriptName.LastIndexOf(".tl") == -1)
                    {
                        scriptName += ".tl";
                    }

                    string scriptPath = null;
                    try
                    {
                        scriptPath = ResolvePath(scriptName);
                    }
                    catch (Exception)
                    {
                        try
                        {
                            scriptPath = ResolvePath(System.IO.Path.Combine(BraidHome, scriptName));
                        }
                        catch (Exception e)
                        {
                            while (e.InnerException != null)
                            {
                                e = e.InnerException;
                            }

                            BraidRuntimeException($"Processing '(using-module {scriptName})' failed with message: {e.Message}.", e);
                        }
                    }

                    string old_FileName = Braid._current_file;
                    string script = File.ReadAllText(scriptPath);
                    Braid._current_file = scriptName;

                    try
                    {
                        // Parse the file
                        s_Expr parsedScript = Parse(script);
                        if (parsedScript == null)
                        {
                            return null;
                        }

                        // Evaluate in the current scope
                        foreach (var expr in parsedScript.GetEnumerable())
                        {
                            Eval(expr);
                        }
                    }
                    finally
                    {
                        Braid._current_file = old_FileName;
                    }

                    return null;
                }));

            /////////////////////////////////////////////////////////////////////
            SpecialForms[Symbol.FromString("try")] = (Vector args) =>
            {
                object catchBlock = null;
                object finallyBlock = null;
                PSStackFrame callStack = Braid.CallStack;
                var namedParameters = callStack.NamedParameters;

                if (namedParameters != null)
                {
                    NamedParameter outval;
                    if (namedParameters.TryGetValue("catch", out outval))
                    {
                        catchBlock = outval.Expression;
                    }

                    if (namedParameters.TryGetValue("finally", out outval))
                    {
                        finallyBlock = outval.Expression;
                    }
                }

                object result = null;
                try
                {
                    int len = args.Count;
                    for (var index = 0; index < len; index++)
                    {
                        var arg = args[index];
                        result = Eval(arg);
                    }
                }
                catch (BraidExitException)
                {
                    throw;
                }
                catch (Exception e)
                {
                    if (catchBlock != null)
                    {
                        if (catchBlock is IInvokeableValue cbe)
                        {
                            result = cbe.Invoke(new Vector { e });
                        }
                        else if (catchBlock is FunctionLiteral llit)
                        {
                            Callable action = (Callable)llit.Value;
                            result = action.Invoke(new Vector { e });
                        }
                        else
                        {
                            result = Eval(catchBlock);
                        }
                    }
                    else
                    {
                        // If there's no catch block, return the exception
                        result = e;
                    }
                }
                finally
                {
                    //BUGBUGBUG - this doesn't special-case callables....
                    if (finallyBlock != null)
                    {
                        Eval(finallyBlock);
                    }
                }

                return result;
            };

            /////////////////////////////////////////////////////////////////////
            FunctionTable[Symbol.FromString("throw")] = (Vector args) =>
            {
                ///BUGBUGBUG - should allow re-throwing the ambient exception.
                if (args.Count < 1 || args[0] == null)
                {
                    Braid.BraidRuntimeException(
                        "no non-null arguments were provided. The throw function requires at least one string argument e.g. (throw \"Hi\")");
                    return null;
                }
                var sb = new StringBuilder();
                bool first = true;
                args.ForEach((item) =>
                {
                    if (first) { first = false; } else { sb.Append(' '); }
                    if (item != null) sb.Append(item.ToString());
                });

                BraidRuntimeException(sb.ToString());
                return null;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Retrieve all of the defined functions
            /// 
            FunctionTable[Symbol.FromString("functions")] = (Vector args) =>
            {
                Regex pattern = null;
                if (args.Count > 0 && args[0] != null)
                {
                    pattern = new Regex(args[0].ToString(), RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
                }
                else
                {
                    pattern = new Regex(".", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
                }

                Vector result = new Vector();

                foreach (var e in Symbol._symbolTable.Where(v => pattern.Match(v.Key.ToString()).Success))
                {
                    // From the variable table, only add things that look like functions.
                    var definition = CallStack.GetValue(e.Value);
                    if ((definition is s_Expr sexpr && sexpr.IsLambda)
                        || definition is IInvokeableValue
                        || definition is ScriptBlock
                    )
                    {
                        var val = new KeyValuePair<Symbol, object>(e.Value, definition);
                        result.Add(val);
                    }
                }

                return new Vector(result.OrderBy((dynamic v) => v.Key.ToString()).Distinct());
            };

            /////////////////////////////////////////////////////////////////////
            FunctionTable[Symbol.sym_add] = (Vector args) =>
            {
                if (args.Count < 1)
                {
                    BraidRuntimeException("The '+' function requires 2 or more arguments.");
                    return null;
                }

                object first = args[0];

                if (args.Count == 1)
                {
                    return curryFunction(Symbol.sym_add, first);
                }

                switch (first)
                {
                    // Handle the string case
                    case string str:
                        StringBuilder sb = new StringBuilder();
                        foreach (var arg in args)
                        {
                            if (_stop)
                            {
                                break;
                            }

                            if (arg != null)
                            {
                                sb.Append(arg.ToString());
                            }
                        }
                        return sb.ToString();

                    case BigDecimal bd:
                        foreach (var arg in args.Skip(1))
                        {
                            if (_stop)
                            {
                                break;
                            }

                            if (arg != null)
                            {
                                switch (arg)
                                {
                                    case int ival:
                                        bd += (BigDecimal)ival;
                                        break;
                                    case long lval:
                                        bd += (BigDecimal)lval;
                                        break;
                                    case float fval:
                                        bd += (BigDecimal)fval;
                                        break;
                                    case double dval:
                                        bd += (BigDecimal)dval;
                                        break;
                                    case BigInteger bival:
                                        bd += new BigDecimal(bival, 0);
                                        break;
                                    case Decimal deval:
                                        bd += (BigDecimal)deval;
                                        break;
                                    default:
                                        bd += (BigDecimal)arg.ToString();
                                        break;
                                }
                            }
                        }
                        return bd;

                    case int ival1 when args.Count == 2 && args[1] is int ival2:
                        try
                        {
                            // checked operation will throw on overflow
                            return BoxInt(checked(ival1 + ival2));
                        }
                        catch
                        {
                            goto default;
                        }

                    case DateTime dt:
                        foreach (var arg in args)
                        {
                            if (_stop)
                            {
                                break;
                            }

                            if (arg == null)
                            {
                                continue;
                            }

                            if (args[1] is TimeSpan tspn)
                            {
                                return dt += tspn;
                            }
                            else if (args[1] is int intval)
                            {
                                var ts = new TimeSpan(0, 0, intval);
                                dt += ts;
                            }
                            else
                            {
                                BraidRuntimeException("+: you can only add a DateTime or TimeSpan object to a DateTime.");
                            }
                        }
                        return dt;

                    case TimeSpan dt:
                        foreach (var arg in args)
                        {
                            if (_stop)
                            {
                                break;
                            }

                            if (arg == null)
                            {
                                continue;
                            }

                            if (args[1] is TimeSpan tspn)
                            {
                                return dt += tspn;
                            }
                            else if (args[1] is int intval)
                            {
                                var ts = new TimeSpan(0, 0, intval);
                                dt += ts;
                            }
                            else
                            {
                                BraidRuntimeException("+: you can only add a DateTime or TimeSpan object to a TimeSpan.");
                            }
                        }
                        return dt;

                    default:
                        dynamic result = 0;
                        int indexer = 0;
                        dynamic val;
                        try
                        {
                            for (; indexer < args.Count; indexer++)
                            {
                                if (_stop)
                                {
                                    break;
                                }

                                val = args[indexer];
                                if (val == null)
                                {
                                    continue;
                                }

                                if (val is BigDecimal bd)
                                {
                                    result = (BigDecimal)result + bd;
                                }
                                else
                                {
                                    // Necessary because C# dynamic doesn't follow the left-hand rule and converts
                                    // everything to string if anything is a string.
                                    if (val is string str)
                                    {
                                        val = ConvertTo(str, result.GetType());
                                    }

                                    result = checked(result + val);
                                }
                            }

                            return result;
                        }
                        catch (OverflowException)
                        {
                            result = (long)result;
                            try
                            {
                                for (; indexer < args.Count; indexer++)
                                {
                                    if (_stop)
                                    {
                                        break;
                                    }

                                    val = args[indexer];
                                    if (val == null)
                                    {
                                        continue;
                                    }

                                    result = checked(result + val);
                                }
                                return result;
                            }
                            catch (OverflowException)
                            {
                                result = (double)result;
                                try
                                {
                                    for (; indexer < args.Count; indexer++)
                                    {
                                        if (_stop)
                                        {
                                            break;
                                        }

                                        val = args[indexer];
                                        if (val == null)
                                        {
                                            continue;
                                        }

                                        result = checked(result + val);
                                    }
                                    return result;
                                }
                                catch (OverflowException)
                                {
                                    result = (BigInteger)result;
                                    try
                                    {
                                        for (; indexer < args.Count; indexer++)
                                        {
                                            if (_stop)
                                            {
                                                break;
                                            }

                                            val = args[indexer];
                                            if (val == null)
                                            {
                                                continue;
                                            }

                                            result = checked(result + val);
                                        }
                                        return result;
                                    }
                                    catch (OverflowException)
                                    {
                                        BraidRuntimeException("The '+' operation overflowed all numeric types.");
                                    }
                                }
                            }
                        }
                        return null;
                }
            };

            /////////////////////////////////////////////////////////////////////
            FunctionTable[Symbol.sym_multiply] = (Vector args) =>
            {
                if (args.Count > 0)
                {
                    if (args.Count == 1)
                    {
                        return curryFunction(Symbol.sym_multiply, args[0]);
                    }

                    // If the first argument is a string that always wins.
                    if (args[0] is string argsstr)
                    {
                        if (args.Count > 2)
                        {
                            BraidRuntimeException("too many arguments to function '*' when multiplying a string. Usage: (* <string> <integer>).");
                        }

                        var count = 0;
                        try
                        {
                            count = ConvertToHelper<int>(args[1]);
                        }
                        catch (PSInvalidCastException psice)
                        {
                            BraidRuntimeException("when multiplying a string, the second argument to '*' must be an integer.", psice);
                        }

                        if (count < 0)
                        {
                            BraidRuntimeException($"When using '*' on a string, the second argument must be a " +
                                "positive integer, not {count} e.g. (* \".\" 30).");
                        }

                        StringBuilder sb = new StringBuilder(count * argsstr.Length);
                        while (count-- > 0)
                        {
                            if (_stop)
                            {
                                break;
                            }

                            sb.Append(argsstr);
                        }

                        return sb.ToString();
                    }

                    // If the first argument is a sequence, multiply the sequence
                    if (args[0] is ISeq seq)
                    {
                        if (args.Count > 2)
                        {
                            BraidRuntimeException("too many arguments to function '*' when multiplying a sequence. Usage: (* <sequence> <integer>)");
                        }

                        int count = 0;
                        try
                        {
                            count = ConvertToHelper<int>(args[1]);
                        }
                        catch (PSInvalidCastException psice)
                        {
                            BraidRuntimeException("when multiplying a sequence, the second argument to '*' must be an integer.", psice);
                        }

                        Vector vresult = new Vector(count * seq.Count);
                        while (count-- > 0)
                        {
                            if (_stop)
                            {
                                break;
                            }

                            vresult.AddRange(seq);
                        }

                        return vresult;
                    }

                    if (args[0] is BigDecimal bd)
                    {
                        foreach (object arg in args.Skip(1))
                        {
                            switch (arg)
                            {
                                case int ival:
                                    bd *= (BigDecimal)ival;
                                    break;
                                case long lval:
                                    bd *= (BigDecimal)lval;
                                    break;
                                case float fval:
                                    bd *= (BigDecimal)fval;
                                    break;
                                case double dval:
                                    bd *= (BigDecimal)dval;
                                    break;
                                case Decimal dval:
                                    bd *= (BigDecimal)dval;
                                    break;
                                default:
                                    bd *= (BigDecimal)(arg.ToString());
                                    break;
                            }
                        }

                        return bd;
                    }

                    dynamic result = 1;
                    int indexer = 0;
                    dynamic val;
                    try
                    {
                        for (; indexer < args.Count; indexer++)
                        {
                            if (_stop)
                            {
                                break;
                            }

                            val = args[indexer];
                            if (val is BigDecimal bdval)
                            {
                                result = (BigDecimal)result * bdval;
                            }
                            else
                            {
                                result = checked(result * val);
                            }
                        }

                        return result;
                    }
                    catch (OverflowException)
                    {
                        result = (long)result;
                        try
                        {
                            for (; indexer < args.Count; indexer++)
                            {
                                if (_stop)
                                {
                                    break;
                                }

                                val = args[indexer];
                                result = checked(result * val);
                            }
                            return result;
                        }
                        catch (OverflowException)
                        {
                            result = (BigInteger)result;
                            try
                            {
                                for (; indexer < args.Count; indexer++)
                                {
                                    if (_stop)
                                    {
                                        break;
                                    }

                                    val = args[indexer];
                                    result = checked(result * val);
                                }
                                return result;
                            }
                            catch (OverflowException)
                            {
                                BraidRuntimeException("During numeric multiplication, the '*' function overflowed all numeric types.");
                            }
                        }
                    }

                    return null;
                }
                else
                {
                    return null;
                }
            };

            /////////////////////////////////////////////////////////////////////
            FunctionTable[Symbol.sym_subtract] = (Vector args) =>
            {
                if (args.Count < 1 || args.Count > 2)
                {
                    BraidRuntimeException("The '-' function takes exactly 2 arguments");
                    return null;
                }

                if (args.Count == 1)
                {
                    return curryFunction(Symbol.sym_subtract, args[0]);
                }

                switch (args[0])
                {
                    case DateTime dt:
                        if (args.Count == 1)
                        {
                            BraidRuntimeException("Can't return a negative DateTime.");
                            return dt;
                        }

                        if (args[1] is DateTime dt2)
                        {
                            return dt - dt2;
                        }

                        if (args[1] is TimeSpan tspn)
                        {
                            return dt - tspn;
                        }

                        if (args[1] is int intval)
                        {
                            var ts = new TimeSpan(0, 0, intval);
                            return dt - ts;
                        }

                        BraidRuntimeException("You can only subtract a DateTime, TimeSpan or integer value from a DateTime value.");
                        return null;

                    case int ival1 when args.Count == 2 && args[1] is int ival2:
                        try
                        {
                            // checked operation will throw on overflow
                            return BoxInt(checked(ival1 - ival2));
                        }
                        catch
                        {
                            goto default;
                        }

                    case BigDecimal bd:
                        if (args[1] is BigDecimal bd2)
                        {
                            return bd - bd2;
                        }
                        switch (args[1])
                        {
                            case int ival:
                                return bd - (BigDecimal)ival;
                            case long lval:
                                return bd - (BigDecimal)lval;
                            case float fval:
                                return bd - (BigDecimal)fval;
                            case double dval:
                                return bd - (BigDecimal)dval;
                            case decimal dval:
                                return bd - (BigDecimal)dval;
                            default:
                                return bd - (BigDecimal)(args[1].ToString());
                        }

                    default:
                        dynamic first;
                        if (args[0] == null)
                        {
                            first = 0;
                        }
                        else
                        {
                            first = args[0];
                        }

                        dynamic second = args[1];
                        return first - second;
                }
            };

            /////////////////////////////////////////////////////////////////////
            FunctionTable[Symbol.sym_divide] = (Vector args) =>
            {
                if (args.Count == 1)
                {
                    return curryFunction(Symbol.sym_divide, args[0]);
                }

                if (args.Count != 2)
                {
                    BraidRuntimeException("The '/' function takes exactly 2 arguments");
                    return null;
                }

                if (args[0] is BigDecimal bd)
                {
                    if (args[1] is BigDecimal bd2)
                    {
                        return bd / bd2;
                    }

                    switch (args[1])
                    {
                        case int ival:
                            return bd / (BigDecimal)ival;
                        case long lval:
                            return bd / (BigDecimal)lval;
                        case float fval:
                            return bd / (BigDecimal)fval;
                        case double dval:
                            return bd / (BigDecimal)dval;
                        case Decimal dval:
                            return bd / (BigDecimal)dval;
                        default:
                            BraidRuntimeException("The '/' function takes exactly 2 arguments");
                            return null;
                    }
                }

                if (args[1] is BigDecimal rbd)
                {
                    switch (args[0])
                    {
                        case int ival:
                            return (BigDecimal)ival / rbd;
                        case long lval:
                            return (BigDecimal)lval / rbd;
                        case float fval:
                            return (BigDecimal)fval / rbd;
                        case double dval:
                            return (BigDecimal)dval / rbd;
                        case Decimal decval:
                            return (BigDecimal)decval / rbd;
                        default:
                            return (BigDecimal)(args[1].ToString()) / rbd;
                    }
                }

                dynamic first = args[0];
                dynamic second = args[1];

                return first / second;
            };

            /////////////////////////////////////////////////////////////////////
            FunctionTable[Symbol.sym_mod] = (Vector args) =>
            {
                if (args.Count == 1)
                {
                    return curryFunction(Symbol.sym_mod, args[0]);
                }

                if (args.Count != 2)
                {
                    BraidRuntimeException("The '%' operation takes exactly 2 arguments");
                }

                dynamic first = args[0];
                dynamic second = args[1];
                return first % second;
            };

            /////////////////////////////////////////////////////////////////////
            FunctionTable[Symbol.FromString("band")] = (Vector args) =>
            {
                if (args.Count < 1)
                {
                    BraidRuntimeException("band: requires at least two numeric arguments e.g. (band n1 n2 n3 n4 ...).");
                }

                if (args.Count == 1)
                {
                    return curryFunction(Symbol.FromString("band"), args[0]);
                }

                dynamic result = 0xffffffff;
                foreach (dynamic arg in args)
                {
                    dynamic value;
                    if (arg == null)
                    {
                        value = 0;
                    }
                    else if (arg.GetType().IsEnum)
                    {
                        value = (int)arg;
                    }
                    else
                    {
                        value = arg;
                    }

                    result = result & value;
                }

                return result;
            };

            /////////////////////////////////////////////////////////////////////
            FunctionTable[Symbol.FromString("bor")] = (Vector args) =>
            {
                if (args.Count < 1)
                {
                    BraidRuntimeException("bor: requires at least two numeric arguments e.g. (bor n1 n2 n3 ...).");
                }

                if (args.Count == 1)
                {
                    return curryFunction(Symbol.FromString("bor"), args[0]);
                }

                dynamic result = 0;
                foreach (dynamic arg in args)
                {
                    dynamic value;
                    if (arg == null)
                    {
                        value = 0;
                    }
                    else if (arg.GetType().IsEnum)
                    {
                        value = (int)arg;
                    }
                    else
                    {
                        value = arg;
                    }

                    result = result | value;
                }

                return result;
            };

            /////////////////////////////////////////////////////////////////////
            FunctionTable[Symbol.FromString("bnot")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException("bnot: requires one scalar numeric argument e.g. (bnot 0b0001).");
                }

                dynamic first = args[0];
                return ~first;
            };

            /////////////////////////////////////////////////////////////////////
            FunctionTable[Symbol.FromString("bxor")] = (Vector args) =>
            {
                if (args.Count < 1)
                {
                    BraidRuntimeException("bxor: requires two numeric arguments.");
                    return null;
                }

                if (args.Count == 1)
                {
                    return curryFunction(Symbol.FromString("bxor"), args[0]);
                }

                if (args[0] is uint uint1)
                {
                    return uint1 ^ ConvertToHelper<uint>(args[1]);
                }

                if (args[0] is int int1)
                {
                    return BoxInt(int1 ^ ConvertToHelper<int>(args[1]));
                }

                if (args[0] is ulong ulong1)
                {
                    return ulong1 ^ ConvertToHelper<ulong>(args[1]);
                }

                if (args[0] is long long1)
                {
                    return long1 ^ ConvertToHelper<long>(args[1]);
                }

                ulong first = ConvertToHelper<ulong>(args[0]);
                ulong second = ConvertToHelper<ulong>(args[1]);
                return first ^ second;
            };

            /////////////////////////////////////////////////////////////////////
            FunctionTable[Symbol.FromString("shiftr")] = (Vector args) =>
            {
                if (args.Count < 1)
                {
                    BraidRuntimeException("the 'shiftr' function requires two number arguments.");
                    return null;
                }

                if (args.Count == 1)
                {
                    return curryFunction(Symbol.FromString("shiftr"), args[0]);
                }

                dynamic first = args[0];
                dynamic second = args[1];
                return (int)((first >> second) & (0xffffffffu >> second));
            };

            /////////////////////////////////////////////////////////////////////
            FunctionTable[Symbol.FromString("shiftl")] = (Vector args) =>
            {
                if (args.Count < 2)
                {
                    BraidRuntimeException("the 'shiftl' function requires two number arguments.");
                    return null;
                }

                if (args.Count == 1)
                {
                    return curryFunction(Symbol.FromString("shiftl"), args[0]);
                }

                dynamic first = args[0];
                dynamic second = args[1];
                return first << second;
            };

            /////////////////////////////////////////////////////////////////////
            FunctionTable[Symbol.FromString("eq?")] =
            FunctionTable[Symbol.FromString("==")] = (Vector args) =>
            {
                if (args.Count == 1)
                {
                    return curryFunction(Symbol.FromString("=="), args[0]);
                }

                if (args.Count == 0 || args.Count % 2 != 0)
                {
                    BraidRuntimeException("==: takes exactly 2 arguments");
                    return null;
                }

                // Test each pair for equality
                for (int i = 0; i < args.Count - 1; i += 2)
                {
                    if (!Braid.CompareItems(args[i], args[i + 1]))
                    {
                        return BoxBool(false);
                    }
                }

                return BoxBool(true);
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Reference equals
            /// 
            FunctionTable[Symbol.FromString("===")] = (Vector args) =>
            {
                if (args.Count == 1)
                {
                    return curryFunction(Symbol.FromString("==="), args[0]);
                }

                if (args.Count == 0 || args.Count % 2 != 0)
                {
                    BraidRuntimeException("===: takes pairs of arguments to compare. (=== 1 1 2 2 ...)");
                    return null;
                }

                // Test each pair for equality
                for (int i = 0; i < args.Count - 1; i += 2)
                {
                    if (!object.ReferenceEquals(args[i], args[i + 1]))
                    {
                        return BoxBool(false);
                    }
                }

                return BoxBool(true);
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Reference not equals
            /// 
            FunctionTable[Symbol.FromString("!==")] = (Vector args) =>
            {
                if (args.Count == 1)
                {
                    return curryFunction(Symbol.FromString("!=="), args[0]);
                }

                if (args.Count == 0 || args.Count % 2 != 0)
                {
                    BraidRuntimeException("!==: takes exactly 2 arguments");
                    return null;
                }

                // Test each pair for equality
                for (int i = 0; i < args.Count - 1; i += 2)
                {
                    if (!object.ReferenceEquals(args[i], args[i + 1]))
                    {
                        return BoxBool(true);
                    }
                }

                return BoxBool(false);
            };

            /////////////////////////////////////////////////////////////////////
            FunctionTable[Symbol.FromString("!=")] = (Vector args) =>
            {
                if (args.Count == 1)
                {
                    return curryFunction(Symbol.FromString("!="), args[0]);
                }

                if (args.Count != 2)
                {
                    BraidRuntimeException("!=: takes exactly 2 arguments");
                    return null;
                }

                return BoxBool(!Braid.CompareItems(args[0], args[1]));
            };

            /////////////////////////////////////////////////////////////////////
            FunctionTable[Symbol.sym_lt] = (Vector args) =>
            {
                if (args.Count == 0)
                {
                    BraidRuntimeException("<: takes 2 or more arguments");
                    return null;
                }

                int numargs = args.Count;
                if (numargs == 1)
                {
                    return curryFunction(Symbol.sym_lt, args[0]);
                }

                // Return true if the arguments are monotonically increasing.
                dynamic lhs = args[0];
                for (int i = 1; i < numargs; i++)
                {
                    dynamic rhs = args[i];
                    try
                    {
                        if (lhs >= rhs)
                        {
                            return BoxBool(false);
                        }
                    }
                    catch (Microsoft.CSharp.RuntimeBinder.RuntimeBinderException)
                    {
                        if (LanguagePrimitives.Compare(lhs, rhs, true) >= 0)
                        {
                            return BoxBool(false);
                        }
                    }

                    lhs = rhs;
                }

                return BoxBool(true);
            };

            /////////////////////////////////////////////////////////////////////
            FunctionTable[Symbol.sym_le] = (Vector args) =>
            {
                if (args.Count == 0)
                {
                    BraidRuntimeException(">: takes 2 or more arguments");
                    return null;
                }

                int numargs = args.Count;
                if (numargs == 1)
                {
                    return curryFunction(Symbol.sym_le, args[0]);
                }

                dynamic lhs = args[0];
                for (int i = 1; i < numargs; i++)
                {
                    dynamic rhs = args[i];
                    try
                    {
                        if (lhs > rhs)
                        {
                            return BoxBool(false);
                        }
                    }
                    catch (Microsoft.CSharp.RuntimeBinder.RuntimeBinderException)
                    {
                        if (LanguagePrimitives.Compare(lhs, rhs, true) > 0)
                        {
                            return BoxBool(false);
                        }
                    }
                    lhs = rhs;
                }

                return BoxBool(true);
            };

            /////////////////////////////////////////////////////////////////////
            FunctionTable[Symbol.sym_ge] = (Vector args) =>
            {
                if (args.Count == 0)
                {
                    BraidRuntimeException(">=: takes 2 or more arguments");
                    return null;
                }

                int numargs = args.Count;
                if (numargs == 1)
                {
                    return curryFunction(Symbol.sym_ge, args[0]);
                }

                dynamic lhs = args[0];
                for (int i = 1; i < numargs; i++)
                {
                    dynamic rhs = args[i];
                    try
                    {
                        if (lhs < rhs)
                        {
                            return BoxBool(false);
                        }
                    }
                    catch (Microsoft.CSharp.RuntimeBinder.RuntimeBinderException)
                    {
                        if (LanguagePrimitives.Compare(lhs, rhs, true) < 0)
                        {
                            return BoxBool(false);
                        }
                    }

                    lhs = rhs;
                }

                return BoxBool(true);
            };

            /////////////////////////////////////////////////////////////////////
            FunctionTable[Symbol.sym_gt] = (Vector args) =>
            {
                if (args.Count == 0)
                {
                    BraidRuntimeException(">=: takes 2 or more arguments");
                    return null;
                }

                int numargs = args.Count;
                if (numargs == 1)
                {
                    return curryFunction(Symbol.sym_gt, args[0]);
                }

                dynamic lhs = args[0];
                for (int i = 1; i < numargs; i++)
                {
                    dynamic rhs = args[i];
                    try
                    {
                        if (lhs <= rhs)
                        {
                            return BoxBool(false);
                        }
                    }
                    catch (Microsoft.CSharp.RuntimeBinder.RuntimeBinderException)
                    {
                        if (LanguagePrimitives.Compare(lhs, rhs, true) < 0)
                        {
                            return BoxBool(false);
                        }
                    }

                    lhs = rhs;
                }

                return BoxBool(true);
            };

            /////////////////////////////////////////////////////////////////////
            //
            // A function that returns the largest of it's arguments
            //
            FunctionTable[Symbol.sym_bigger] = (Vector args) =>
            {
                if (args.Count == 0)
                {
                    BraidRuntimeException("bigger: takes 2 or more arguments e.g. (bigger 7 5).");
                    return null;
                }

                int numargs = args.Count;
                if (numargs == 1)
                {
                    return curryFunction(Symbol.sym_bigger, args[0]);
                }

                dynamic lhs = args[0];
                for (int i = 1; i < numargs; i++)
                {
                    dynamic rhs = args[i];
                    try
                    {
                        if (lhs <= rhs)
                        {
                            lhs = rhs;
                        }
                    }
                    catch (Microsoft.CSharp.RuntimeBinder.RuntimeBinderException)
                    {
                        if (LanguagePrimitives.Compare(lhs, rhs, true) < 0)
                        {
                            lhs = rhs;
                        }
                    }
                }

                return lhs;
            };

            /////////////////////////////////////////////////////////////////////
            //
            // A varargs function that returns the smallest of it's arguments
            //
            FunctionTable[Symbol.sym_smaller] = (Vector args) =>
            {
                if (args.Count == 0)
                {
                    BraidRuntimeException("smaller: takes 2 or more arguments e.g. (smaller 7 5).");
                    return null;
                }

                int numargs = args.Count;
                if (numargs == 1)
                {
                    return curryFunction(Symbol.sym_smaller, args[0]);
                }

                dynamic lhs = args[0];
                for (int i = 1; i < numargs; i++)
                {
                    dynamic rhs = args[i];
                    try
                    {
                        if (lhs > rhs)
                        {
                            lhs = rhs;
                        }
                    }
                    catch (Microsoft.CSharp.RuntimeBinder.RuntimeBinderException)
                    {
                        if (LanguagePrimitives.Compare(lhs, rhs, true) > 0)
                        {
                            lhs = rhs;
                        }
                    }
                }

                return lhs;
            };

            /////////////////////////////////////////////////////////////////////
            FunctionTable[Symbol.FromString("not")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException("not: requires exactly one argument");
                }

                return BoxBool(!Braid.IsTrue(args[0]));
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// and the values of two or more expressions together, with
            /// short-circuit evaluation.
            /// 
            SpecialForms[Symbol.FromString("and")] = (Vector args) =>
            {
                if (args.Count == 1)
                {
                    return curryFunction(Symbol.FromString("and"), args[0]);
                }

                object last = null;
                foreach (var item in args)
                {
                    last = Braid.Eval(item);
                    if (!Braid.IsTrue(last))
                    {
                        return BoxedFalse;
                    }
                }
                return last;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// or the values of two or more expressions together, with
            /// short-circuit evaluation.
            /// 
            SpecialForms[Symbol.FromString("or")] = (Vector args) =>
            {
                if (args.Count == 1)
                {
                    return curryFunction(Symbol.FromString("or"), args[0]);
                }

                foreach (var item in args)
                {
                    object result = Braid.Eval(item);
                    if (Braid.IsTrue(result))
                    {
                        return result;
                    }
                }

                return BoxedFalse;
            };

            /////////////////////////////////////////////////////////////////////
            FunctionTable[Symbol.FromString("xor")] = (Vector args) =>
            {
                if (args.Count < 1 || args.Count > 2)
                {
                    BraidRuntimeException("xor: requires exactly two arguments.");
                    return BoxedFalse;
                }

                if (args.Count == 1)
                {
                    return curryFunction(Symbol.FromString("xor"), args[0]);
                }

                bool first = ConvertToHelper<bool>(args[0]);
                bool second = ConvertToHelper<bool>(args[1]);
                return Braid.BoxBool(first ^ second);
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Return the length of an object. It always succeeds. Null is length 0
            /// and a scalar value is length 1.
            /// 
            FunctionTable[Symbol.FromString("count")] =
            FunctionTable[Symbol.FromString("length")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException("length: takes exactly 1 argument");
                    return null;
                }

                switch (args[0])
                {
                    case null:
                        return 0;

                    case ISeq seq:
                        return seq.Count;

                    case VectorLiteral vlit:
                        return vlit.ValueList.Count;

                    case Array arr:
                        return arr.Length;

                    case ICollection lst:
                        return lst.Count;

                    case string str:
                        return str.Length;

                    case Symbol sym:
                        return sym.Value.Length;

                    case IEnumerable<object> ieo:
                        return ieo.Count();

                    case IEnumerable ie:
                        int count = 0;
                        foreach (var e in ie) { count++; }
                        return count;

                    // Assume scalar so return 1 by default
                    default:
                        return 1;
                }
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Compare two objects returning 0 if equal, 1 if greater and -1 if less.
            /// This function just calls the PowerShell Compare function wit case-insensitive
            /// string comparison.
            /// 
            FunctionTable[Symbol.FromString("compare")] = (Vector args) =>
            {
                if (args.Count == 1)
                {
                    return curryFunction(Symbol.FromString("compare"), args[0]);
                }

                if (args.Count != 2)
                {
                    BraidRuntimeException("The 'compare' function requires exactly two arguments.");
                }

                return LanguagePrimitives.Compare(args[0], args[1], true);
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Indexing operations; uses '!!' like Haskell. Can index into strings, lists and vectors
            /// doing both sets and gets.
            /// 
            FunctionTable[Symbol.FromString("!!")] = (Vector args) =>
            {
                if (args.Count == 1)
                {
                    return curryFunction(Symbol.FromString("!!"), args[0]);
                }

                if (args.Count < 2 || args.Count > 3)
                {
                    BraidRuntimeException(
                        $"!!: takes two or three non-null arguments: (!! <indexable> <index> [<valToSet>]). not {args}");
                }

                var v0 = args[0];
                if (v0 == null)
                {
                    // If the collection arg is null, create a new dictionary (matches Clojure).
                    v0 = new Dictionary<object, object>(new ObjectComparer());
                }

                var v1 = args[1];
                if (v1 == null)
                {
                    BraidRuntimeException($"!!: the index/key for this operation cannot be null.");
                    return null;
                }

                int index = 0;
                object v3;
                switch (v0)
                {
                    case IList indexable:
                        try
                        {
                            index = ConvertToHelper<int>(v1);

                            if (index < 0)
                            {
                                // negative values index from the end
                                index = indexable.Count + index;
                            }
                        }
                        catch (Exception e)
                        {
                            BraidRuntimeException($"!!: index/key '{v1}' for the '{v0.GetType()}' collection was invalid: {e.Message}");
                        }

                        if (args.Count == 3)
                        {
                            v3 = args[2];
                            indexable[index] = v3;
                            return indexable;
                        }

                        return indexable[index];

                    case IDictionary idict:
                        if (args.Count == 3)
                        {
                            v3 = args[2];
                            idict[v1] = v3;
                            return idict;
                        }

                        return idict[v1];

                    case HashSet<object> hashset:
                        // do set: 
                        //          (!! #{:a :b} :c true) ; ensure index is in the hashmap
                        //          (!! #{:a :b} :b false) ; ensure index is not present, remove if necessary
                        if (args.Count == 3)
                        {
                            v3 = ConvertToHelper<bool>(args[2]);
                            if ((bool)v3)
                            {
                                if (!hashset.Contains(v1))
                                {
                                    hashset.Add(v1);
                                }
                            }
                            else
                            {
                                if (hashset.Contains(v1))
                                {
                                    hashset.Remove(v1);
                                }
                            }

                            return hashset;
                        }

                        // Do get
                        object key = null;
                        if (hashset.TryGetValue(v1, out key))
                        {
                            return key;
                        }
                        else
                        {
                            return null;
                        }

                    case string str:
                        try
                        {
                            index = ConvertToHelper<int>(v1);

                            if (index < 0)
                            {
                                index = str.Length + index;
                            }
                        }
                        catch (Exception e)
                        {
                            BraidRuntimeException($"!!: index/key '{v1}' for the '{v0.GetType()}' argument was invalid: {e.Message}", e);
                        }

                        if (args.Count == 3)
                        {
                            BraidRuntimeException("!!: Strings are immutable and cannot be assigned to.", null);
                        }

                        return str[index];

                    case IEnumerable enumerable:

                        try
                        {
                            index = ConvertToHelper<int>(v1);
                        }
                        catch (Exception e)
                        {
                            BraidRuntimeException($"!!: index/key '{v1}' for the '{v0.GetType()}' argument was invalid: {e.Message}", e);
                        }

                        // For IEnumerables, walk the list until we reach the right index. This is not fast.
                        object result = null;
                        int start = 0;
                        bool found = false;
                        foreach (object obj in enumerable)
                        {
                            result = obj;
                            if (start++ >= index) {
                                found = true;
                                break;
                            }
                        }

                        if (!found)
                        {
                            int count = 0;
                            foreach (var e in enumerable) count++;
                            BraidRuntimeException($"!!: The specified index ({index}) was out of range. It must be non-negative " +
                                                $"and less than the size of the collection ({count}).");
                        }

                        return result;

                    default:
                        BraidRuntimeException($"the first argument to '!!' must be an indexable/enumerable collection; not {v0.GetType()}");
                        return null;
                }
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Returns the edit distance between two strings.
            ///
            FunctionTable[Symbol.FromString("edit-distance")] = (Vector args) =>
            {
                if (args.Count != 2 || args[0] == null || args[1] == null)
                {
                    BraidRuntimeException("The 'edit-distance' function requires two non-null string arguments.");
                }

                string s = args[0].ToString();
                string t = args[1].ToString();

                return Utils.EditDistance(s, t);
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Append arguments and return a list
            /// 
            FunctionTable[Symbol.FromString("append")] = (Vector args) =>
            {
                s_Expr result = null;
                s_Expr end = null;

                foreach (object arg in args)
                {
                    switch (arg)
                    {
                        case null:
                            // Don't include nulls in the result list
                            break;

                        case string str:
                            if (result == null)
                            {
                                result = end = new s_Expr(str);
                            }
                            else
                            {
                                end = end.Add(str);
                            }
                            break;

                        case IDictionary dict:
                            if (result == null)
                            {
                                result = end = new s_Expr(dict);
                            }
                            else
                            {
                                end = end.Add(dict);
                            }
                            break;

                        case IEnumerable ienum:
                            // IEnumerables get copied into the list...
                            foreach (var e in ienum)
                            {
                                if (result == null)
                                {
                                    result = end = new s_Expr(e);
                                }
                                else
                                {
                                    end = end.Add(e);
                                }
                            }
                            break;

                        default:
                            // Otherwise, just append the argument as a scalar.
                            if (result == null)
                            {
                                result = end = new s_Expr(arg);
                            }
                            else
                            {
                                end = end.Add(arg);
                            }
                            break;
                    }
                }

                return result;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Append together the arguments into a vector instead of a list.
            ///
            FunctionTable[Symbol.FromString("concat")] = (Vector args) =>
            {
                Vector result = new Vector(args.Count);
                foreach (object arg in args)
                {
                    switch (arg)
                    {
                        case null:
                            // Don't include nulls in the result list
                            break;
                        case string s:
                            result.Add(s);
                            break;
                        case IDictionary d:
                            result.Add(d);
                            break;
                        case IEnumerable<object> c:
                            result.AddRange(c);
                            break;
                        case IEnumerable ienum:
                            foreach (var item in ienum)
                            {
                                result.Add(item);
                            }
                            break;
                        default:
                            result.Add(arg);
                            break;
                    }
                }
                return result;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Append together the arguments into a vector instead of a list.
            ///
            FunctionTable[Symbol.FromString("add")] = (Vector args) =>
            {
                if (args.Count != 2)
                {
                    BraidRuntimeException($"add: requires two arguments: a vector (^IList) and a value to add to that vector, not {args}");
                }

                IList input = args[0] as IList;
                if (input == null)
                {
                    BraidRuntimeException($"add: the vector argument to this function must be a non-null vector, not {args}");
                }

                input.Add(args[1]);

                return input;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Get the first element from a list or vector.
            ///
            FunctionTable[Symbol.FromString("head")] =
            FunctionTable[Symbol.FromString("car")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException($"car: requires exactly takes one argument, not {args}");
                }

                switch (args[0])
                {
                    case ISeq expr:
                        return expr.Car;

                    case IList ilist:
                        if (ilist.Count > 0)
                        {
                            return ilist[0];
                        }
                        else
                        {
                            return null;
                        }

                    case string str:
                        // Return the car of the string - text up to the first space
                        var spcpos = str.IndexOf(' ');
                        if (spcpos == -1)
                            return str;
                        else
                            return str.Substring(0, spcpos);

                    case IEnumerable ienum:
                        var ie = ienum.GetEnumerator();
                        if (ie.MoveNext())
                            return ie.Current;
                        else
                            return null;

                    default:
                        return args[0];
                }
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Function to get the remaining elements in a ISeq, turning that collection
            /// into a s_Expr for performance with subsequent calls to cdr.
            /// The cdr function has 2 aliases rest and tail. 
            /// 
            FunctionTable[Symbol.FromString("rest")] =
            FunctionTable[Symbol.FromString("tail")] =
            FunctionTable[Symbol.FromString("cdr")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException("cdr: requires exactly one argument");
                }

                switch (args[0])
                {
                    case ISeq seq:
                        // Handle vectors and lists.
                        return seq.Cdr;

                    case string str:
                        // Return the "cdr" of the string where elements of the string are separated
                        // by spaces. This function converts the string into a list.
                        string[] strlist = Regex.Split(str, @"\s+", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
                        if (strlist.Length == 0)
                            return null;
                        return s_Expr.FromEnumerable(strlist).Cdr;

                    case IList ilist:
                        return new Slice(ilist, 1);

                    case IEnumerable enumerable:
                        return new Slice(enumerable, 1);

                    default:
                        // Default behaviour is that the object is an atom/scalar so it's cdr is null.
                        return null;
                }
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Add an item to the beginning of a list, returning a list
            ///
            FunctionTable[Symbol.FromString(":")] =
            FunctionTable[Symbol.FromString("cons")] = (Vector args) =>
            {
                if (args.Count != 2)
                {
                    BraidRuntimeException("cons: takes exactly 2 arguments.");
                }

                // (cons 1 2)
                return new s_Expr(args[0], args[1]);
            };

            /////////////////////////////////////////////////////////////////////
            ///
            FunctionTable[Symbol.FromString("nconc")] = (Vector args) =>
            {
                if (args.Count != 2)
                {
                    BraidRuntimeException("nconc: takes exactly 2 arguments: (nconc item vector)");
                }

                switch (args[1])
                {
                    case null:
                        return new Vector { args[0] };

                    case Vector vec:
                        vec.Add(args[0]);
                        return vec;

                    default:
                        // (nconc 1 2)
                        BraidRuntimeException("The second argument to 'nconc' must be a vector: (nconc item vector)");
                        return null;
                }
            };

            /////////////////////////////////////////////////////////////////////
            ///
            FunctionTable[Symbol.FromString(">:")] =
            FunctionTable[Symbol.FromString(">cons")] = (Vector args) =>
            {
                if (args.Count != 2)
                {
                    BraidRuntimeException(">cons: takes exactly 2 arguments: (>cons '(1 2 3) 4)");
                }

                switch (args[0])
                {
                    case null:
                        // (cons arg1 null)
                        return new s_Expr(args[1]);

                    case ISeq seq:
                        // (cons arg1 '(2 3 4))
                        return seq.Cons(args[1]);

                    case string str:
                        if (args[1] != null)
                            return args[1].ToString() + str;
                        return str;

                    case IEnumerable ienum:
                        // (cons arg1 [2 3 4]
                        return s_Expr.FromEnumerable(ienum).Cons(args[1]);

                    default:
                        // (cons 1 2)
                        return new s_Expr(args[1], args[0]);
                }
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Cons an item onto the beginning of a vector returning
            /// the mutated vector unlike cons which returns a new list.
            ///
            FunctionTable[Symbol.FromString("vcons")] = (Vector args) =>
            {
                if (args.Count != 2)
                {
                    BraidRuntimeException("vcons: takes exactly 2 arguments: (vcons <value> <vector>).");
                }

                switch (args[1])
                {
                    case null:
                        return new Vector { args[0] };

                    case Vector vect:
                        vect.Insert(0, args[0]);
                        return vect;

                    default:
                        BraidRuntimeException("The second argument to 'vcons' must be a vector (vcons <value> <vector>).");
                        return null;
                }
            };

            /////////////////////////////////////////////////////////////////////
            FunctionTable[Symbol.FromString("aslist")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException("aslist: takes exactly 1 argument.");
                }

                switch (args[0])
                {
                    case null:
                        return null;

                    case s_Expr expr:
                        return expr;

                    case string strexpr:
                        return new s_Expr(strexpr);

                    case IEnumerable enumerable:
                        return s_Expr.FromEnumerable(enumerable);

                    default:
                        return new s_Expr(args[0]);
                }
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Function to turn a collection into a .NET object[] array.
            /// 
            FunctionTable[Symbol.FromString("asarray")] = (Vector args) =>
            {
                if (args.Count < 1 || args.Count > 2)
                {
                    BraidRuntimeException("asarray: takes 1 or 2 argument: (asarray <collection> [<type>])");
                }

                Type targetType = typeof(object);
                if (args.Count == 2)
                {
                    targetType = args[1] as Type;
                    if (targetType == null)
                    {
                        BraidRuntimeException("The second argument to 'asarray' must be a type, not '{args[1]}'");
                    }
                }

                object objToConvert = args[0];

                if (objToConvert == null)
                {
                    return Array.CreateInstance(targetType, 0);
                }

                if (objToConvert is PSObject pso && !(pso.BaseObject is PSCustomObject))
                {
                    objToConvert = pso.BaseObject;
                }

                if (objToConvert is object[] && targetType == typeof(object))
                {
                    return objToConvert;
                }

                if (objToConvert is string sobj)
                {
                    return new string[1] { sobj };
                };

                Array result;

                if (objToConvert is IEnumerable enumexpr)
                {
                    int size = 0;
                    // BUGBUGBUG FIX THIS
                    foreach (var val in enumexpr)
                    {
                        size++;
                    }

                    result = Array.CreateInstance(targetType, size);
                    int index = 0;
                    foreach (dynamic val in enumexpr)
                    {
                        result.SetValue(Braid.ConvertTo(val, targetType), index);
                        index++;
                    }

                    return result;
                }

                result = Array.CreateInstance(targetType, 1);
                result.SetValue(Braid.ConvertTo(args[0], targetType), 0);
                return result;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Function to create an array where the element type is based on the first
            /// non-null element encountered.
            /// 
            FunctionTable[Symbol.FromString("array")] = (Vector args) =>
            {
                if (args.Count < 1)
                {
                    return new object[0];

                }

                // Default the type tp be object
                Type targetType = typeof(object);

                // but use the type of the first non-null element as the array type.
                foreach (var el in args)
                {
                    object obj = null;
                    if (el is PSObject tpso)
                    {
                        obj = tpso.BaseObject;
                    }
                    if (obj != null)
                    {
                        targetType = obj.GetType();
                        break;
                    }
                }

                var result = Array.CreateInstance(targetType, args.Count);

                for (int i = 0; i < args.Count; i++)
                {
                    result.SetValue(Braid.ConvertTo(args[i], targetType), i);
                }

                return result;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Function to create an array where the element type is passed as
            /// the first argument.
            /// 
            FunctionTable[Symbol.FromString("array-of")] = (Vector args) =>
            {
                if (args.Count < 1)
                {
                    BraidRuntimeException("array-of: requires a type parameter: (array-of <type> <values...>).");
                }

                if (!(args[0] is Type))
                {
                    BraidRuntimeException("array-of: the first argument must specify a valid type: (array-of <type> <values...>).");
                }

                // Get the type of the array to create
                Type targetType = args[0] as Type;

                var resultArray = Array.CreateInstance(targetType, args.Count-1);

                int i = 0;
                foreach (object arg in args.Skip(1))
                {
                    resultArray.SetValue(Braid.ConvertTo(arg, targetType), i++);
                }

                return resultArray;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Read lines from a file optionally filtering with a regex then applying a lambda to the line.
            /// 
            FunctionTable[Symbol.FromString("read-file")] =
            FunctionTable[Symbol.FromString("file/read-lines")] =
            FunctionTable[Symbol.FromString("read-lines")] = (Vector args) =>
            {

                if (args.Count < 1 || args[0] == null)
                {
                    BraidRuntimeException(
                        "file/read-lines: requires at least one argument: (file/read-lines [-not] [-annotate] <fileName> [<pattern> [<lambda>]]).");
                }

                bool not = false;
                bool annotate = false;
                var callStack = Braid.CallStack;
                var namedParameters = callStack.NamedParameters;
                if (namedParameters != null)
                {
                    foreach (var key in namedParameters.Keys)
                    {
                        if (key.Equals("not", StringComparison.OrdinalIgnoreCase))
                        {
                            not = Braid.IsTrue(namedParameters["not"]);
                        }
                        else if (key.Equals("annotate", StringComparison.OrdinalIgnoreCase))
                        {
                            annotate = Braid.IsTrue(namedParameters["annotate"]);
                        }
                        else
                        {
                            BraidRuntimeException($"Named parameter '-{key}' is not valid for the 'file/read-lines' function, " +
                                                "the only named parameters for 'file/read-lines' are '-not' and '-annotate");
                        }
                    }
                }

                Vector filesToRead = new Vector();
                if (args[0] is string str)
                {
                    filesToRead.Add(str);
                }
                else if (args[0] is IEnumerable ienum)
                {
                    foreach (object e in ienum)
                    {
                        filesToRead.Add(e);
                    }
                }
                else
                {
                    filesToRead.Add(args[0]);
                }

                Regex pattern = null;
                if (args.Count > 1)
                {
                    // If it's already a regex, use as-is otherwise turn it into a string and make a regex out of it.
                    if (args[1] is Regex re)
                    {
                        pattern = re;
                    }
                    else
                    {
                        pattern = new Regex(args[1].ToString(), RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
                    }
                }

                Callable callable = null;
                if (args.Count > 2)
                {
                    callable = args[2] as Callable;
                    if (callable == null)
                    {
                        BraidRuntimeException("The third argument to 'file/read-lines' should be a callable function.");
                    }
                }

                int nargs = 2;
                if (callable is UserFunction lam)
                {
                    nargs = lam.Arguments.Count;
                }

                Vector result = new Vector();
                foreach (var element in filesToRead)
                {

                    // Skip nulls
                    if (element == null)
                    {
                        continue;
                    }

                    var uelement = (element is PSObject pso) ? pso.BaseObject : element;

                    // Skip directories
                    if (element is System.IO.DirectoryInfo)
                    {
                        continue;
                    }

                    string fileToRead;
                    if (uelement is System.IO.FileInfo f)
                    {
                        fileToRead = f.FullName;
                    }
                    else
                    {
                        // Use PowerShell to resolve the path.
                        fileToRead = ResolvePath(uelement.ToString());
                    }

                    using (var file = File.OpenText(fileToRead))
                    {
                        string line;
                        Match match = null;
                        Vector argvec = new Vector(nargs);
                        for (int i = 0; i < nargs; i++)
                        {
                            argvec.Add(null);
                        }

                        int linenumber = 0;
                        while ((line = file.ReadLine()) != null)
                        {
                            linenumber++;
                            if (pattern != null && (match = pattern.Match(line)).Success == not)
                            {
                                continue;
                            }

                            if (_stop)
                            {
                                return null;
                            }

                            object valToReturn = null;
                            if (callable != null)
                            {
                                // first arg is the current line of text
                                if (nargs > 0)
                                    argvec[0] = line;

                                // second arg is the array of matches
                                if (nargs > 1)
                                {
                                    var matchArray = new List<string>();
                                    if (match != null)
                                    {
                                        for (var index = 0; index < match.Groups.Count; index++)
                                        {
                                            matchArray.Add(match.Groups[index].Value);
                                        }
                                    }
                                    argvec[1] = matchArray;
                                }

                                // 3rd arg is the current line number
                                if (nargs > 2)
                                    argvec[2] = linenumber;

                                // 4th args is the name of the file being processed
                                if (nargs > 3)
                                    argvec[3] = fileToRead;

                                valToReturn = callable.Invoke(argvec);
                            }
                            else
                            {
                                valToReturn = line;
                            }

                            if (valToReturn != null)
                            {
                                if (annotate)
                                {
                                    result.Add($"{fileToRead}:{linenumber}:{valToReturn}");
                                }
                                else
                                {
                                    result.Add(valToReturn);
                                }
                            }
                        }
                    }
                }

                return result;
            };

            /////////////////////////////////////////////////////////////////////
            SpecialForms[Symbol.FromString("trace")] = (Vector args) =>
            {
                var namedParams = CallStack.NamedParameters;
                if (namedParams != null)
                {
                    if (namedParams.ContainsKey("exceptions"))
                    {
                        if (Braid.IsTrue(namedParams["exceptions"]))
                        {
                            Braid.Debugger |= DebugFlags.TraceException;
                        }
                        else
                        {
                            Braid.Debugger &= ~DebugFlags.TraceException;
                        }
                    }
                    else
                    {
                        string vals = string.Join(", -", namedParams.Keys);
                        BraidRuntimeException($"the only valid named parameter for 'trace' is '-exceptions' not: -{vals}.");
                    }
                }

                if (args.Count == 0)
                {
                    // With no args, just invert the trace flag
                    Braid.Debugger &= ~DebugFlags.Trace;
                }
                else if (args[0] is s_Expr listToEval)
                {
                    // If it's a list, evaluate it with tracing turned on.
                    try
                    {
                        Braid.Debugger |= DebugFlags.Trace;
                        return Eval(listToEval);
                    }
                    finally
                    {
                        Debugger &= ~DebugFlags.Trace;
                    }
                }
                else
                {
                    if (Braid.IsTrue(Braid.Eval(args[0])))
                    {
                        Braid.Debugger |= DebugFlags.Trace;
                    }
                    else
                    {
                        Braid.Debugger &= ~DebugFlags.Trace;
                    }
                }

                if ((Braid.Debugger & DebugFlags.Trace) != 0)
                {
                    Braid.Debugger &= ~DebugFlags.TraceException;
                }

                return Debugger;
            };

            /////////////////////////////////////////////////////////////////////
            /// Implements a breakpoint
            FunctionTable[Symbol.FromString("debug/breakPoint")] = (Vector args) =>
            {
                if (_stop)
                {
                    return null;
                }

                var oldDebugger = Debugger;
                Debugger &= ~DebugFlags.Trace;
                // Enter the debugger / REPL 
                try
                {

                    if (CallStack.Caller != null)
                    {
                        var caller = CallStack.Caller;
                        var srcLine = GetSourceLine(caller.Text, caller.Offset);
                        WriteConsoleColor(ConsoleColor.Green, $"*break* at {caller.File}:{caller.LineNo} >>> {srcLine}");
                    }

                    WriteConsoleColor(ConsoleColor.Green,
                        $"DEBUG: Stack Depth: {CallStack.Depth()} (Cmds: 'show-callstack' (scs) and 'get-dynamic' (gdv))");
                    StartBraid();
                }
                finally
                {
                    Debugger = oldDebugger;
                }

                return null;
            };

            /////////////////////////////////////////////////////////////////////
            FunctionTable[Symbol.FromString("distinct")] = (Vector args) =>
            {
                if (args.Count < 1 || args.Count > 2)
                {
                    BraidRuntimeException(
                        "distinct: requires one argument which must be a collection and an optional function argument used to compare elements", null);
                }

                object list = args[0];
                if (list == null)
                {
                    return null;
                }

                IEnumerable<object> enumerable = GetEnumerableFrom(list);

                if (args.Count == 2)
                {
                    var func = args[1] as IInvokeableValue;
                    if (func == null)
                    {
                        BraidRuntimeException("The second argument to 'distinct' must be a function taking two arguments.");
                    }

                    return new Vector(enumerable.Distinct(new ObjectComparer(func)));
                }

                return new Vector(enumerable.Distinct(new ObjectComparer()));
            };

            /////////////////////////////////////////////////////////////////////
            //
            // Sort a list or enumerable; returning a sorted list. An optional property
            // name or lambda can be specified to specify the value to sort on,
            //
            FunctionTable[Symbol.FromString("sort")] = (Vector args) =>
            {
                if (args.Count < 1)
                {
                    BraidRuntimeException("The 'sort' function requires at least one non-null argument which must be the collection to sort.");
                }

                if (args[0] == null)
                {
                    return null;
                }

                object list = args[0];
                IEnumerable<object> enumerable = GetEnumerableFrom(list);

                if (enumerable == null)
                {
                    return list;
                }

                object lambda = null;

                if (args.Count > 1)
                {
                    lambda = args[1];
                }

                var callStack = CallStack;
                var namedParameters = callStack.NamedParameters;
                bool descending = false;
                if (namedParameters != null && namedParameters.TryGetValue("Descending", out NamedParameter keyValue))
                {
                    descending = LanguagePrimitives.IsTrue(keyValue.Value);
                }

                if (lambda != null)
                {
                    var func = GetFunc(callStack, lambda) as IInvokeableValue;
                    if (func == null)
                    {
                        BraidRuntimeException(
                            $"sort: the second argument to 'sort' must resolve to a function; not '{args[1]}'");
                    }

                    Vector data = new Vector { null };

                    if (descending)
                    {
                        return enumerable.OrderByDescending((val) =>
                        {
                            data[0] = val;
                            return func.Invoke(data);
                        }, new PSComparer());
                    }
                    else
                    {
                        return enumerable.OrderBy((val) =>
                        {
                            data[0] = val;
                            return func.Invoke(data);
                        }, new PSComparer());
                    }
                }

                if (descending)
                {
                    return enumerable.OrderByDescending((n) => n, new PSComparer());
                }
                else
                {
                    return enumerable.OrderBy((n) => n, new PSComparer());
                }
            };

            /////////////////////////////////////////////////////////////////////
            //
            // Sort a list or enumerable; returning a sorted list. An optional property
            // name or lambda can be specified to specify the value to sort on,
            //
            FunctionTable[Symbol.FromString("thenSort")] = (Vector args) =>
            {
                if (args.Count < 1)
                {
                    BraidRuntimeException("The 'thenSort' function requires at least one non-null argument " +
                        "which must be the output of the 'sort' function (^System.Linq.IOrderedEnumerable[object]).");
                }

                if (args[0] == null)
                {
                    return null;
                }

                var enumerable = args[0] as System.Linq.IOrderedEnumerable<object>;
                if (enumerable == null)
                {
                    BraidRuntimeException("The first argument to the 'thenSort' function must be the output of the " +
                        $"'sort' function (^System.Linq.IOrderedEnumerable[object]) not ^{args[0].GetType()}.");
                }

                object lambda = null;

                if (args.Count > 1)
                {
                    lambda = args[1];
                }

                var callStack = CallStack;
                var namedParameters = callStack.NamedParameters;
                bool descending = false;
                if (namedParameters != null && namedParameters.TryGetValue("Descending", out NamedParameter keyValue))
                {
                    descending = LanguagePrimitives.IsTrue(keyValue.Value);
                }

                if (lambda != null)
                {
                    var func = GetFunc(callStack, lambda) as IInvokeableValue;
                    if (func == null)
                    {
                        BraidRuntimeException(
                            $"thenSort: the second argument to 'thenSort' must resolve to a function; not '{args[1]}'");
                    }

                    Vector data = new Vector { null };

                    if (descending)
                    {
                        return enumerable.ThenByDescending((val) =>
                        {
                            data[0] = val;
                            return func.Invoke(data);
                        }, new PSComparer());
                    }
                    else
                    {
                        return enumerable.ThenBy((val) =>
                        {
                            data[0] = val;
                            return func.Invoke(data);
                        }, new PSComparer());
                    }
                }

                if (descending)
                {
                    return enumerable.ThenBy((n) => n, new PSComparer());
                }
                else
                {
                    return enumerable.ThenByDescending((n) => n, new PSComparer());
                }
            };

            /////////////////////////////////////////////////////////////////////
            //
            // Lazy Sort a list or enumerable; returning a sorted list. An optional property
            // name or lambda can be specified to specify the value to sort on,
            //
            FunctionTable[Symbol.FromString("lazy-sort")] = (Vector args) =>
            {
                if (args.Count < 1 || args[0] == null)
                {
                    BraidRuntimeException("The 'sort' function requires at least one non-null argument which must be the collection to sort.");
                }

                object list = args[0];
                IEnumerable<object> enumerable;

                if (list is IEnumerable ienum)
                {
                    enumerable = ienum.Cast<object>();
                }
                else
                {
                    enumerable = GetEnumerableFrom(list);
                }

                if (enumerable == null)
                {
                    return list;
                }

                object lambda = null;

                if (args.Count > 1)
                {
                    lambda = args[1];
                }

                var callStack = CallStack;
                var namedParameters = callStack.NamedParameters;
                bool descending = false;
                NamedParameter keyValue = null;
                if (namedParameters != null && namedParameters.TryGetValue("Descending", out keyValue))
                {
                    descending = LanguagePrimitives.IsTrue(keyValue.Value);
                }

                if (lambda != null)
                {
                    object func;

                    FunctionType ftype;
                    string funcname;
                    func = GetFunc(callStack, lambda, out ftype, out funcname);

                    if (func == null)
                    {
                        BraidRuntimeException(
                            $"sort: the second argument to 'sort' must resolve to a function; not '{args[1]}'");
                    }

                    s_Expr data;
                    var exprToCall = new s_Expr(func, data = new s_Expr(null));

                    if (func != null)
                    {
                        if (descending)
                        {
                            return enumerable.OrderByDescending((val) =>
                            {
                                data.Car = val;
                                return Braid.Eval(exprToCall, true, true);
                            }, new PSComparer());
                        }
                        else
                        {
                            return enumerable.OrderBy((val) =>
                            {
                                data.Car = val;
                                return Braid.Eval(exprToCall, true, true);
                            }, new PSComparer());
                        }
                    }
                    else
                    {
                        if (descending)
                        {
                            // Sort by property name
                            string propertyName = lambda.ToString();
                            return enumerable.OrderByDescending((val) =>
                            {
                                PSObject pso = PSObject.AsPSObject(val);
                                return pso.Members[propertyName].Value;
                            }, new PSComparer());
                        }
                        else
                        {
                            // Sort by property name
                            string propertyName = lambda.ToString();
                            return enumerable.OrderBy((val) =>
                            {
                                PSObject pso = PSObject.AsPSObject(val);
                                return pso.Members[propertyName].Value;
                            }, new PSComparer());
                        }
                    }
                }

                if (descending)
                {
                    return enumerable.OrderByDescending((n) => n, new PSComparer());
                }
                else
                {
                    return enumerable.OrderBy((n) => n, new PSComparer());
                }
            };

            /////////////////////////////////////////////////////////////////////
            //
            // Group a list or enumerable by the specified property name or the result of a lambda.
            // The result is a Dictionary<object,object> where the key is the element grouped by
            // and the value is the set of group members. An option second lambda can be provided that
            // will process the group values before adding it to the hashtable.
            // Example:
            //      (random 100 1 10 | group (fn n -> n)) ; group a random set of numbers
            //      (random 100 1 10 | group (fn n -> n) (fn g -> (count g))
            //
            FunctionTable[Symbol.FromString("group")] = (Vector args) =>
            {
                if (args.Count < 1 || args[0] == null)
                {
                    BraidRuntimeException(
                        "group: requires one non-null arguments which must be a collection of values.");
                }

                var callStack = Braid.CallStack;
                if (callStack.NamedParameters != null)
                {
                    BraidRuntimeException("the 'group' function doesn't define any named parameters.");
                }

                object list = args[0];
                IEnumerable<object> enumerable = GetEnumerableFrom(list);

                if (enumerable == null)
                {
                    BraidRuntimeException($"group: the first argument must be an enumerable collection, not {args[0].GetType()}");
                }

                // default the function to echo
                object funcArg = args.Count > 1 ? args[1] : "echo";


                IInvokeableValue func;
                FunctionType ftype;
                string funcname;

                // Lambda used to compute the value to group by
                func = GetFunc(callStack, funcArg, out ftype, out funcname) as IInvokeableValue;
                if (func == null)
                {
                    BraidRuntimeException($"group: the second argument must be function, not {args[0].GetType()}");
                }

                // An optional second function for manipulating the values in each group 
                IInvokeableValue nfunc = null;
                if (args.Count == 3)
                {
                    nfunc = GetFunc(callStack, args[2], out ftype, out funcname) as IInvokeableValue;
                    if (nfunc == null)
                    {
                        BraidRuntimeException($"group: when present, the third argument must be function, not {args[0].GetType()}");
                    }
                }

                Dictionary<object, object> gresult = new Dictionary<object, object>(new ObjectComparer());
                var data = new Vector { null };
                var g_enum = enumerable.GroupBy(val =>
                {
                    data[0] = val;
                    return func.Invoke(data);
                }, new ObjectComparer());

                foreach (var g in g_enum)
                {
                    if (nfunc != null)
                    {
                        data[0] = new Vector(g);
                        gresult[g.Key] = nfunc.Invoke(data);
                    }
                    else
                    {
                        gresult[g.Key] = new Vector(g);
                    }
                }
                return gresult;
            };

            /////////////////////////////////////////////////////////////////////
            //
            // Produce a new list containing the members from the original two lists.
            //
            FunctionTable[Symbol.FromString("union")] = (Vector args) =>
            {
                if (args.Count != 2 || args[0] == null || args[1] == null)
                {
                    BraidRuntimeException("union: takes exactly 2 non-null arguments: (union <list1> <list2>).");
                }

                IEnumerable<object> list1 = GetEnumerableFrom(args[0]);
                if (list1 == null)
                {
                    BraidRuntimeException("union: the first argument to union must be a list or enumerable.");
                }

                IEnumerable<object> list2 = GetEnumerableFrom(args[1]);
                if (list2 == null)
                {
                    BraidRuntimeException("union: the second argument to union must be a list or enumerable.");
                }

                return new Vector(Enumerable.Union(list1, list2, new ObjectComparer()));
            };

            /////////////////////////////////////////////////////////////////////
            //
            // Computes the intersection (i.e. members in both argument lists) and return a new list
            // containing that intersection.
            //
            FunctionTable[Symbol.FromString("intersect")] = (Vector args) =>
            {
                if (args.Count != 2 || args[0] == null || args[1] == null)
                {
                    BraidRuntimeException(
                        "intersect: takes exactly 2 non-null arguments: (intersect <list1> <list2>).");
                }

                IEnumerable<object> list1 = GetEnumerableFrom(args[0]);
                if (list1 == null)
                {
                    BraidRuntimeException(
                        "intersect: the first argument to intersect must be a list or enumerable.");
                }

                IEnumerable<object> list2 = GetEnumerableFrom(args[1]);
                if (list2 == null)
                {
                    BraidRuntimeException(
                        "intersect: the second argument to intersect must be a list or enumerable.");
                }

                return new Vector(Enumerable.Intersect(list1, list2, new ObjectComparer()));
            };

            /////////////////////////////////////////////////////////////////////
            //
            // Returns all of the members of argument 1 that aren't in argument 2.
            // 
            FunctionTable[Symbol.FromString("except")] = (Vector args) =>
            {
                if (args.Count != 2)
                {
                    BraidRuntimeException("The 'except' function takes exactly 2 non-null arguments: (except <list1> <list2>).");
                }

                if (args[0] == null)
                {
                    BraidRuntimeException("except: the first argument to 'except' must be a non-null value: (except <list1> <list2>).");
                }

                if (args[1] == null)
                {
                    BraidRuntimeException("except: the second argument to 'except' must be a non-null value: (except <list1> <list2>).");
                }

                IEnumerable<object> list1 = GetEnumerableFrom(args[0]);
                if (list1 == null)
                {
                    BraidRuntimeException($"except: the first argument to 'except' must be a list or enumerable, not {args[0]}");
                }

                IEnumerable<object> list2 = GetEnumerableFrom(args[1]);
                if (list2 == null)
                {
                    BraidRuntimeException($"except: the second argument to 'except' must be a list or enumerable, not {args[1]}");
                }

                return new Vector(Enumerable.Except(list1, list2, new ObjectComparer()));
            };

            /////////////////////////////////////////////////////////////////////
            //
            // Zip two lists together by joining corresponding elements into pairs.
            // An optional lambda can be provided to operate on the pair returning a new value.
            //
            FunctionTable[Symbol.FromString("zip")] = (Vector args) =>
            {
                if (args.Count < 2 || args.Count > 3 || args[0] == null || args[1] == null)
                {
                    BraidRuntimeException(
                        "zip: takes either 2 or 3 non-null arguments: (zip <list1> <list2> [<lambda>]).");
                }

                IEnumerable<object> list1 = GetEnumerableFrom(args[0]);
                if (list1 == null)
                {
                    BraidRuntimeException("zip: the first argument to zip must be a list or enumerable.");
                }

                IEnumerable<object> list2 = GetEnumerableFrom(args[1]);
                if (list2 == null)
                {
                    BraidRuntimeException("zip: the second argument to except must be a list or enumerable.");
                }

                object afunc = null;
                if (args.Count == 3 && args[2] != null)
                {
                    afunc = GetFunc(CallStack, args[2]);
                    if (afunc == null)
                    {
                        BraidRuntimeException($"zip: the third argument to 'zip' must be a function, not '{args[2]}'");
                    }
                }

                IEnumerable<object> zipped = null;

                if (afunc != null && afunc is IInvokeableValue lambda)
                {
                    Vector argvect = new Vector { null, null };
                    zipped = Enumerable.Zip(list1, list2, (arg1, arg2) =>
                    {
                        argvect[0] = arg1;
                        argvect[1] = arg2;

                        return lambda.Invoke(argvect);
                    });
                }
                else if (afunc != null && afunc is Func<Vector, object> func)
                {
                    Vector argvect = new Vector
                    {
                        null,
                        null
                    };

                    zipped = Enumerable.Zip(list1, list2, (arg1, arg2) =>
                    {
                        argvect[0] = arg1;
                        argvect[1] = arg2;

                        return func.Invoke(argvect);
                    });
                }
                else if (afunc != null)
                {
                    zipped = Enumerable.Zip(list1, list2, (arg1, arg2) =>
                    {
                        s_Expr exprToCall = new s_Expr(afunc, new s_Expr(arg1, new s_Expr(arg2)));
                        return Braid.Eval(exprToCall, true, true);
                    });
                }
                else
                {
                    zipped = Enumerable.Zip(list1, list2, (arg1, arg2) => new s_Expr(arg1, new s_Expr(arg2)));
                }

                Vector result = new Vector();
                foreach (var e in zipped)
                {
                    if (e is BraidBreakOperation breakOp)
                    {
                        if (breakOp.HasValue)
                        {
                            return breakOp.BreakResult;
                        }

                        break;
                    }

                    if (e is BraidContinueOperation)
                    {
                        continue;
                    }

                    result.Add(e);
                }

                return result;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Implements reduce or fold-left; doing reduction from left to right
            /// so
            ///     (foldl [1 2 3 4] -)
            /// is equivalent to
            ///     (- (- (- 1 2) 3) 4)
            /// or
            ///     (1 | - 2 | - 3 | - 4)
            ///
            FunctionTable[Symbol.FromString("foldl")] =
            FunctionTable[Symbol.FromString("reduce")] = (Vector args) =>
            {
                if (args.Count < 2 || args.Count > 3 || args[0] == null || args[1] == null)
                {
                    BraidRuntimeException("reduce: takes 2 or 3 non-null arguments: (reduce <list1> <function> [<seed>]).");
                }

                IEnumerable<object> list1 = GetEnumerableFrom(args[0]);
                if (list1 == null)
                {
                    BraidRuntimeException("reduce: the first argument to reduce must be a list or enumerable.");
                }

                var func = GetFunc(CallStack, args[1]);

                if (func == null)
                {
                    BraidRuntimeException($"reduce: the second argument must be a function, not '{args[1]}'");
                }

                object reduced;
                if (func is IInvokeableValue invokeable)
                {
                    Vector argvect = new Vector
                    {
                        null,
                        null
                    };

                    if (args.Count == 3)
                    {
                        reduced = Enumerable.Aggregate(list1, args[2], (arg1, arg2) =>
                        {
                            argvect[0] = arg1;
                            argvect[1] = arg2;
                            return invokeable.Invoke(argvect);
                        });
                    }
                    else
                    {
                        reduced = Enumerable.Aggregate(list1, (arg1, arg2) =>
                        {
                            argvect[0] = arg1;
                            argvect[1] = arg2;
                            return invokeable.Invoke(argvect);
                        });
                    }
                }
                else
                {
                    //BUGBUGBUG - this should eventually be removed...
                    s_Expr argcell1, argcell2;
                    s_Expr exprToCall = new s_Expr(func, argcell1 = new s_Expr(null, argcell2 = new s_Expr(null)));
                    if (args.Count == 3)
                    {
                        reduced = Enumerable.Aggregate(list1, (arg1, arg2) =>
                        {
                            argcell1.Car = arg1;
                            argcell2.Car = arg2;
                            return Braid.Eval(exprToCall, true, true);
                        });
                    }
                    else
                    {
                        reduced = Enumerable.Aggregate(list1, (arg1, arg2) =>
                        {
                            argcell1.Car = arg1;
                            argcell2.Car = arg2;
                            return Braid.Eval(exprToCall, true, true);
                        });
                    }
                }

                return reduced;
            };

            /////////////////////////////////////////////////////////////////////
            //
            FunctionTable[Symbol.FromString("reduce-with-seed")] = (Vector args) =>
            {
                if (args.Count != 3 || args[0] == null || args[1] == null)
                {
                    BraidRuntimeException(
                        "reduce-with-seed: takes exactly 3 non-null arguments: (reduce-with-seed <list1> <lambda> <seed>).");
                }

                IEnumerable<object> list1 = GetEnumerableFrom(args[0]);
                if (list1 == null)
                {
                    BraidRuntimeException(
                        "reduce-with-seed: the first argument to reduce must be a list or enumerable.");
                }

                var seed = args[2];
                object reduced;
                if (args[1] is Callable binlambda)
                {
                    var argvec = new Vector { null, null };
                    reduced = Enumerable.Aggregate(list1, seed, (arg1, arg2) =>
                    {
                        argvec[0] = arg1;
                        argvec[1] = arg2;
                        return binlambda.Invoke(argvec);
                    });
                }
                else
                {
                    reduced = Enumerable.Aggregate(list1, seed, (arg1, arg2) =>
                    {
                        s_Expr exprToCall = new s_Expr(args[1], new s_Expr(arg1, new s_Expr(arg2)));
                        return Braid.Eval(exprToCall, true, true);
                    });
                }

                return reduced;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Implements the fold-right function which does reduction from right to left.
            /// Example:
            ///     (foldr [1 2 3 4] -)
            /// is equivalent to
            ///      (- 1 (- 2 (- 3 4)))
            /// or
            ///      ( 4 | - 3 | - 2 | - 1)
            FunctionTable[Symbol.FromString("foldr")] = (Vector args) =>
            {
                if (args.Count != 2 || args[0] == null || args[1] == null)
                {
                    BraidRuntimeException("foldr: takes exactly 2 non-null arguments: (reduce <list1> <lambda>).");
                }

                var lambda = args[1];
                s_Expr argcell1, argcell2;
                s_Expr exprToCall = new s_Expr(lambda, argcell1 = new s_Expr(null, argcell2 = new s_Expr(null)));

                if (args[0] is IList ilist)
                {
                    // Fast path for indexables; walks the array backwards
                    object y = ilist[ilist.Count - 1];
                    for (var i = ilist.Count - 2; i >= 0; i--)
                    {
                        argcell1.Car = ilist[i];
                        argcell2.Car = y;
                        y = Braid.Eval(exprToCall, true, true);
                    }

                    return y;
                }
                else
                {
                    // Slow path for enumerables
                    IEnumerable<object> list1 = GetEnumerableFrom(args[0]);
                    if (list1 == null)
                    {
                        BraidRuntimeException("foldr: the first argument to reduce must be a list or enumerable.");
                    }

                    var stk = new Stack();
                    foreach (var e in list1)
                    {
                        stk.Push(e);
                    }

                    object y = stk.Pop();
                    while (stk.Count > 0)
                    {
                        argcell1.Car = stk.Pop();
                        argcell2.Car = y;
                        y = Braid.Eval(exprToCall, true, true);
                    }

                    return y;
                }
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Returns the type of the argument object
            /// 
            FunctionTable[Symbol.FromString("type-of")] = (Vector args) =>
            {
                if (args.Count != 1 || args[0] == null)
                {
                    return null;
                }

                return args[0].GetType();
            };

            /////////////////////////////////////////////////////////////////////
            //
            // Function for building tuples
            //
            FunctionTable[Symbol.FromString("tuple")] = (Vector args) =>
            {
                if (args.Count < 0)
                {
                    BraidRuntimeException("tuple: requires at least one argument.");
                }

                switch (args.Count)
                {
                    case 1:
                        return Tuple.Create<object>(args[0]);
                    case 2:
                        return Tuple.Create<object, object>(args[0], args[1]);
                    case 3:
                        return Tuple.Create<object, object, object>(args[0], args[1], args[2]);
                    case 4:
                        return Tuple.Create<object, object, object, object>(args[0], args[1], args[2], args[3]);
                    case 5:
                        return Tuple.Create<object, object, object, object, object>(args[0], args[1], args[2], args[3], args[4]);
                    default:
                        BraidRuntimeException("tuple: can only take up to 5 args.");
                        return null;
                }
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// If the argument is a psobject, this function will return the object
            ///  witht he PSObject wrapper removed.
            ///  
            FunctionTable[Symbol.FromString("baseobject")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException("baseobject: requires exactly one argument");
                }

                if (args[0] is PSObject pso && !(pso.BaseObject is PSCustomObject))
                {
                    return pso.BaseObject;
                }

                return args[0];
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Build a PowerShell PSCustomObject out of it's arguments or a dictionary.
            ///
            SpecialForms[Symbol.FromString("defobject")] = (Vector args) =>
            {
                if (args.Count < 1 || !(args.Count == 1 || args.Count % 2 == 0))
                {
                    BraidRuntimeException(
                        "defobject: requires an even number of arguments representing property name/value pairs.");
                }

                var psco = new PSObject();
                if (args.Count == 1)
                {
                    foreach (DictionaryEntry pair in (Eval(args[0]) as IDictionary))
                    {
                        psco.Properties.Add(new PSNoteProperty(pair.Key.ToString(), pair.Value));
                    }
                }
                else
                {
                    int index = 0;
                    while (index < args.Count)
                    {
                        string name = null;
                        switch (args[index])
                        {
                            case s_Expr sexpr:
                                name = Eval(args[index])?.ToString();
                                break;

                            case Symbol sym:
                                name = sym.Value;
                                break;

                            case KeywordLiteral kwlit:
                                // Strip off the leading ':'.
                                name = kwlit.BaseName;
                                break;

                            case string str:
                                name = str;
                                break;

                            default:
                                BraidRuntimeException($"defobject: a property name must be a symbol or string, not {args[index]}");
                                break;
                        }

                        index++;
                        object pvalue = Eval(args[index]);
                        index++;
                        psco.Properties.Add(new PSNoteProperty(name, pvalue));
                    }
                }
                return psco;
            };

            //////////////////////////////////////////////////////////////////////////
            ///
            /// Function to define a new  type. This function generates real .Net types with real properties
            /// and methods.
            /// 
            SpecialForms[Symbol.sym_deftype] = (Vector args) =>
            {
                if (args.Count < 1)
                {
                    BraidRuntimeException(
                        "missing arguments for 'deftype'; the syntax is: " +
                        "(deftype ^type [-extends: <basetype>] [-implements: <interfaceType>] [[^memberType] member] [:defm methodName <lambda>].");
                }

                string typeName;
                if (args[0] is Type t)
                {
                    typeName = t.Name;
                    if (CallStack.LookUpType(typeName) != null)
                    {
                        CallStack.RemoveType(typeName);
                    }
                    else
                    {
                        BraidRuntimeException($"the type '{typeName}' cannot be redefined.");
                    }
                }
                else if (args[0] is TypeLiteral tlit)
                {
                    typeName = tlit.TypeName;
                }
                else if (args[0] is string tstr)
                {
                    typeName = tstr;
                }
                else if (args[0] is ExpandableStringLiteral testr)
                {
                    typeName = (string)testr.Value;
                }
                else
                {
                    BraidRuntimeException($"the first argument to 'deftype' must be a type literal like '^foo', not '{args[0]}'");
                    return null;
                }

                var callStack = Braid.CallStack;
                var namedParameters = callStack.NamedParameters;
                NamedParameter baseTypeValue;
                Type baseType = null;
                if (namedParameters != null && namedParameters.TryGetValue("extends", out baseTypeValue))
                {
                    switch (baseTypeValue.Expression)
                    {
                        case TypeLiteral tlit:
                            baseType = (Type)tlit.Value;
                            break;
                        case Type bt:
                            baseType = bt;
                            break;
                        default:
                            BraidRuntimeException(
                                $"deftype's '-extends:' property requires a type to use as the base " +
                                $"type to use for the new type; not '{baseTypeValue}'."
                            );
                            break;
                    }
                }

                Type[] interfaces = null;
                NamedParameter implements;
                if (namedParameters != null && namedParameters.TryGetValue("implements", out implements))
                {
                    if (implements.Value is Type itype)
                    {
                        interfaces = new Type[] { itype };
                    }
                    else if (implements.Value is Vector vtypes)
                    {
                        interfaces = new Type[vtypes.Count];
                        int i = 0;
                        foreach (var ty in vtypes)
                        {
                            if (ty is Type ivtype)
                            {
                                interfaces[i++] = ivtype;
                            }
                            else
                            {
                                BraidRuntimeException($"defining type '{typeName}': '-implements' requires either a single type or vector of interface types.");
                            }
                        }
                    }
                    else
                    {
                        BraidRuntimeException($"defining type '{typeName}': '-implements' requires either a single type or vector of interface types.");
                    }
                }

                OrderedDictionary memberDict;
                List<Tuple<Symbol, bool, UserFunction>> methods;
                ProcessTypeDefMembers("deftype", args, typeName, out memberDict, out methods);

                Type newType = BraidTypeBuilder.NewType(typeName, baseType, interfaces, memberDict, methods, isInterface: false);

                // Add file & line info as an association for this type
                var caller = callStack.Caller;
                PutAssoc(newType, "FileInfo", $"{caller.File}:{caller.LineNo}");
                return newType;
            };

            /////////////////////////////////////////////////////////////////////////
            ///
            /// Function to define a .Net interface. Follows the same patterns as 'deftype' except that functions cannot have bodies.
            ///
            SpecialForms[Symbol.sym_definterface] = (Vector args) =>
            {
                if (args.Count < 1)
                {
                    BraidRuntimeException(
                        "missing arguments; syntax: (definterface ^type [-implements: <interfaceType>] [[^memberType] member]* [:defm methodName <lambda>]*.");
                }

                string typeName;
                if (args[0] is Type t)
                {
                    typeName = t.Name;
                }
                else if (args[0] is TypeLiteral tlit)
                {
                    typeName = tlit.TypeName;
                }
                else if (args[0] is string tstr)
                {
                    typeName = tstr;
                }
                else if (args[0] is ExpandableStringLiteral testr)
                {
                    typeName = (string)testr.Value;
                }
                else
                {
                    BraidRuntimeException($"the first argument to 'definterface' must be a type literal like '^foo', not '{args[0]}'");
                    return null;
                }

                var callStack = Braid.CallStack;
                var namedParameters = callStack.NamedParameters;
                Type[] interfaces = null;
                NamedParameter implements;

                if (namedParameters != null)
                {
                    if (namedParameters.TryGetValue("implements", out implements))
                    {
                        if (implements.Value is Type itype)
                        {
                            interfaces = new Type[] { itype };
                        }
                        else if (implements.Value is Vector vtypes)
                        {
                            interfaces = new Type[vtypes.Count];
                            int i = 0;
                            foreach (var ty in vtypes)
                            {
                                if (ty is Type ivtype)
                                {
                                    interfaces[i++] = ivtype;
                                }
                                else
                                {
                                    BraidRuntimeException($"defining interface '{typeName}': '-implements' requires either a single type or vector of interface types.");
                                }
                            }
                        }
                        else
                        {
                            BraidRuntimeException($"defining type '{typeName}': '-implements' requires either a single type or vector of interface types.");
                        }
                    }
                    else if (namedParameters.Count > 0)
                    {
                        BraidRuntimeException("The 'definterface' function only takes one named parameter '-implements:'");
                    }
                }

                OrderedDictionary memberDict;
                List<Tuple<Symbol, bool, UserFunction>> methods;
                ProcessTypeDefMembers("definterface", args, typeName, out memberDict, out methods);

                Type newType = BraidTypeBuilder.NewType(typeName, baseClass: null, interfaces, memberDict, methods, isInterface: true);

                // Add file & line info as an association for this type
                var caller = callStack.Caller;
                PutAssoc(newType, "FileInfo", $"{caller.File}:{caller.LineNo}");

                return newType;
            };

            /////////////////////////////////////////////////////////////////////////
            ///
            /// A function to define a Braid enum type.
            ///     (defenum ^foo red blue green)
            ///     (defenum ^foo {:red 10 :blue 20 :green 30})
            ///
            /// BUGBUGBUG - add more/better error checking and data sanitization.
            SpecialForms[Symbol.FromString("defenum")] = (Vector args) =>
            {
                if (args.Count < 2 || args[0] == null | args[1] == null)
                {
                    BraidRuntimeException("The 'defenum' function requires at least 2 arguments e.g. (defenum ^enumtype <name> <name> ...)/");
                }

                string typeName;
                if (args[0] is TypeElement te)
                {
                    typeName = te.Tlit.TypeName;
                }
                else if (args[0] is TypeLiteral tlit)
                {
                    typeName = tlit.TypeName;
                }
                else
                {
                    typeName = Eval(args[0], true, true)?.ToString();
                }

                // Create a dynamic assembly in the current application domain,
                // and allow it to be executed and saved to disk.
                var asmName = new AssemblyName($"_enum_{typeName}");

                // Create a dynamic assembly in the current application domain
                var ab = System.Reflection.Emit.AssemblyBuilder.DefineDynamicAssembly(asmName, AssemblyBuilderAccess.RunAndCollect);

                // Define a dynamic module in the assembly. For a single-
                // module assembly, the module has the same name as the assembly.
                var mb = ab.DefineDynamicModule(asmName.Name);

                // Define a public enumeration with the name in typeName and an
                // underlying type of Integer (so far Braid only supports Int.)
                EnumBuilder eb = mb.DefineEnum(typeName, TypeAttributes.Public, typeof(int));

                if (args[1] is DictionaryLiteral dlit)
                {
                    IDictionary litdict = (IDictionary)(dlit.Value);
                    foreach (var key in litdict.Keys)
                    {
                        eb.DefineLiteral(key.ToString(), Braid.ConvertToHelper<int>(litdict[key]));
                    }
                }
                else if (args[1] is s_Expr sexpr && Eval(sexpr, true, true) is IDictionary dict)
                {
                    // bind members from a dictionary: (defenum ^bob {:one 1 :two 2 :three 3})
                    foreach (var key in dict.Keys)
                    {
                        eb.DefineLiteral(key.ToString(), Braid.ConvertToHelper<int>(dict[key]));
                    }
                }
                else
                {
                    // Define the members based on the arguments passed to 'defenum'.
                    int index = 0;
                    foreach (var x in args.Skip(1))
                    {
                        if (x is Symbol s)
                        {
                            eb.DefineLiteral(s.ToString(), index++);
                        }
                        else if (x is String str)
                        {
                            eb.DefineLiteral(str, index++);
                        }
                        else if (x is ExpandableStringLiteral estr)
                        {
                            eb.DefineLiteral(estr.Value.ToString(), index++);
                        }
                        else if (x is KeywordLiteral kw)
                        {
                            eb.DefineLiteral(kw.BaseName, index++);
                        }
                        else
                        {
                            BraidRuntimeException($"The 'defenum' function only takes simple symbols or keywords " +
                                                $"as the names for enum members, not values like '{x}' ({x.GetType()}).");
                        }
                    }
                }

                // Create the type and save the assembly.
                Type newType = eb.CreateType();

                var callStack = CallStack;

                // And add the type to the type alias table.
                callStack.SetTypeAlias(typeName, newType);

                // Add file & line info as an association for this type
                var caller = callStack.Caller;
                PutAssoc(newType, "FileInfo", $"{caller.File}:{caller.LineNo}");

                return newType;
            };

            /////////////////////////////////////////////////////////////////////////
            ///
            /// Undefine a Braid type deinition.
            /// 
            SpecialForms[Symbol.FromString("undeftype")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException("undeftype requires 1 non-null argument which is a type to undefine");
                }

                switch (args[0])
                {
                    case TypeLiteral tlit:
                        return CallStack.RemoveType(tlit.TypeName);
                    case Type t:
                        return CallStack.RemoveType(t.Name);
                    case string s:
                        return CallStack.RemoveType(s);
                    case ExpandableStringLiteral esl:
                        return CallStack.RemoveType(esl.Value.ToString());
                    default:
                        BraidRuntimeException("undeftype requires a type to undef; not {args[0]");
                        return false;
                }
            };

            /////////////////////////////////////////////////////////////////////////
            ///
            /// Add a method to an existing Braid class
            ///
            SpecialForms[Symbol.FromString("defmethod")] = (Vector args) =>
            {
                if (args.Count != 3)
                {
                    BraidRuntimeException($"'defmethod' takes 3 arguments: (defmethod <targetType> <methodName> <lambda>)");
                }

                int index = 0;
                var type = args[index++];
                Type typeToExtend = null;
                if (type is Type tte)
                    typeToExtend = tte;
                else if (type is TypeLiteral tlit)
                    typeToExtend = (Type)tlit.Value;
                else
                    BraidRuntimeException($"The first argument to 'defmethod' must be the target type for the new method; not '{type}'");

                string name = args[index] == null ? string.Empty : args[index].ToString();
                if (string.IsNullOrEmpty(name))
                {
                    BraidRuntimeException($"'defmethod': the name of the method to add cannot be null or empty.");
                }
                Symbol methodName = Symbol.FromString(name);
                index++;

                UserFunction body = (args[index] is FunctionLiteral lamlit ? lamlit.Value : args[index]) as UserFunction;
                if (body == null)
                {
                    BraidRuntimeException($"The body of the method being defined with 'defmethod' must be a lambda, not {args[index]}");
                }

                body.Environment = CallStack;

                var methods = new Dictionary<Symbol, UserFunction>() { { methodName, body } };
                BraidTypeBuilder.TypeMethodMap.AddOrUpdate(typeToExtend,
                    (t) => methods,
                    (t, d) =>
                    {
                        // Update the existing dictionary with new bindings.
                        foreach (var pair in methods)
                        {
                            d[pair.Key] = pair.Value;
                        }

                        return d;
                    });

                return body;
            };

            /////////////////////////////////////////////////////////////////////////////////
            ///
            /// Create an alias for a given type
            ///
            SpecialForms[Symbol.FromString("type-alias")] = (Vector args) =>
            {
                if (args.Count > 2
                    || (args.Count == 2 && (args[0] == null || args[1] == null))
                    || (args.Count == 1 && args[0] == null)
                )
                {
                    BraidRuntimeException("type-alias: requires either no args to list the existing type aliases, " +
                                        "or two arguments: a name and a type e.g. (type-alias 'foo ^int) to create a new");
                }

                string alias = null;

                // If no args, just return a copy of the type aliases
                if (args.Count == 0)
                {
                    return CallStack.GetTypes();
                }

                try
                {
                    // Zero args, just list the type aliases
                    if (args[0] is TypeLiteral tlit)
                    {
                        alias = tlit.TypeName;
                    }
                    else
                    {
                        alias = Eval(args[0])?.ToString();
                    }

                    // One argument - remove the specified type alias
                    if (args.Count == 1)
                    {
                        return CallStack.RemoveType(alias);
                    }
                }
                catch (Exception e)
                {
                    BraidRuntimeException($"Error processing alias argument for type-alias: {e.Message}", e);
                }

                Type type;
                try
                {
                    switch (args[1])
                    {
                        case Type t:
                            type = t;
                            break;

                        case TypeLiteral tlit2:
                            type = (Type)tlit2.Value;
                            break;

                        default:
                            type = ConvertToHelper<Type>(Eval(args[1]));
                            break;
                    }
                }
                catch (Exception e)
                {
                    BraidRuntimeException($"Error processing target type argument for type-alias: {e.Message}", e);
                    return null;
                }

                CallStack.SetTypeAlias(alias, type);
                return null;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Evaluate a block of statements in the current scope, returning the
            /// result from the last function evaluated.
            /// 
            SpecialForms[Symbol.FromString("do")] = (Vector args) =>
            {
                object result = null;
                for (int i = 0; i < args.Count; i++)
                {
                    result = BraidLang.Braid.Eval(args[i]);
                    if (result is BraidFlowControlOperation)
                    {
                        return result;
                    }
                }
                return result;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Echo the arguments back to the output
            ///
            FunctionTable[Symbol.FromString("id")] =
            FunctionTable[Symbol.FromString("echo")] = (Vector args) =>
            {
                if (args.Count == 0)
                    return null;

                if (args.Count == 1)
                    return args[0];

                return args;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Function to define a local variable
            ///
            var function_let = new Function(Symbol.sym_let.Value, (Vector args) =>
            {
                if (args.Count < 2 || args.Count > 3)
                {
                    BraidRuntimeException("the 'let/local' function takes either 2 or 3 arguments  e.g. (let [^int] foo 13)");
                }

                IInvokeableValue setter = null;
                IInvokeableValue getter = null;
                bool success = false;

                var callStack = CallStack;
                var namedParameters = callStack.NamedParameters;
                if (namedParameters != null)
                {
                    NamedParameter temp = null;
                    if (namedParameters.TryGetValue("success", out temp))
                    {
                        success = Braid.IsTrue(temp.Value);
                    }

                    if (namedParameters.TryGetValue("setter", out temp))
                    {
                        if (temp.Value is IInvokeableValue iv)
                        {
                            setter = iv;
                        }
                        else
                        {
                            BraidRuntimeException($"The -setter: parameter to 'local/let' requires a value of type " +
                                                $"^IInvokableValue, not {temp.GetType()} " +
                                                "e.g. (let foo 0 -setter: (\\ x -> (* x 2)))");
                        }
                    }

                    if (namedParameters.TryGetValue("getter", out temp))
                    {
                        if (temp.Value is IInvokeableValue iv)
                        {
                            getter = iv;
                        }
                        else
                        {
                            BraidRuntimeException($"The -getter: parameter to 'local/let' requires a value of " +
                                                $"type ^IInvokableValue, not {temp.GetType()} " +
                                                "e.g. (let -getter: (\\ x -> (* x 2)) 0)");
                        }
                    }
                }

                var argIndex = 0;
                if (args[argIndex] == null)
                {
                    BraidRuntimeException("the first argument to the 'let' function must be a symbol or vector, not null");
                }

                TypeLiteral tlit = null;

                if (args.Count > 2)
                {
                    // BUGBUGBUG - throw an explicit error here
                    tlit = args[0] as TypeLiteral;
                    if (tlit == null)
                    {
                        if (args[0] is Type vtype)
                        {
                            tlit = new TypeLiteral(vtype);
                        }
                    }

                    if (tlit != null)
                    {
                        argIndex++;
                    }
                }

                if (tlit == null && args.Count == 3)
                {
                    BraidRuntimeException("the 'let/local' function  takes a maximum of 3 arguments where the first one " +
                        "is a type constraint e.g. (let ^int foo 123)");
                }

                object value;

                // Handle property patterns e.g. (let {day _ month _ year _} .datetime/now) 
                if (args[argIndex] is DictionaryLiteral dlit)
                {
                    if (tlit != null)
                    {
                        BraidRuntimeException($"type constraints like {tlit} cannot be used with property patterns.");
                    }

                    PropertyPatternElement ppe = new PropertyPatternElement(dlit);
                    value = Braid.Eval(args[++argIndex]);
                    if (value is BraidReturnOperation retop1)
                    {
                        return retop1;
                    }

                    return ppe.DoMatch(callStack, value, 0, out int consumed) == MatchElementResult.Matched;
                }

                // Handle a vector pattern e.g. (let [a 2 c] [1 2 3)
                if (args[argIndex] is VectorLiteral vlit)
                {
                    if (tlit != null)
                    {
                        BraidRuntimeException($"type constraints like {tlit} cannot be used with vector patterns.");
                    }

                    var peList = PatternClause.CompilePatternElements(new Vector(vlit.ValueList), out int patternArity, out bool hasStarFunction);
                    NestedPatternElement npe = new NestedPatternElement(peList, patternArity, hasStarFunction);

                    value = Braid.Eval(args[++argIndex]);
                    if (value is BraidReturnOperation retop1)
                    {
                        return retop1;
                    }

                    //BUGBUGBUGBUG - why is this necessary
                    if (value is IList ilist)
                    {
                        value = new Vector { ilist };
                    }

                    return npe.DoMatch(callStack, value, 0, out int consumed) == MatchElementResult.Matched;
                }

                Symbol varsym = args[argIndex] as Symbol;
                ArgIndexLiteral argindexliteral = null;
                if (varsym == null)
                {
                    argindexliteral = args[argIndex] as ArgIndexLiteral;

                    if (argindexliteral == null)
                    {
                        BraidRuntimeException("The 'let' function requires a symbol or argument index (e.g. %0) to assign to.");
                    }
                }

                value = Braid.Eval(args[++argIndex]);
                if (value is BraidReturnOperation retop)
                {
                    return retop;
                }

                if (tlit != null)
                {
                    value = tlit.Invoke(value);
                }

                if (argindexliteral != null)
                {
                    if (Braid.Debugger != 0)
                    {
                        if ((Braid.Debugger & DebugFlags.Trace) != 0 && (Braid.Debugger & DebugFlags.TraceException) == 0)
                        {
                            Console.WriteLine("LET    {0} '{1}' = '{2}'", spaces(_evalDepth + 2), argindexliteral, Braid.Truncate(value));
                        }
                    }

                    argindexliteral.Value = value;

                    // If the -success argument was passed return true (or false), otherwise return the
                    // value being assigened
                    if (success)
                    {
                        return BoxedTrue;
                    }
                    else
                    {
                        return value;
                    }
                }

                if (varsym == Symbol.sym_underbar)
                {
                    return value;
                }

                bool multiAssign = varsym.CompoundSymbol;

                if (Braid.Debugger != 0)
                {
                    if ((Braid.Debugger & DebugFlags.Trace) != 0 && (Braid.Debugger & DebugFlags.TraceException) == 0)
                    {
                        Console.WriteLine("LET    {0} '{1}' = '{2}'", spaces(_evalDepth + 4), varsym, Braid.Truncate(value));
                    }
                }

                object result = null;
                if (tlit != null)
                {
                    if (multiAssign)
                    {
                        BraidRuntimeException("In 'let' function, type qualification cannot be used with multiple assignment.");
                    }

                    BraidVariable var = callStack.SetLocal(tlit, varsym, value);
                    var.Getter = getter;
                    var.Setter = setter;
                    result = value;
                }
                else if (multiAssign)
                {
                    try
                    {
                        bool succeeded = MultipleAssignment(callStack, varsym, value, ScopeType.Local);
                        if (success)
                        {
                            return BoxBool(succeeded);
                        }

                        if (!succeeded)
                        {
                            BraidRuntimeException(
                                $"While executing function 'let', multiple assignment to '{varsym}' failed; value was '{Braid.Truncate(value)}'.");
                        }
                    }
                    catch (BraidUserException)
                    {
                        throw;
                    }
                    catch (Exception e)
                    {
                        if (success)
                        {
                            return BoxedFalse;
                        }

                        BraidRuntimeException(
                            $"While executing function 'let', multiple assignment to '{varsym}' raised an exception: {e.Message}", e);
                    }
                }
                else
                {
                    BraidVariable braidvar = callStack.SetLocal(varsym, value);

                    if (tlit != null)
                    {
                        braidvar.TypeConstraint = tlit;
                    }

                    result = value;

                    // BUGBUGBUGBUG - should the getter be run on first assignment? e.g. (let foo null -getter: (fn _ -> ...))
                    braidvar.Getter = getter;
                    braidvar.Setter = setter;
                }

                return result;
            });
            function_let.FType = FunctionType.SpecialForm;
            CallStack.Const(Symbol.sym_let, function_let);

            /////////////////////////////////////////////////////////////////////
            //
            // Define a function (defn name "doc string" [args...] body ... )
            //
            CallStack.Const(Symbol.sym_defn, new Macro(Symbol.sym_defn.Value, (Vector args) =>
            {
                if (args.Count < 2)
                {
                    if (args.Count > 0)
                        BraidRuntimeException(
                            $"function definition '{args[0]}' requires at least two arguments e.g. (defn {args[0]} [args...] body ... )");
                    else
                        BraidRuntimeException(
                            "function definition requires at least two arguments e.g. (defn name [args...] body ... )");
                }

                var index = 0;

                var callStack = CallStack;
                var caller = callStack.Caller;

                Symbol funcsym = args[index++] as Symbol;
                if (funcsym == null)
                {
                    BraidRuntimeException($"The name of a function must be a symbol, not '{args[0]}'");
                }

                if (args[index] == null)
                {
                    BraidRuntimeException(
                        $"The formal arguments to a function should either be a vector as in (defn foo [a b c] ...) or " +
                        "you can use the '|' symbol to define a pattern function: (defn foo | a b -> ...)");
                }

                string docString = null;
                if (args[index] is string str)
                {
                    docString = str;
                    index++;
                }
                else if (args[index] is ExpandableStringLiteral esl)
                {
                    docString = (string)esl.Value;
                    index++;
                }

                string signature;
                Callable func = null;
                // First handle patterns (defn foo [<docString>] | ...)
                if (Symbol.sym_pipe.Equals(args[index]))
                {
                    var matcher = parsePattern(funcsym.Value, args, index);
                    matcher.IsFunction = true;
                    matcher.Name = funcsym.Value;
                    signature = matcher.Signature;
                    string returnTypeStr = string.Empty;
                    if (matcher.ReturnType != null)
                    {
                        returnTypeStr = $" {matcher.ReturnType}";
                    }

                    func = matcher;
                }
                else
                {
                    var lambda = new UserFunction(funcsym.Value)
                    {
                        Name = funcsym.Value
                    };
                    lambda = parseFunctionBody(lambda, funcsym.Value, args, index);
                    signature = lambda.Signature;
                    string returnTypeStr = string.Empty;
                    if (lambda.ReturnType != null)
                    {
                        returnTypeStr = $" {lambda.ReturnType}";
                    }

                    func = lambda;
                }

                func.LineNo = caller.LineNo;
                func.Offset = caller.Offset;
                func.Text = caller.Text;
                func.File = caller.File;

                signature = $"Syntax: {signature}\n";
                if (docString != null)
                {
                    signature += "\n" + docString.Trim();
                }

                return new s_Expr(function_let, new s_Expr(funcsym, new s_Expr(new FunctionLiteral(func, signature))));
            }));

            /////////////////////////////////////////////////////////////////
            ///
            /// Define a lambda.
            /// 
            SpecialForms[Symbol.sym_lambda] = (Vector args) =>
            {
                return BuildUserFunction(args);
            };

            ////////////////////////////////////////////////////////////////////////
            ///
            /// Undefine (delete) a binding in the current lexical scope chain.
            ///
            SpecialForms[Symbol.FromString("undef")] = (Vector args) =>
            {
                if (args.Count != 1 || args[0] == null)
                {
                    BraidRuntimeException("undef: requires one argument which is the name of the binding to delete.");
                }

                if (!(args[0] is Symbol symbol))
                {
                    symbol = Symbol.FromString(args[0].ToString());
                }

                if (CallStack.RemoveVariable(symbol))
                {
                    return BoxedTrue;
                }

                return BoxedFalse;
            };

            ////////////////////////////////////////////////////////////////////////
            ///
            /// Define a macro. This function is evaluated at parse time so any macros defined
            /// in a file can be used later in that file
            /// 
            SpecialForms[Symbol.sym_defmacro] = (Vector args) =>
            {
                if (args.Count < 2 || args[0] == null)
                {
                    BraidRuntimeException(
                        "The 'defmacro' function requires at least three non-null arguments e.g. (defmacro name [args...] <body ... >)");
                }

                int argIndex = 0;
                Symbol funcsym = args[argIndex++] as Symbol;
                if (funcsym == null)
                {
                    funcsym = Symbol.FromString(args[0].ToString());
                }

                string docString = null;
                if (args[argIndex] is string str)
                {
                    docString = str;
                    argIndex++;
                }
                else if (args[argIndex] is ExpandableStringLiteral esl)
                {
                    docString = (string)esl.Value;
                    argIndex++;
                }

                ////////////////////////////////////////

                string signature;
                Callable funcObj;

                // First handle patterns
                if (Symbol.sym_pipe.Equals(args[argIndex]))
                {
                    var matcher = parsePattern(funcsym.Value, args, argIndex);
                    matcher.FType = FunctionType.Macro;
                    matcher.IsFunction = true;
                    signature = matcher.Signature;
                    funcObj = matcher;
                }
                else
                {
                    var lambda = new UserFunction(funcsym.Value);
                    lambda = parseFunctionBody(lambda, funcsym.Value, args, argIndex);
                    lambda.FType = FunctionType.Macro;
                    signature = lambda.Signature;
                    funcObj = lambda;
                }

                CallStack.SetLocal(funcsym, funcObj);

                funcObj.Environment = CallStack;

                signature = $"Syntax: {signature}\n\n";
                if (docString != null)
                {
                    PutAssoc(funcObj, "helptext", signature + docString.Trim());
                }
                else if (GetAssoc(funcObj, "helptext") == null)
                {
                    PutAssoc(funcObj, "helptext", signature);
                }

                return null;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Define a special form i.e. a function where the arguments aren't evaluated before
            /// calling the function. Example include the "if" and "cond" functions.
            ///
            SpecialForms[Symbol.sym_defspecial] = (Vector args) =>
            {
                if (args.Count < 2 || args[0] == null | args[1] == null)
                {
                    BraidRuntimeException(
                        "defspecial requires at least two arguments e.g. (defspecial name [args...] body... )");
                }

                int index = 0;
                Symbol funcsym = args[index] as Symbol;
                if (funcsym == null)
                {
                    funcsym = Symbol.FromString(args[index].ToString());
                }
                index++;

                string docString = null;
                if (args[index] is string str)
                {
                    docString = str;
                    index++;
                }
                else if (args[index] is ExpandableStringLiteral esl)
                {
                    docString = (string)esl.Value;
                    index++;
                }

                if (index >= args.Count)
                {
                    BraidRuntimeException(
                        "defspecial requires at least three arguments e.g. (defspecial name \"doc string\" [args...] body... )");
                }

                var caller = CallStack.Caller;
                string signature;

                // First handle patterns (defn foo [<docString>] | ...)
                if (Symbol.sym_pipe.Equals(args[index]))
                {
                    var matcher = parsePattern(funcsym.Value, args, index);
                    matcher.IsFunction = true;
                    matcher.FType = FunctionType.SpecialForm;
                    matcher.Environment = CallStack;

                    CallStack.SetLocal(funcsym, matcher);
                    if (caller != null)
                    {
                        matcher.File = caller.File;
                        matcher.LineNo = caller.LineNo;
                    }
                    else
                    {
                        matcher.File = Braid._current_file;
                    }

                    matcher.Name = funcsym.Value;

                    signature = $"Syntax (Pattern Function): ({funcsym} {matcher.Signature})\n\n";
                    if (docString != null)
                    {
                        PutAssoc(matcher, "helptext", signature + docString.Trim());
                    }
                    else if (GetAssoc(matcher, "helptext") == null)
                    {
                        PutAssoc(matcher, "helptext", signature);
                    }
                }
                else
                {
                    var lambda = new UserFunction(funcsym.Value);
                    CallStack.SetLocal(funcsym, lambda);

                    if (caller != null)
                    {
                        lambda.File = caller.File;
                        lambda.LineNo = caller.LineNo;
                    }
                    else
                    {
                        lambda.File = Braid._current_file;
                    }

                    lambda.Name = funcsym.Value;

                    lambda = parseFunctionBody(lambda, funcsym.Value, args, index);

                    lambda.FType = FunctionType.SpecialForm;

                    string returnTypeStr = string.Empty;
                    if (lambda.ReturnType != null)
                    {
                        returnTypeStr = $" {lambda.ReturnType}";
                    }

                    signature = $"Syntax: {lambda.Signature}\n\n";

                    if (docString != null)
                    {
                        PutAssoc(lambda, "helptext", signature + docString.Trim());
                    }
                    else if (GetAssoc(lambda, "helptext") == null)
                    {
                        PutAssoc(lambda, "helptext", signature);
                    }
                }

                return null;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Evaluate an s-expression as a function.
            /// 
            FunctionTable[Symbol.FromString("eval")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException("eval: requires exactly one argument: the code to execute.");
                }

                // null is the empty list which evaluates to (surprise) null.
                if (args[0] == null)
                {
                    return null;
                }

                return Eval(args[0]);
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Evaluate a list of expressions in the parent's dynamic scope.
            /// 
            FunctionTable[Symbol.FromString("upDo")] = (Vector args) =>
            {
                if (args == null || args.Count < 1)
                {
                    return null;
                }

                object result = null;
                var currentScope = CallStack;
                PopCallStack();
                try
                {
                    foreach (object arg in args)
                    {
                        if (arg != null)
                        {
                            result = Eval(arg);
                        }
                        else
                        {
                            result = null;
                        }
                    }
                }
                finally
                {
                    PushCallStack(currentScope);
                }

                return result;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Parse a string into an s-expression then evaluate it.
            ///
            FunctionTable[Symbol.FromString("eval-string")] = (Vector args) =>
            {
                if (args.Count != 1 || args[0] == null)
                {
                    BraidRuntimeException("eval-string: requires exactly one non-argument");
                }

                return Eval(Parse(args[0].ToString()));
            };

            /////////////////////////////////////////////////////////////////////
            //
            // Set up a new binding context, either explicitly e.g. (let ((a 1) (b 2)) ...)
            // or by passing a dictionary
            // (let dict {a 1 b 2})  (let dict ... )
            //
            SpecialForms[Symbol.sym_with] = (Vector args) =>
            {
                if (args.Count < 1 || args[0] == null)
                {
                    BraidRuntimeException("with: requires at least 1 argument e.g. (with [a 1 b 2] ...)");
                }

                // Evaluate the argument expressions in the current scope.
                List<BraidVariable> varsToBind = new List<BraidVariable>();

                // handle (let [(a 1) (b 2)] ...) or (let [a 1 b 2] ...) 
                if (args[0] is VectorLiteral vlit)
                {
                    s_Expr val = vlit.ValueList;

                    while (val != null)
                    {
                        object current = val.Car;
                        if (current is s_Expr pair)
                        {
                            if (pair.Count != 2)
                            {
                                BraidRuntimeException($"with: binding pairs must be a 2 element list, not: {pair}");
                            }

                            var car = pair.Car;
                            if (car == null)
                            {
                                BraidRuntimeException($"with: the first element of a binding pair cannot be null.");
                            }

                            Symbol symToBind = car as Symbol;
                            if (symToBind == null)
                            {
                                if (car is string symname)
                                {
                                    symToBind = Symbol.FromString(symname);
                                }
                                else if (car is Callable callable)
                                {
                                    symToBind = Symbol.FromString(callable.Name);
                                }

                                if (symToBind == null)
                                {
                                    BraidRuntimeException(
                                        "with: the first element of a binding pair must be a string or symbol.");
                                }
                            }

                            // We've checked the length so we know that the cdr is non-null
                            var bindingExpr = ((s_Expr)pair.Cdr).Car; //BUGBUG - clean this up

                            object vvalue = Braid.Eval(bindingExpr);
                            if (Braid.Debugger != 0)
                            {
                                if ((Braid.Debugger & DebugFlags.Trace) != 0 && (Braid.Debugger & DebugFlags.TraceException) == 0)
                                {
                                    Console.WriteLine("WITH    {0} '{1}' = '{2}'", spaces(_evalDepth + 2), symToBind, Braid.Truncate(vvalue));
                                }
                            }

                            varsToBind.Add(new BraidVariable(symToBind, vvalue));
                            val = (s_Expr)val.Cdr;
                        }
                        else
                        {
                            if (current == null)
                            {
                                BraidRuntimeException("The symbol to bind in a 'let' function call cannot be null.");
                            }

                            TypeLiteral argType = null;
                            if (current is TypeLiteral tlit)
                            {
                                argType = tlit;
                                val = (s_Expr)val.Cdr;
                                if (val == null)
                                {
                                    if (current == null)
                                    {
                                        BraidRuntimeException("A type constraint in a typed 'let' binding must be followed by a variable name.");
                                    }
                                }
                                else
                                {
                                    current = val.Car;
                                    if (current == null)
                                    {
                                        BraidRuntimeException("The symbol to bind in a 'with' function call cannot be null.");
                                    }
                                }
                            }

                            Symbol symToBind = current as Symbol;
                            if (symToBind == null)
                            {
                                symToBind = Symbol.FromString(current.ToString());
                            }

                            object vvalue = null;
                            val = (s_Expr)val.Cdr;
                            if (val != null)
                            {
                                vvalue = Eval(val.Car);
                                val = (s_Expr)val.Cdr;
                            }

                            varsToBind.Add(new BraidVariable(symToBind, vvalue, argType));
                        }
                    }
                }
                else
                {
                    BraidRuntimeException(
                        $"with: the first argument must be a list of binding pairs, not: '{args[0]}'.");
                }

                try
                {
                    // Create a stack frame for the let execution scope
                    var caller = CallStack.Caller;
                    PSStackFrame callStack = PushCallStack(new PSStackFrame(caller.File, "with", caller, CallStack));

                    foreach (var braidvar in varsToBind)
                    {
                        Symbol symToBind = braidvar.Name;
                        if (symToBind.CompoundSymbol)
                        {
                            BindMultiple(callStack, braidvar.Value, ScopeType.Local, symToBind.ComponentSymbols, symToBind._bindRestToLast);
                        }
                        else
                        {
                            callStack.Vars.Add(braidvar.Name, braidvar);
                        }
                    }

                    // now evaluate all the functions in the body
                    object result = null;
                    for (var index = 1; index < args.Count; index++)
                    {
                        if (Braid._stop)
                        {
                            break;
                        }
                        result = BraidLang.Braid.Eval(args[index]);
                    }

                    return result;

                }
                catch (BraidExitException)
                {
                    throw;
                }
                finally
                {
                    // and finally restore the old stack frame
                    PopCallStack();
                }
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Apply a function to an optional list
            ///
            FunctionTable[Symbol.FromString("apply")] = (Vector args) =>
            {
                if (args.Count != 2)
                {
                    BraidRuntimeException("The 'apply' function requires 2 arguments: (apply <function> <coll>).");
                }

                IInvokeableValue iv = GetFunc(CallStack, args[0]) as IInvokeableValue;
                if (iv == null)
                {
                    BraidRuntimeException($"The first argument to 'apply' must be a valid function, not '{args[0]}'.");
                }

                if (args[1] == null)
                {
                    return null;
                }

                if (args[1] is Vector argvect)
                {
                    return iv.Invoke(argvect);
                }

                return iv.Invoke(new Vector(GetNonGenericEnumerableFrom(args[1])));
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Set a variable value; note both args are evaluated so quoting may be necessary
            ///  e.g. (set 'num (+ 2 3))
            //
            FunctionTable[Symbol.FromString("set")] = (Vector args) =>
            {
                if (args.Count != 2 || args[0] == null)
                {
                    BraidRuntimeException("set: takes exactly 2 arguments e.g. (set 'foo 123).");
                }

                Symbol varsym = args[0] as Symbol;
                if (varsym == null)
                {
                    string strname = args[0] as string;
                    if (strname == null)
                    {
                        BraidRuntimeException("The first argument to set must be either a symbol or a string naming the variable to set.");
                    }

                    varsym = Symbol.FromString(strname);
                }

                return CallStack.Set(varsym, args[1]);
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Set a variable value in the parent dynamic scope i.e. up set
            /// Note both args are evaluated so quoting may be necessary.
            ///  e.g. (upvar 'parentSymbol 'localSymbol)
            // BUGBUGBUG - doesn't handle destructuring a:b:c
            FunctionTable[Symbol.FromString("upvar")] = (Vector args) =>
            {
                if (args.Count != 2 || args[0] == null || args[1] == null)
                {
                    BraidRuntimeException("upvar: takes exactly 2 arguments e.g. (upvar 'parentSymbol 'localSymbol).");
                }

                if (!(args[0] is Symbol parentSym))
                {
                    string strname = args[0] as string;
                    if (strname == null)
                    {
                        BraidRuntimeException("The first argument to 'upvar' must evaluate to either a symbol or a string naming the variable to set e.g. (upvar 'foo 13).");
                    }

                    parentSym = Symbol.FromString(strname);
                }

                Symbol localSym = args[1] as Symbol;
                if (localSym == null)
                {
                    string strname = args[1] as string;
                    if (strname == null)
                    {
                        BraidRuntimeException("The first argument to 'upvar' must evaluate to either a symbol or a string naming the variable to set e.g. (upvar 'foo 13).");
                    }

                    localSym = Symbol.FromString(strname);
                }

                var pvar = _callStackStack.Peek().GetOrCreateLocalVar(parentSym);

                // BUGBUGBUG - this will just wack any existing variables, even if their constant. Need to be more careful here
                CallStack.Vars[localSym] = pvar;

                return pvar;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Get a variable value; the arg is evaluated so quoting may be necessary e.g. (get 'foo)
            ///
            FunctionTable[Symbol.FromString("get")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException("get: takes exactly 1 argument and 1 switch: (get <symbol> [-caller]).");
                }

                if (!(args[0] is Symbol varsym))
                {
                    varsym = Symbol.FromString(args[0].ToString());
                }

                bool caller = false;
                var namedParameters = CallStack.NamedParameters;
                if (namedParameters != null)
                {
                    caller = namedParameters.ContainsKey("caller");
                }

                if (caller)
                    return _callStackStack.Peek().GetValue(varsym);

                return _callStack.GetValue(varsym);
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Get a variable value; the arg is evaluated so quoting may be necessary e.g. (get 'foo)
            ///
            FunctionTable[Symbol.FromString("getfunc")] = (Vector args) =>
            {
                if (args.Count < 1 || args[0] == null || args.Count > 2)
                {
                    BraidRuntimeException("getfunc: takes 1 argument and 2 switches: (getfunc <funcToLookUp> [-caller] [-noexternals])");
                }

                bool caller = false;
                bool noExternals = false;
                var namedParameters = CallStack.NamedParameters;
                if (namedParameters != null)
                {
                    caller = namedParameters.ContainsKey("caller");
                    noExternals = namedParameters.ContainsKey("noExternals");

                }

                if (caller)
                {
                    return GetFunc(_callStackStack.Peek(), args[0], noExternals);
                }

                return GetFunc(CallStack, args[0], noExternals);
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Get the variable object corresponding to the argument symbol
            ///
            FunctionTable[Symbol.FromString("getvar")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException("getvar: takes exactly 1 argument.");
                }

                if (!(args[0] is Symbol varsym))
                {
                    varsym = Symbol.FromString(args[0].ToString());
                }

                return CallStack.GetVariable(varsym);
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Special form that sets a variable; quotes the first argument
            /// This form has 3 aliases 'setq' '=' and 'set!'.
            ///
            SpecialForms[Symbol.FromString("def")] =
            SpecialForms[Symbol.FromString("setq")] = (Vector args) =>
            {
                if (args.Count != 2)
                {
                    BraidRuntimeException("the 'def' function takes exactly 2-3 arguments and, optionally, the -Success switch.");
                }

                if (args[0] == null)
                {
                    BraidRuntimeException("the first argument to 'def' cannot be null");
                }

                object value = null;
                if (args[1] != null)
                {
                    value = Braid.Eval(args[1]);
                }

                var callStack = Braid.CallStack;

                var varsym = args[0] as Symbol;
                if (varsym == null)
                {
                    varsym = Symbol.FromString(args[0].ToString());
                }

                bool success = false;
                var namedParameters = callStack.NamedParameters;
                if (namedParameters != null)
                {
                    success = namedParameters.ContainsKey("success");
                }

                if (Braid.Debugger != 0)
                {
                    if ((Braid.Debugger & DebugFlags.Trace) != 0 && (Braid.Debugger & DebugFlags.TraceException) == 0)
                    {
                        Console.WriteLine("DEF    {0} (depth {1}) '{2}' = '{3}'", spaces(_evalDepth + 2), Braid._callStackStack.Count, varsym, Braid.Truncate(value));
                    }
                }

                if (varsym.CompoundSymbol)
                {
                    bool succeeded = MultipleAssignment(callStack, varsym, value, ScopeType.Lexical);
                    if (success)
                    {
                        return succeeded;
                    }
                }
                else
                {
                    callStack.Set(varsym, value);
                }

                return value;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Let-to-right 'def' function.
            /// 
            SpecialForms[Symbol.FromString(">def")] = (Vector args) =>
            {
                if (args.Count != 2)
                {
                    BraidRuntimeException("the '>def' function takes exactly 2 arguments and, optionally, the -Success switch.");
                }

                if (args[1] == null)
                {
                    BraidRuntimeException("the second argument to this command cannot be null");
                }

                object value = null;
                if (args[0] != null)
                {
                    value = Braid.Eval(args[0]);
                }

                var callStack = Braid.CallStack;

                var varsym = args[1] as Symbol;
                if (varsym == null)
                {
                    varsym = Symbol.FromString(args[1].ToString());
                }

                // Short-circuit assignment to '_'.
                if (varsym == Symbol.sym_underbar)
                {
                    return null;
                }

                bool success = false;
                var namedParameters = callStack.NamedParameters;
                if (namedParameters != null)
                {
                    success = namedParameters.ContainsKey("success");
                }

                if (!MultipleAssignment(callStack, varsym, value, ScopeType.Lexical))
                {
                    if (success && varsym.CompoundSymbol)
                    {
                        return BoxedFalse;
                    }

                    callStack.Set(varsym, value);
                }

                if (success)
                {
                    return BoxedTrue;
                }

                return value;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Define a constant value in the currect scope.
            /// 
            SpecialForms[Symbol.FromString("const")] = (Vector args) =>
            {
                if (args.Count != 2 || args[0] == null)
                {
                    BraidRuntimeException($"The 'const' function requires 2 arguments not {args.Count}. Usage: (const varname value)");
                }

                Symbol varsym = args[0] as Symbol;
                if (varsym == null)
                {
                    varsym = Symbol.FromString(args[0].ToString());
                }

                object val = Eval(args[1]);
                BraidVariable variable = CallStack.SetLocal(varsym, val);
                variable.Const = true;

                // add a typeconstraint based on the the type value
                if (val != null)
                {
                    variable.TypeConstraint = new TypeLiteral(val.GetType());
                }

                return val;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Ge or set a value in the global scope.
            /// 
            SpecialForms[Symbol.FromString("global")] = (Vector args) =>
            {
                if (args.Count < 1 || args[0] == null)
                {
                    BraidRuntimeException("global: takes at least 1 argument: (global varname [value])");
                }

                var name = Eval(args[0]);
                Symbol varsym = name as Symbol;
                if (varsym == null)
                {
                    varsym = Symbol.FromString(args[0].ToString());
                }

                if (args.Count == 1)
                {
                    return GlobalScope.GetValue(varsym);
                }

                object val = Eval(args[1]);
                GlobalScope.SetLocal(varsym, val);
                return val;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Get or set a value in the global scope. The first argument is quoted
            ///
            SpecialForms[Symbol.FromString("globalq")] = (Vector args) =>
            {
                if (args.Count < 1 || args[0] == null)
                {
                    BraidRuntimeException("global: takes at least 1 argument: (globalq varname [value])");
                }

                Symbol varsym = args[0] as Symbol;
                if (varsym == null)
                {
                    varsym = Symbol.FromString(args[0].ToString());
                }

                if (args.Count == 1)
                {
                    return GlobalScope.GetValue(varsym);
                }

                object val = Eval(args[1]);

                if (!MultipleAssignment(CallStack, varsym, val, ScopeType.Global))
                {
                    GlobalScope.SetLocal(varsym, val);
                }

                return null;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Sets a binding in the caller's scope (dynamic scoping)
            /// 
            FunctionTable[Symbol.FromString("def-dynamic")] = (Vector args) =>
            {
                if (args.Count != 2 || args[0] == null)
                {
                    BraidRuntimeException("def-in-parent: takes at least 2 arguments: (def-in-parent varname value)");
                }

                if (!(args[0] is Symbol varsym))
                {
                    varsym = Symbol.FromString(args[0].ToString());
                }

                // If we're in a child scope, set in the callers scope, otherwise
                // just set it in the current lexical scope.
                if (_callStackStack != null && _callStackStack.Count > 0)
                {
                    var scope = _callStackStack.Peek();
                    scope.Set(varsym, args[1]);
                }
                else
                {
                    CallStack.Set(varsym, args[1]);
                }
                return null;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Look up the activation stack instead of the lexical stack.
            /// 
            SpecialForms[Symbol.FromString("gdv")] =
            SpecialForms[Symbol.FromString("get-dynamic")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException("get-dynamic: takes exactly 1 argument.");
                }

                if (args[0] == null)
                {
                    BraidRuntimeException("get-dynamic: the argument to get-dynamic cannot be null.");
                }

                if (!(args[0] is Symbol varsym))
                {
                    varsym = Symbol.FromString(args[0].ToString());
                }

                return Braid.GetDynamic(varsym);
            };

            /////////////////////////////////////////////////////////////////////
            ////
            /// swap scalar variable values (swap x y) or array values (swap x 1 x 2)
            /// 
            SpecialForms[Symbol.FromString("swap")] = (Vector args) =>
            {
                Callable swapfunc = null;
                var callStack = CallStack;

                if (args.Count < 2 || args.Count > 5)
                {
                    BraidRuntimeException("swap: requires either 2 or 4 arguments. e.g. (swap v1 v2) or (swap v1 index1 v2 index2)");
                }

                if (args.Count < 4)
                {
                    if (args.Count == 3)
                    {
                        swapfunc = GetFunc(callStack, args[2]) as Callable;
                    }

                    if (args[0] is Symbol sym1 && args[1] is Symbol sym2)
                    {
                        object val1 = GetValue(sym1);
                        object val2 = GetValue(sym2);
                        if (swapfunc == null || Braid.IsTrue(swapfunc.Invoke(new Vector { val1, val2 })))
                        {
                            callStack.Set(sym1, val2);
                            callStack.Set(sym2, val1);
                        }
                    }
                    else
                    {
                        BraidRuntimeException(
                            $"swap: when 2 arguments are specified, they must both be symbols not '{args[0]}' and '{args[1]}'.");
                    }
                }
                else
                {
                    if (args.Count == 5)
                    {
                        swapfunc = GetFunc(callStack, args[4]) as Callable;
                    }

                    if (args[0] is Symbol sym1 && args[2] is Symbol sym2)
                    {
                        // Get the Indices...
                        int index1 = ConvertToHelper<int>(Eval(args[1]));
                        int index2 = ConvertToHelper<int>(Eval(args[3]));
                        IList val1 = (IList)GetValue(sym1);
                        IList val2 = (IList)GetValue(sym2);

                        if (swapfunc == null || Braid.IsTrue(swapfunc.Invoke(new Vector { val1[index1], val2[index2] })))
                        {
                            (val2[index2], val1[index1]) = (val1[index1], val2[index2]);
                        }
                    }
                    else
                    {
                        BraidRuntimeException(
                            $"swap: when 4 arguments are specified,  the pattern is (swap <collection1> <index1> <collection2> <index2>).");
                    }
                }
                return null;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Function to create a new dictionary instance taking the types of the
            /// keys and values as arguments and the list of elements to add
            /// This function is used by the dictionary literal notations.
            /// 
            SpecialForms[Symbol.sym_new_dict] = (Vector args) =>
            {
                if (args.Count == 1)
                {
                    BraidRuntimeException("new-dict: requires either 0 or more pairs of arguments e.g. " +
                                        "(new-dict) (new-dict ^string ^object) (new-dict ^string object :a 1 :b 2)");
                }

                if (args.Count == 0)
                {
                    return new Dictionary<object, object>(new ObjectComparer());
                }
                else
                {
                    Type t1;
                    Type t2;
                    IDictionary dict;

                    try
                    {
                        t1 = Eval(args[0]) as Type;
                        t2 = Eval(args[1]) as Type;
                        Type open = typeof(System.Collections.Generic.Dictionary<,>);
                        Type closed = open.MakeGenericType(t1, t2);
                        if (t1 == typeof(string))
                        {
                            dict = (IDictionary)Activator.CreateInstance(closed, StringComparer.OrdinalIgnoreCase);
                        }
                        else if (t1 == typeof(object))
                        {
                            dict = (IDictionary)Activator.CreateInstance(closed, new ObjectComparer());
                        }
                        else
                        {
                            // BUGBUGBUG - why doesn't this take an object comparer
                            dict = (IDictionary)Activator.CreateInstance(closed);
                        }
                    }
                    catch (Exception e)
                    {
                        BraidRuntimeException($"Error creating dictionary: {e.Message}", e);
                        return null;
                    }

                    try
                    {
                        if (args.Count > 2)
                        {
                            object key;
                            object value;
                            for (int i = 2; i < args.Count; i++)
                            {
                                key = args[i];

                                // If this is a splatted dictionary, merge the splatted dictionary's
                                // keys into the new dictionary.
                                if (key is s_Expr skey && skey.Car == Symbol.sym_splat)
                                {
                                    IDictionary kdict = null;
                                    if (skey.Cdr is Symbol sym)
                                    {
                                        kdict = ConvertToHelper<IDictionary>(GetValue(sym));
                                    }
                                    else if (skey.Cdr is string vstr)
                                    {
                                        kdict = ConvertToHelper<IDictionary>(GetValue(Symbol.FromString(vstr)));
                                    }
                                    else
                                    {
                                        kdict = ConvertToHelper<IDictionary>(Eval(skey.Cdr));
                                    }

                                    //  BUGBUGBUG - add code here to properly merge KeyValuePair and DictionaryEntries. 
                                    foreach (var dkey in kdict.Keys)
                                    {
                                        object dictkey;
                                        if (t1 != typeof(object))
                                        {
                                            dictkey = ConvertTo(dkey, t1);
                                        }
                                        else
                                        {
                                            dictkey = dkey;
                                        }

                                        value = ConvertTo(kdict[dkey], t2);

                                        dict[dictkey] = value;
                                    }

                                    continue;
                                }

                                // Handle non-splatted values
                                if (t1 != typeof(object))
                                {
                                    key = ConvertTo(Eval(args[i]), t1);
                                }
                                else if (args[i] is KeywordLiteral klit)
                                {
                                    // BUGBUGBUG - this should be removed when keywords get rationalized.
                                    key = klit.BaseName;
                                }
                                else
                                {
                                    key = Eval(args[i]);
                                }

                                if (key == null)
                                {
                                    BraidRuntimeException($"The key expression '{args[i]}' resulted in a null value during dictionary creation.");
                                }

                                if (++i >= args.Count)
                                {
                                    BraidRuntimeException($"Missing value for key '{key}' during dictionary creation.");
                                    return null;
                                }

                                value = ConvertTo(Eval(args[i]), t2);
                                dict[key] = value;
                            }
                        }
                        return dict;
                    }
                    catch (BraidExitException)
                    {
                        throw;
                    }
                    catch (Exception e)
                    {
                        BraidRuntimeException($"Error initializing dictionary elements: {e.Message}", e);
                    }
                }

                return null;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Create a new vector with the args becomming elements
            /// 
            FunctionTable[Symbol.FromString("vector")] =
            FunctionTable[Symbol.sym_new_vector] = (Vector args) =>
            {
                if (args.Count == 0)
                {
                    return new Vector();
                }

                return args;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Create a vector out of the argument enumerable. If the argument is
            /// already a vector it's just returned as-is instead of being copied.
            ///
            /// See also: new-vector copy-vector
            ///
            FunctionTable[Symbol.sym_to_vector] = (Vector args) =>
            {
                if (args.Count == 0)
                {
                    return new Vector();
                }

                if (args.Count > 1)
                {
                    BraidRuntimeException("'to-vector' only takes 1 argument which should be the value or values to include in the Vector.");
                }

                object lst = args[0];
                if (lst == null)
                {
                    return new Vector();
                }
                if (lst is IEnumerable ienum)
                {
                    return new Vector(ienum);
                }
                else
                {
                    return new Vector(GetNonGenericEnumerableFrom(lst));
                }
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Function to turn a collection into a string with an optional separator string.
            /// The default separator is a single space (' '). Example:
            ///    ([1 2 3 4] | join \"+\") ; returns \"1+2+3+4\"
            ///
            /// See also: + join str
            ///
            FunctionTable[Symbol.sym_join] = (Vector args) =>
            {
                if (args.Count < 1)
                {
                    return null;
                }

                if (args.Count > 2)
                {
                    BraidRuntimeException("The 'join' function takes a list to join with an optional seperator (default is ' '): (join <list> [<sep>])");
                }

                object lst = args[0];
                string sep = " ";
                if (args.Count == 2)
                {
                    if (args[1] == null)
                    {
                        sep = string.Empty;
                    }
                    else
                    {
                        sep = args[1].ToString();
                    }
                }

                StringBuilder sb = new StringBuilder();
                bool first = true;
                foreach (var element in GetNonGenericEnumerableFrom(lst))
                {
                    if (element == null)
                    {
                        continue;
                    }

                    string selement = element.ToString();
                    if (selement.Length == 0)
                    {
                        continue;
                    }

                    if (first)
                    {
                        first = false;
                    }
                    else
                    {
                        sb.Append(sep);
                    }

                    sb.Append(selement);
                }

                return sb.ToString();
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Join all arguments into a string with no separators.
            ///
            FunctionTable["str"] = (Vector args) =>
            {
                if (args.Count < 1)
                {
                    return string.Empty;
                }

                StringBuilder sb = new StringBuilder();
                foreach (var element in args)
                {
                    if (element == null)
                    {
                        continue;
                    }

                    string selement = element.ToString();
                    if (selement.Length == 0)
                    {
                        continue;
                    }

                    sb.Append(selement);
                }

                return sb.ToString();
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Syntax: (new-array <type> <length> [ initializers...])
            ///
            /// Create a new array of the specified type, size with optional initializers. Conversions
            /// are done on the initializers.
            ///
            /// Examples:
            ///     (new-array ^int 7)                  ; array of seven integers
            ///     (new-array ^string 3 "a" "b" "c")   ; array of three strings initialized
            /// 
            FunctionTable[Symbol.FromString("new-array")] = (Vector args) =>
            {
                if (args.Count < 1)
                {
                    BraidRuntimeException("'new-array' requires the type, count and initializers for the array e.g. (new-array ^int 3 10 20 30)");
                }

                Type type = ConvertToHelper<Type>(args[0]);

                if (type == null)
                {
                    BraidRuntimeException("the first argument to new-array must be the type of the array e.g. (new-array ^int 3 10 20 30)");
                }

                if (args.Count == 1)
                {
                    BraidRuntimeException("the second argument to 'new-array' must be the length of the array to create " +
                                        "e.g. (new-array ^int 3 10 20 30)");
                }

                int length = ConvertToHelper<int>(args[1]);
                if (length == -1)
                {
                    length = args.Count - 2;
                }
                else if (length < args.Count - 2)
                {
                    BraidRuntimeException($"More initializers ({args.Count})were specified to 'new-array' than can be fit into the array.");
                }

                Array result = Array.CreateInstance(type, length);
                int index = 2;
                while (index < args.Count)
                {
                    result.SetValue(ConvertTo(args[index], type), index - 2);
                    index++;
                }

                return result;
            };

            /////////////////////////////////////////////////////////////////////
            //
            // Access a method or property on an object. Handles both static and instance members and
            // both methods and properties. This function uses PowerShell PSObject type adapters.
            //
            // Examples:
            //      (. "abcd" :length)              ; returns 4
            //      (. "abcde" :substring 1 3)      ; returns "bcd"
            //
            FunctionTable[Symbol.sym_dot] = (Vector args) =>
            {
                if (args.Count < 2)
                {
                    BraidRuntimeException("At least 2 arguments must be provided for the '.' function: (. <targetObject> <memberName>)");
                }

                if (args[0] == null)
                {
                    BraidRuntimeException("The first argument to '.' cannot be null; it should be a reference " +
                                        "to the object whose member is being accessed.");
                }

                if (args[1] == null)
                {
                    BraidRuntimeException("The second argument to '.' cannot be null; it should be a string " +
                                        "naming the member to access on the argument object.");
                }

                string memberName = args[1].ToString();

                Vector newArgs = new Vector { args[0] };
                newArgs.AddRange(args.GetRange(2, args.Count - 2));

                return InvokeMember(false, memberName, newArgs);
            };

            /////////////////////////////////////////////////////////////////////
            //
            // Function to create a new instance of an object.
            //
            FunctionTable[Symbol.sym_new] = (Vector args) =>
            {
                if (args.Count < 1 || args[0] == null)
                {
                    BraidRuntimeException("The first argument to the 'new' function must be the type of the object to construct.");
                }

                Dictionary<string, NamedParameter> namedParameters;
                IDictionary propertiesToSet = null;
                if ((namedParameters = CallStack.NamedParameters) != null)
                {
                    NamedParameter np;
                    if (namedParameters.Count == 1 && namedParameters.TryGetValue("properties", out np))
                    {
                        object val = np.Value;
                        propertiesToSet = val as IDictionary;
                        if (propertiesToSet == null)
                        {
                            BraidRuntimeException($"The -Properties: parameter to the 'new' function requires a dictionary argument.");
                        }
                    }
                    else
                    {
                        BraidRuntimeException($"The only named parameter supported by the 'new' function is -Properties:.");
                    }
                }

                Type typeval = args[0] as Type;
                object result = null;

                Type targetType = typeval != null ? typeval : ConvertToHelper<Type>(args[0]);

                // If there's a braid-defined constructor (i.e. a 'new' method) then it overrides other constructors
                Callable methodBody = BraidTypeBuilder.GetMethodFromMap(targetType, Symbol.sym_new);
                if (methodBody != null)
                {
                    // If there is a dynamic construction then create the object using the default constructor
                    // and invoke that dynamic method on it.
                    result = args[0] = Activator.CreateInstance(targetType);
                    methodBody.Invoke(args);
                }
                else
                {
                    switch (args.Count - 1)
                    {
                        case 0:
                            result = Activator.CreateInstance(targetType);
                            break;
                        case 1:
                            result = Activator.CreateInstance(targetType, FixupArg(args[1]));
                            break;
                        case 2:
                            result = Activator.CreateInstance(targetType, FixupArg(args[1]), FixupArg(args[2]));
                            break;
                        case 3:
                            result = Activator.CreateInstance(targetType,
                                FixupArg(args[1]), FixupArg(args[2]), FixupArg(args[3]));
                            break;
                        case 4:
                            result = Activator.CreateInstance(targetType,
                                FixupArg(args[1]), FixupArg(args[2]), FixupArg(args[3]), FixupArg(args[4]));
                            break;
                        case 5:
                            result = Activator.CreateInstance(targetType,
                                FixupArg(args[1]), FixupArg(args[2]), FixupArg(args[3]), FixupArg(args[4]),
                                    FixupArg(args[5]));
                            break;
                        case 6:
                            result = Activator.CreateInstance(targetType,
                                FixupArg(args[1]), FixupArg(args[2]), FixupArg(args[3]), FixupArg(args[4]),
                                    FixupArg(args[5]), FixupArg(args[6]));
                            break;
                        case 7:
                            result = Activator.CreateInstance(targetType,
                                FixupArg(args[1]), FixupArg(args[2]), FixupArg(args[3]), FixupArg(args[4]),
                                    FixupArg(args[5]), FixupArg(args[6]), FixupArg(args[7]));
                            break;
                        default:
                            BraidRuntimeException($"The 'new' function can handle a maximum of 7 arguments, not {args.Count - 1}");
                            break;
                    }
                }

                if (propertiesToSet != null)
                {
                    Delegate lambda = null;
                    foreach (var keyval in propertiesToSet.Keys)
                    {
                        object junk;
                        var key = keyval.ToString();
                        var valToSet = propertiesToSet[keyval];
                        DynamicUtils.SetProperty(result, key, valToSet, out junk, ref lambda);
                    }
                }

                return result;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Gets the MethodInfo of the method matching the passed type signature.
            /// 
            FunctionTable[Symbol.FromString("Get-Method")] = (Vector args) =>
            {
                if (args.Count < 2 || args[0] == null || args[1] == null)
                {
                    BraidRuntimeException($"Get-Method requires at least two non-null arguments: (get-method ^type :methodname [paramTypes...]");
                }

                Type targetType = args[0] as Type;
                if (targetType == null)
                {
                    BraidRuntimeException($"The first argument to 'Get-Method' must be a type.");
                }

                string methodName = args[1].ToString();

                Type[] typeArgs = null;
                if (args.Count > 2)
                {
                    int len = args.Count - 2;
                    typeArgs = new Type[len];
                    for (int index = 0; index < len; index++)
                    {
                        Type tval = args[index + 2] as Type;
                        if (tval == null)
                        {
                            BraidRuntimeException($"Type arguments to 'Get-Method' must be a valid, non-null type; not {args[index + 2]}");
                        }
                        typeArgs[index] = tval;
                    }
                }

                var methodList = targetType.GetMethods(BindingFlags.Public | BindingFlags.Static | BindingFlags.Instance
                                                      | BindingFlags.FlattenHierarchy | BindingFlags.IgnoreCase);

                var result = methodList
                            .Where(m => m.Name.Equals(methodName, StringComparison.OrdinalIgnoreCase)
                                && CheckParameters(m, typeArgs))
                            .FirstOrDefault();

                return result;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Dynamically invoke a method on an object.
            /// 
            ///     Invoke-Method <object> <methodName> <args>...
            ///     
            FunctionTable[Symbol.FromString("Invoke-Method")] = (Vector args) =>
            {
                if (args.Count < 2 || args[0] == null || args[1] == null)
                {
                    BraidRuntimeException($"Invoke-Method requires at least two non-null arguments: " +
                                         "(invoke-method object :methodname [method parameters...])");
                }

                Type targetType;
                if (args[0] is Type type)
                {
                    targetType = type;
                }
                else
                {
                    targetType = args[0].GetType();
                }

                string methodName = args[1].ToString();

                Type[] typeArgs = null;
                object[] parameterArray = new object[0];
                if (args.Count > 2)
                {
                    int len = args.Count - 2;
                    typeArgs = new Type[len];
                    parameterArray = new object[len];
                    for (int index = 0; index < len; index++)
                    {
                        Type tval = args[index + 2].GetType();
                        parameterArray[index] = ConvertTo(args[index + 2], tval);
                        typeArgs[index] = tval;
                    }
                }

                var methodList = targetType.GetMethods(BindingFlags.Public | BindingFlags.Static | BindingFlags.Instance
                                                        | BindingFlags.FlattenHierarchy | BindingFlags.IgnoreCase);

                var mi = methodList
                            .Where(m => m.Name.Equals(methodName, StringComparison.OrdinalIgnoreCase)
                                && CheckParameters(m, typeArgs))
                            .FirstOrDefault();

                if (mi == null)
                {
                    string str = string.Join(" ", typeArgs.ToList().Select(n => {
                        if (n != null) { return n.ToString(); } else { return "nil"; } }).ToArray());
                    BraidRuntimeException($"Invoke-Method: method '{methodName}' was not found on type ^{targetType} with argument types {str}");
                }

                if (mi.IsStatic)
                {
                    return mi.Invoke(null, parameterArray);
                }
                else
                {
                    return mi.Invoke(args[0], parameterArray);
                }
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Create a delegate of specified type from a lambda.
            /// 
            FunctionTable[Symbol.FromString("CreateDelegate")] = (Vector args) =>
            {
                if (args.Count != 2 || args[0] == null || args[1] == null)
                {
                    BraidRuntimeException("CreateDelegate: requires two arguments (CreateDelegate <type> <lambda>)");
                }

                Type t = args[0] as Type;
                if (t == null)
                {
                    BraidRuntimeException(
                        "CreateDelegate: The first parameter must be the type of delegate to create not {args[0]}");
                }

                Callable expr = args[1] as Callable;
                if (expr == null)
                {
                    BraidRuntimeException(
                        $"CreateDelegate: the second argument must be a Callable function; not {args[1]}.");
                }

                return CreateDelegate(t, expr);
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Map a lambda onto a list of objects, returning the resulting vector of objects.
            /// This function is strict rather than lazy-map which is lazy.
            ///
            SpecialForms[Symbol.FromString("map")] = (Vector args) =>
            {
                var callStack = Braid.CallStack;

                if (callStack.NamedParameters != null)
                {
                    BraidRuntimeException("The 'map' function doesn't take any named parameters.");
                }

                if (args.Count == 1)
                {
                    return curryFunction(Symbol.FromString("map"), args[0]);
                }

                if (args.Count != 2)
                {
                    BraidRuntimeException($"map: requires 2 arguments; not {args.Count} e.g. (map data <condLambda>)");
                }

                // If there's no data; just return.
                if (args[0] == null)
                {
                    return null;
                }

                object func = args[1];

                if (func is s_Expr sexpr)
                {
                    func = Eval(sexpr);
                }

                if (!(func is IInvokeableValue))
                {
                    func = Braid.GetFunc(callStack, func);
                }

                if (func == null)
                {
                    BraidRuntimeException(
                        $"map: the second argument to 'map' must resolve to a function; not '{args[1]}'");
                }

                object rawdata = Eval(args[0], true, true);
                IEnumerable data = GetNonGenericEnumerableFrom(rawdata);

                var result = new Vector();
                object retval = null;

                if (func is IInvokeableValue lambda)
                {
                    var argvec = new Vector() { null };
                    foreach (var item in data)
                    {
                        if (_stop)
                        {
                            break;
                        }

                        argvec[0] = item;
                        retval = lambda.Invoke(argvec);
                        if (retval is BraidFlowControlOperation)
                        {
                            if (retval is BraidBreakOperation breakOp)
                            {
                                if (breakOp.HasValue)
                                {
                                    return breakOp.BreakResult;
                                }

                                break;
                            }
                            else if (retval is BraidContinueOperation)
                            {
                                continue;
                            }
                            else if (retval is BraidRecurOperation || retval is BraidReturnOperation)
                            {
                                return retval;
                            }
                        }

                        result.Add(retval);
                    }
                }
                else if (func is Func<Vector, object> nfunc)
                {
                    var argvec = new Vector();
                    argvec.Add(null);
                    foreach (var item in data)
                    {
                        if (_stop)
                        {
                            break;
                        }

                        argvec[0] = item;
                        retval = nfunc.Invoke(argvec);
                        if (retval is BraidFlowControlOperation)
                        {

                            if (retval is BraidBreakOperation breakOp)
                            {
                                if (breakOp.HasValue)
                                {
                                    return breakOp.BreakResult;
                                }

                                break;
                            }
                            else if (retval is BraidContinueOperation)
                            {
                                continue;
                            }
                            else if (retval is BraidRecurOperation || retval is BraidReturnOperation)
                            {
                                return retval;
                            }
                        }

                        result.Add(retval);
                    }
                }
                else
                {
                    s_Expr dataArg;
                    var action = new s_Expr(func, dataArg = new s_Expr(null));
                    foreach (var item in data)
                    {
                        if (_stop)
                        {
                            break;
                        }

                        dataArg.Car = item;
                        retval = Braid.Eval(action, true, true);

                        if (retval is BraidFlowControlOperation)
                        {
                            if (retval is BraidBreakOperation breakOp)
                            {
                                if (breakOp.HasValue)
                                {
                                    return breakOp.BreakResult;
                                }

                                break;
                            }
                            else if (retval is BraidContinueOperation)
                            {
                                continue;
                            }
                            else if (retval is BraidRecurOperation || retval is BraidReturnOperation)
                            {
                                return retval;
                            }
                        }

                        result.Add(retval);
                    }
                }

                if (result.Count == 0)
                {
                    return null;
                }
                else
                {
                    return result;
                }
            };

            /////////////////////////////////////////////////////////////////////
            //
            // Map a lambda onto a list of objects, returning nothing so
            // it's main purpose is side-effects.
            // This function is strict.
            //
            SpecialForms[Symbol.FromString("each")] = (Vector args) =>
            {
                if (args.Count == 1)
                {
                    return curryFunction(Symbol.FromString("each"), args[0]);
                }

                if (args.Count != 2)
                {
                    BraidRuntimeException($"each: requires 2 arguments; not {args.Count} e.g. (each data <function>)");
                }

                // If there's no data; just return.
                if (args[0] == null)
                {
                    return null;
                }

                object func = args[1];

                if (func is s_Expr sexpr)
                {
                    func = Eval(sexpr);
                }

                if (!(func is IInvokeableValue))
                {
                    func = Braid.GetFunc(CallStack, func);
                }

                if (func == null)
                {
                    BraidRuntimeException(
                        $"map: the second argument to 'each' must resolve to a function; not '{args[1]}'");
                }

                object result;

                if (func is IInvokeableValue invokeable)
                {
                    var nfunc = invokeable.FuncToCall;

                    var argvec = new Vector();
                    argvec.Add(null);

                    foreach (var item in GetNonGenericEnumerableFrom(Eval(args[0], true, true)))
                    {
                        if (_stop)
                        {
                            break;
                        }

                        argvec[0] = item;
                        result = nfunc.Invoke(argvec);

                        if (result is BraidFlowControlOperation fco)
                        {
                            if (result is BraidContinueOperation)
                            {
                                continue;
                            }
                            else if (result is BraidBreakOperation breakOp)
                            {
                                if (breakOp.HasValue)
                                {
                                    return breakOp.BreakResult;
                                }

                                break;
                            }
                            else if (result is BraidRecurOperation || result is BraidReturnOperation)
                            {
                                return result;
                            }
                        }
                    }

                    return null;
                }

                // BUGBUGBUG This shouldn't be necessary
                s_Expr data;
                var action = new s_Expr(func, data = new s_Expr(null));

                foreach (var item in GetNonGenericEnumerableFrom(Eval(args[0], true, true)))
                {
                    if (_stop)
                    {
                        break;
                    }

                    data.Car = item;
                    result = Braid.Eval(action, true, true);

                    if (result is BraidFlowControlOperation fco)
                    {
                        if (result is BraidContinueOperation)
                        {
                            continue;
                        }
                        else if (result is BraidBreakOperation)
                        {
                            break;
                        }
                        else if (result is BraidRecurOperation || result is BraidReturnOperation)
                        {
                            return result;
                        }
                    }
                }

                return null;
            };


            /////////////////////////////////////////////////////////////////////
            ///
            /// Lazily map a lambda onto a list of objects, returning an enumerator.
            ///
            SpecialForms[Symbol.FromString("lazy-map")] = (Vector args) =>
            {
                if (args.Count == 1)
                {
                    return curryFunction(Symbol.FromString("lazy-map"), args[0]);
                }

                if (args.Count != 2)
                {
                    BraidRuntimeException($"lazy-map: requires 2 arguments; not {args.Count} e.g. (lazy-map data <function>)");
                }

                // If theres no data; just return.
                if (args[0] == null)
                {
                    return null;
                }

                object func = args[1];

                if (func is s_Expr sexpr)
                {
                    func = Eval(sexpr);
                }

                if (!(func is IInvokeableValue))
                {
                    func = Braid.GetFunc(CallStack, func);
                }

                if (func == null)
                {
                    BraidRuntimeException(
                        $"map: the second argument to 'lazy-map' must resolve to a function; not '{args[1]}'");
                }

                return new BraidLang.BraidMapIterator(func, GetNonGenericEnumerableFrom(Eval(args[0], true, true)));
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Map a lambda onto a list on objects, returning the resulting list of objects flattened by one level.
            /// This function is strict.
            ///
            FunctionTable[Symbol.FromString("flatmap")] = (Vector args) =>
            {
                if (args.Count == 1)
                {
                    return curryFunction(Symbol.FromString("flatmap"), args[0]);
                }

                if (args.Count != 2)
                {
                    BraidRuntimeException(
                        $"flatmap: requires exactly 2 non-null arguments; not {args.Count}: (flatmap <list> <lambda>).");
                }

                // If theres no data; just return.
                if (args[0] == null)
                {
                    return null;
                }

                object func = args[1];

                if (func is s_Expr sexpr)
                {
                    func = Eval(sexpr);
                }

                if (!(func is IInvokeableValue))
                {
                    func = Braid.GetFunc(CallStack, func);
                }

                if (func == null)
                {
                    BraidRuntimeException(
                        $"map: the second argument to 'flatmap' must resolve to a function; not '{args[1]}'");
                }

                var result = new Vector();
                s_Expr data;
                var cond = new s_Expr(func, data = new s_Expr(null));
                foreach (var item in GetNonGenericEnumerableFrom(args[0]))
                {
                    if (_stop)
                    {
                        break;
                    }

                    data.Car = item;
                    try
                    {
                        // don't flatten strings or dictionaries.
                        object obj = Braid.Eval(cond, true, true);
                        if (obj is string || obj is IDictionary)
                        {
                            result.Add(obj);
                        }
                        else
                        {
                            foreach (var nesteditem in GetNonGenericEnumerableFrom(Braid.Eval(cond, true, true)))
                            {
                                result.Add(nesteditem);
                            }
                        }
                    }
                    catch (InvalidCastException)
                    {
                        // Ignore invalid cast, it's simply a failure to match in this case
                    }
                }

                return result;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Lazily map a lambda onto a list on objects, returning the resulting list of objects flattened by one level.
            /// Returns an enumerator.
            ///
            FunctionTable[Symbol.FromString("lazy-flatmap")] = (Vector args) =>
            {
                if (args.Count == 1)
                {
                    return curryFunction(Symbol.FromString("lazy-flatmap"), args[0]);
                }

                if (args.Count != 2)
                {
                    BraidRuntimeException(
                        $"lazy-flatmap: requires exactly 2 non-null arguments; not {args.Count}: (lazy-flatmap <list> <function>).");
                }

                // If theres no data; just return.
                if (args[0] == null)
                {
                    return null;
                }

                object func = args[1];

                if (func is s_Expr sexpr)
                {
                    func = Eval(sexpr);
                }

                if (!(func is IInvokeableValue))
                {
                    func = Braid.GetFunc(CallStack, func);
                }

                if (func == null)
                {
                    BraidRuntimeException(
                        $"map: the second argument to 'lazy-flatmap' must resolve to a function; not '{args[1]}'");
                }

                IEnumerable lazyflatmap(object valToEnumerate, object mapfunc)
                {
                    s_Expr data;
                    var condExpr = new s_Expr(mapfunc, data = new s_Expr(null));
                    foreach (var item in GetNonGenericEnumerableFrom(valToEnumerate))
                    {
                        if (_stop)
                        {
                            break;
                        }

                        if (item is string || item is IDictionary)
                        {
                            data.Car = item;
                            object obj = Braid.Eval(condExpr, true, true);
                            yield return obj;
                        }
                        else
                        {
                            data.Car = item;
                            foreach (var nesteditem in GetNonGenericEnumerableFrom(Braid.Eval(condExpr, true, true)))
                            {
                                yield return nesteditem;
                            }
                        }
                    }
                }

                return lazyflatmap(args[0], func);
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Flatten a list of objects (recursive implementation.)
            ///
            FunctionTable[Symbol.FromString("flatten")] = (Vector args) =>
            {
                if (args.Count < 1)
                {
                    BraidRuntimeException("the flatten function requires at least one argument.");
                }

                Vector flatten(IEnumerable ienum)
                {
                    Vector result = new Vector();
                    foreach (var val in ienum)
                    {
                        if (val == null || val is string || val is IDictionary)
                        {
                            result.Add(val);
                            continue;
                        }

                        if (_stop)
                        {
                            break;
                        }

                        if (val is IEnumerable valenum)
                        {
                            foreach (var element in valenum)
                            {
                                if (_stop)
                                {
                                    break;
                                }

                                if (element is null || element is string || element is IDictionary)
                                {
                                    result.Add(element);
                                }
                                else if (element is IEnumerable elementEnum)
                                {
                                    result.AddRange(flatten(elementEnum));
                                }
                                else
                                {
                                    result.Add(element);
                                }
                            }
                            continue;
                        }

                        // Otherwise, just add it as a scalar
                        result.Add(val);
                    }

                    return result;
                }

                return flatten(args);
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Lazily flatten a list of objects (recursive implementation.)
            ///
            FunctionTable[Symbol.FromString("lazy-flatten")] = (Vector args) =>
            {
                if (args.Count < 1)
                {
                    BraidRuntimeException("the flatten function requires at least one argument.");
                }

                IEnumerable lazyflatten(IEnumerable ienum)
                {
                    foreach (var val in ienum)
                    {
                        if (_stop)
                        {
                            break;
                        }

                        if (val == null || val is string || val is IDictionary)
                        {
                            yield return val;
                            continue;
                        }

                        if (val is IEnumerable valenum)
                        {
                            foreach (var element in valenum)
                            {
                                if (_stop)
                                {
                                    break;
                                }

                                if (element == null || element is string || element is IDictionary)
                                {
                                    yield return element;
                                }
                                else if (element is IEnumerable elementEnum)
                                {
                                    foreach (var obj in lazyflatten(elementEnum))
                                    {
                                        yield return obj;
                                    }
                                }
                                else
                                {
                                    yield return element;
                                }
                            }
                            continue;
                        }
                        else
                        {
                            // Otherwise, just add it as a scalar
                            yield return val;
                        }
                    }
                }

                return lazyflatten(args);
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// (Re)Bind a lambda to either the current environment or a optional passed argument.
            /// 
            FunctionTable[Symbol.FromString("bind")] = (Vector args) =>
            {
                if (args.Count < 1 || args[0] == null)
                {
                    BraidRuntimeException($"bind: requires 1 or 2 arguments: (bind lambda [environment])", null);
                }

                var lambda = args[0] as UserFunction;
                if (lambda == null)
                {
                    BraidRuntimeException($"bind: the first argument must be of type ^Lambda, not '{args[0]}'", null);
                }

                if (args.Count == 2)
                {
                    if (args[1] is PSStackFrame env)
                    {
                        lambda.Environment = env;
                    }
                    else if (args[1] is IDictionary dict)
                    {
                        Dictionary<Symbol, BraidVariable> bindings = new Dictionary<Symbol, BraidVariable>();
                        foreach (var key in dict.Keys)
                        {
                            Symbol varsym = Symbol.FromString(key.ToString());
                            bindings.Add(varsym, new BraidVariable(varsym, dict[key]));
                        }

                        var newenv = new PSStackFrame(lambda.File, lambda.Name, lambda.Body, CallStack, bindings);
                        lambda.Environment = newenv;
                    }
                    else
                    {
                        BraidRuntimeException("bind: the second argument to bind must be an instance of PSStackFrame.", null);
                    }
                }
                else
                {
                    lambda.Environment = CallStack;
                }

                // Return the bound lambda
                return lambda;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Returns the current environment
            ///
            FunctionTable[Symbol.FromString("environment")] = (Vector args) =>
            {
                if (args != null && args.Count > 0)
                {
                    BraidRuntimeException("The 'environment' function takes no parameters.");
                }

                return CallStack;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Function to determine if a symbol is bound.
            ///
            FunctionTable[Symbol.FromString("bound?")] = (Vector args) =>
            {
                if (args.Count != 1 || args[0] == null)
                {
                    BraidRuntimeException("bound?: requires exactly 1 non-null argument.");
                }

                Symbol symToCheck = args[0] as Symbol;
                if (symToCheck == null)
                {
                    symToCheck = Symbol.FromString(args[0].ToString());
                }

                return CallStack.IsBound(symToCheck);
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Returns true if the argument is not a collection (IEnumerable)
            ///
            FunctionTable[Symbol.FromString("atom?")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException("atom?: requires exactly 1 argument.");
                }

                var val = args[0];

                return val is string || !(val is IEnumerable);
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Predicate to determine if an object is a symbol.
            ///
            FunctionTable[Symbol.FromString("symbol?")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException("symbol?: requires exactly 1 argument.");
                }

                return args[0] is Symbol;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Predicate to determine if an object is a function
            /// 
            FunctionTable[Symbol.FromString("function?")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException("function?: requires exactly 1 argument.");
                }

                object obj = args[0];

                if (obj == null)
                {
                    return false;
                }

                if (obj is PSObject pobj)
                {
                    obj = pobj.BaseObject;
                }

                // Quick tests for known function types, both Braid and PowerShell
                if (obj is Callable
                || obj is Func<Vector, object>
                || obj is ScriptBlock
                || obj is CommandInfo)
                {
                    return BoxedTrue;
                }

                if (obj is s_Expr sexpr)
                {
                    if (sexpr.IsLambda)
                        return BoxedTrue;
                    else
                        return BoxedFalse;
                }

                // Detailed search which will also find PowerShell and external commands.
                FunctionType ftype;
                string funcname;
                return Braid.BoxBool(GetFunc(CallStack, obj, out ftype, out funcname, noExternals: false, lookup: false) != null);
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Predicate to determine if an object is a string.
            FunctionTable[Symbol.FromString("string?")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException("string?: requires exactly 1 argument.");
                }

                return args[0] is string;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Predicate to detect if an object is a dictionary
            /// 
            FunctionTable[Symbol.FromString("dict?")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException("dict?: requires exactly 1 argument.");
                }

                return args[0] is IDictionary;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Convert an object into a string. If more than one argument is
            /// provided, then the individual arguments are converted to
            /// strings and the result is concatenated into a single string (see "str")
            ///
            FunctionTable[Symbol.sym_tostring] = (Vector args) =>
            {
                if (args.Count < 1)
                {
                    return string.Empty;
                }

                StringBuilder sb = new StringBuilder();
                foreach (var arg in args)
                {
                    if (arg == null)
                    {
                        continue;
                    }

                    if (arg is IDictionary dictval)
                    {
                        sb.Append(Utils.ToStringDict(dictval));
                    }
                    else if (arg is HashSet<object> hashset)
                    {
                        sb.Append(Utils.ToStringHashSet(hashset));
                    }
                    else
                    {
                        sb.Append(arg.ToString());
                    }
                }
                return sb.ToString();
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Convert a number into the corresponding character value
            ///
            FunctionTable[Symbol.FromString("char")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException("The 'char' function requires exactly 1 integer argument. e.g. (char 97)");
                }
                return ConvertToHelper<char>(args[0]);
            };

            ///////////////////////////////////////////////////////////////////
            ///
            /// Convert a string into a vector of chars
            /// 
            FunctionTable[Symbol.FromString("chars")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException("The 'chars' function requires exactly 1 string argument. e.g. (chars \"hello\")");
                }

                if (args[0] == null)
                {
                    return new Vector();
                }

                string data = args[0].ToString();
                Vector result = new Vector(data.Length);

                // copy the chars into the result vector; don't use .toCharArray because it means copying twice 
                for (int i = 0; i < data.Length; i++)
                {
                    result.Add(data[i]);
                }

                return result;
            };

            //////////////////////////////////////////////////////////////
            ///
            /// Returns a customized function for accessing a specifc key in a dictionary
            ///
            FunctionTable[Symbol.FromString("dict/accessor")] = (Vector args) =>
            {
                if (args.Count != 1 || args[0] == null)
                {
                    BraidRuntimeException("this function requires exactly one non-null dictionary key argument.");
                }

                object key = args[0];
                Func<Vector, Object> func = aargs =>
                {
                    if (aargs == null || aargs.Count != 1 || aargs[0] == null)
                    {
                        BraidRuntimeException($"The argument to a dictionary accessor with key '{key}' should be a dictionary.");
                    }

                    var obj = aargs[0];
                    if (obj is IDictionary dict)
                    {
                        return dict[key];
                    }

                    if (obj is IEnumerable enumerable)
                    {
                        Vector result = new Vector();
                        foreach (var elem in enumerable)
                        {
                            // Skip elements that aren't dictionaries
                            if (elem is IDictionary dictelem)
                            {
                                result.Add(dictelem[key]);
                            }
                        }
                        return result;
                    }

                    BraidRuntimeException($"a directory accessor requires a directory to work on, not {obj.GetType()}");
                    return null;
                };

                return func;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Test to see if an object is a list
            ///
            FunctionTable[Symbol.FromString("pair?")] =
            FunctionTable[Symbol.FromString("list?")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException("list? requires exactly 1 argument.");
                }

                return args[0] is s_Expr;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Test to see if an object is an IList
            ///
            FunctionTable[Symbol.FromString("ilist?")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException("ilist? requires exactly 1 argument.");
                }

                return args[0] is IList;
            };
            /////////////////////////////////////////////////////////////////////
            ///
            /// Test to see if an object is a Seq
            ///
            FunctionTable[Symbol.FromString("seq?")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException("seq? requires exactly 1 argument.");
                }

                return args[0] is ISeq;
            };

            /////////////////////////////////////////////////////////////////////
            FunctionTable[Symbol.FromString("vector?")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException("vector?: requires exactly 1 argument.");
                }

                return args[0] is Vector || args[0] is VectorLiteral;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Test to see if an object is a collection
            ///
            FunctionTable[Symbol.FromString("collection?")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException("collection?: requires exactly 1 argument.");
                }

                var obj = args[0];
                return obj is ISeq || obj is ICollection;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Test to see if a value is null.
            /// 
            FunctionTable[Symbol.FromString("nil?")] =
            FunctionTable[Symbol.FromString("null?")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException("null?: requires exactly 1 argument.");
                }

                return args[0] == null;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Test to see if a value is not null.
            /// 
            FunctionTable[Symbol.FromString("notnil?")] =
            FunctionTable[Symbol.FromString("notnull?")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException("notnull?: requires exactly 1 argument.");
                }

                return args[0] != null;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Returns true if the argument has some value e.g. is not null or empty
            /// 
            FunctionTable[Symbol.FromString("some?")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException("some?: requires exactly 1 argument.");
                }

                if (args[0] is ISeq seq && seq.Count() == 0)
                {
                    return false;
                }
                else if (args[0] is string str && str.Length == 0)
                {
                    return false;
                }
                else if (args[0] is IDictionary dict && dict.Count == 0)
                {
                    return false;
                }
                else
                {
                    return args[0] != null;
                }
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Returns true if the argument doesn't have a value e.g. is null or empty
            /// 
            FunctionTable[Symbol.FromString("none?")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException("none?: requires exactly 1 argument.");
                }

                if (args[0] is ISeq seq && seq.Count() == 0)
                {
                    return true;
                }
                else if (args[0] is string str && str.Length == 0)
                {
                    return true;
                }
                else if (args[0] is IDictionary dict && dict.Count == 0)
                {
                    return true;
                }
                else
                {
                    return args[0] == null;
                }
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Returns true if the argument is a function.
            /// 
            FunctionTable[Symbol.FromString("lambda?")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException("lambda?: requires exactly 1 argument.");
                }

                return args[0] is Callable || (args[0] is s_Expr sexpr && sexpr.IsLambda);
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Returns true if the argument is quoted.
            /// 
            FunctionTable[Symbol.FromString("quote?")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException("quote?: requires exactly 1 argument.");
                }

                return (args[0] is s_Expr sexpr) && sexpr.IsQuote;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Returns true if the argument is a keyword object
            ///
            FunctionTable[Symbol.FromString("keyword?")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException("keyword?: requires exactly 1 argument.");
                }

                return args[0] is KeywordLiteral;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Returns true if the argument is a number
            ///
            FunctionTable[Symbol.FromString("number?")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException("number?: requires exactly 1 argument.");
                }

                return Numberp(args[0]);
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// true if the argument is positive
            /// 
            FunctionTable[Symbol.FromString("pos?")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException($"pos?: requires exactly 1 argument.");
                }

                dynamic val = args[0];
                if (Numberp(val))
                    return val >= 0;
                else
                    return false;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// true if the argument is negative
            ///
            FunctionTable[Symbol.FromString("neg?")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException($"neg?: requires exactly 1 argument.");
                }

                dynamic val = args[0];
                if (Numberp(val))
                    return val < 0;
                else
                    return false;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// returns the argument negated
            /// 
            FunctionTable[Symbol.FromString("neg")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException($"neg: requires exactly 1 argument.");
                }

                dynamic val = args[0];
                if (Numberp(val))
                {
                    return -val;
                }
                else
                {
                    BraidRuntimeException($"the argument to the 'neg' function must be a numeric type not '{val}' ({val.GetType()}).");
                    return false;
                }
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// true if the argument is zero
            /// 
            FunctionTable[Symbol.FromString("zero?")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException($"zero?: requires exactly 1 argument.");
                }
                object val = args[0];
                if (Numberp(val))
                {
                    dynamic dval = val;
                    return dval == 0;
                }
                else
                    return false;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// true if the argument is even
            /// 
            FunctionTable[Symbol.FromString("even?")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException($"even?: requires exactly 1 argument.");
                }
                dynamic val = args[0];
                if (Numberp(val))
                    return val % 2 == 0;
                else
                    return false;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// true if the argument is odd
            /// 
            FunctionTable[Symbol.FromString("odd?")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException($"odd?: requires exactly 1 argument.");
                }
                dynamic val = args[0];
                if (Numberp(val))
                    return val % 2 != 0;
                else
                    return false;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Returns true if the first argument is of the type in the second argument
            /// 
            SpecialForms[Symbol.FromString("is?")] = (Vector args) =>
            {
                if (args.Count == 1)
                {
                    return curryFunction(Symbol.FromString("is?"), args[0]);
                }

                if (args.Count != 2)
                {
                    BraidRuntimeException("is?: requires exactly 2 arguments: (is? <object> <type>).");
                }

                object val = Eval(args[0]);

                TypeLiteral tlit = null;
                if (args[1] is TypeLiteral tl)
                {
                    tlit = tl;
                }
                else
                {
                    object tval = Eval(args[1]);
                    if (val == null && tval is null)
                    {
                        return true;
                    }

                    if (tval is Type type)
                    {
                        tlit = new TypeLiteral(type);
                    }
                    else
                    {
                        BraidRuntimeException("is?: the <type> argument is null or invalid: (is? <object> <type>).");
                    }
                }

                object result;
                return tlit.TestValue(val, out result);
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Returns true if the first argument is not of the type in the second argument
            /// 
            SpecialForms[Symbol.FromString("isnot?")] = (Vector args) =>
            {
                if (args.Count == 1)
                {
                    return curryFunction(Symbol.FromString("isnot?"), args[0]);
                }

                if (args.Count != 2)
                {
                    BraidRuntimeException("The 'isnot?' requires exactly 2 arguments: (isnot? <object> <type>).");
                }

                object val = Eval(args[0]);

                TypeLiteral tlit = null;
                if (args[1] is TypeLiteral tl)
                {
                    tlit = tl;
                }
                else
                {
                    object tval = Eval(args[1]);
                    if (val == null && tval is null)
                    {
                        return false;
                    }

                    if (tval is TypeLiteral tvl)
                    {
                        tlit = tvl;
                    }
                    else if (tval is Type type)
                    {
                        tlit = new TypeLiteral(type);
                    }
                    else
                    {
                        BraidRuntimeException("isnot?: the <type> argument is invalid: (is? <object> <type>).");
                    }
                }

                object result;
                return !tlit.TestValue(val, out result);
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Tries to convert the first argument to the type specified by the second argument.
            /// 
            SpecialForms[Symbol.FromString("as")] = (Vector args) =>
            {
                if (args.Count == 1)
                {
                    return curryFunction(Symbol.FromString("as"), args[0]);
                }

                if (args.Count != 2)
                {
                    BraidRuntimeException("as: requires exactly 2 arguments: (as? <object> <type>).");
                }

                object val = Eval(args[0]);
                TypeLiteral tlit = null;
                if (args[1] is TypeLiteral tl)
                {
                    tlit = tl;
                }
                else
                {
                    object tval = Eval(args[1]);

                    if (val is Type type)
                    {
                        tlit = new TypeLiteral(type);
                    }
                    else
                    {
                        BraidRuntimeException("as: the <type> argument is invalid: (as <object> <type>).");
                    }
                }

                object result;
                tlit.TestValue(val, out result);
                return result;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Take the first N items from the argument, returning a list
            ///
            FunctionTable[Symbol.FromString("first")] = (Vector args) =>
            {
                if (args.Count < 1 || args.Count > 2 || args[0] == null)
                {
                    BraidRuntimeException("first: takes one or two non-null arguments: (first <list> [<number>]).");
                }

                int numberToTake = 1;
                if (args.Count == 2)
                {
                    numberToTake = ConvertToHelper<int>(args[1]);
                }

                if (numberToTake <= 0)
                {
                    return null;
                }

                bool was1 = numberToTake == 1;

                if (args[0] is string str)
                {
                    var slen = str.Length;

                    if (slen == 0)
                        return "";

                    if (numberToTake > slen)
                        numberToTake = slen;

                    return str.Substring(0, numberToTake);
                }

                if (was1 && args[0] is ISeq seq)
                    return seq.Car;

                s_Expr result = null;
                s_Expr end = null;
                foreach (var item in GetNonGenericEnumerableFrom(args[0]))
                {
                    if (was1)
                    {
                        return item;
                    }

                    if (result == null)
                    {
                        result = end = new s_Expr(item);
                    }
                    else
                    {
                        end = end.Add(item);
                    }

                    if (--numberToTake == 0)
                    {
                        break;
                    }
                }
                return result;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Take the first n items from the argument, returning a vector or a slice.
            ///
            FunctionTable[Symbol.FromString("take")] = (Vector args) =>
            {
                if (args.Count == 1)
                {
                    return curryFunction(Symbol.FromString("take"), args[0]);
                }

                if (args.Count != 2)
                {
                    BraidRuntimeException("take: takes one or two non-null arguments: (take <list> [<number>]).");
                }

                if (args[0] == null)
                {
                    return new Vector();
                }

                int numberToTake = ConvertToHelper<int>(args[1]);

                if (numberToTake == 0)
                {
                    return new Vector();
                }

                // Optimize for indexible collections
                if (args[0] is IList ilist)
                {
                    if (numberToTake < 0)
                    {
                        numberToTake = ilist.Count + numberToTake;
                        if (numberToTake <= 0)
                        {
                            return new Vector();
                        }
                    }

                    if (numberToTake >= ilist.Count)
                    {
                        return ilist;
                    }

                    return new Slice(ilist, 0, numberToTake);
                }

                var result = new Vector();

                if (args[0] is IEnumerable ie)
                {
                    if (numberToTake < 0)
                    {
                        int count = 0;
                        foreach (var _ in ie)
                        {
                            count++;
                        }

                        numberToTake = count + numberToTake;
                        if (numberToTake <= 0)
                        {
                            return new Vector();
                        }
                    }

                    foreach (var item in ie)
                    {
                        result.Add(item);
                        if (--numberToTake == 0)
                        {
                            break;
                        }
                    }

                    return result;
                }

                if (args[0] is IEnumerator ier)
                {
                    while (numberToTake-- > 0 && ier.MoveNext())
                    {
                        result.Add(ier.Current);
                    }
                    return result;
                }

                // Otherwise do it the hard way.
                foreach (var item in GetNonGenericEnumerableFrom(args[0]))
                {
                    result.Add(item);
                    if (--numberToTake == 0)
                    {
                        break;
                    }
                }
                return result;
            };

            //////////////////////////////////////////////////////////////////////
            ///
            /// Take elements until the arg matches or the predecate returns true
            ///
            FunctionTable[Symbol.FromString("take-until")] = (Vector args) =>
            {
                if (args.Count == 1)
                {
                    return curryFunction(Symbol.FromString("take-until"), args[0]);
                }

                if (args.Count != 2 || args[0] == null)
                {
                    BraidRuntimeException("take-until: takes one or two non-null arguments: (take-until <list> <lambda or value>]).");
                }

                if (args[0] == null)
                {
                    return new Vector();
                }

                return Utils.TakeWhileEnumerable(GetNonGenericEnumerableFrom(args[0]), args[1]);
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Take elements after the arg matches or the predecat return true
            ///
            FunctionTable[Symbol.FromString("take-after")] = (Vector args) =>
            {
                if (args.Count == 1)
                {
                    return curryFunction(Symbol.FromString("take-after"), args[0]);
                }

                if (args.Count != 2 || args[0] == null)
                {
                    BraidRuntimeException("take-after: takes one or two non-null arguments: (take-after <list> <lambda or value>).");
                }

                return Utils.TakeAfterEnumerable(GetNonGenericEnumerableFrom(args[0]), args[1]);
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Skip the first n items in a list or enumerable
            ///
            FunctionTable[Symbol.FromString("skip")] = (Vector args) =>
            {
                if (args.Count == 1)
                {
                    return curryFunction(Symbol.FromString("skip"), args[0]);
                }

                if (args.Count != 2 || args[0] == null || args[1] == null)
                {
                    BraidRuntimeException("skip: takes two mandatory non-null arguments: (skip <list> <number>).");
                }

                int numberToSkip = ConvertToHelper<int>(args[1]);
                var list = args[0];
                if (list == null || numberToSkip < 0)
                {
                    return new Vector();
                }

                if (list is IList ilist)
                {
                    var len = ilist.Count - numberToSkip;

                    if (len <= 0)
                        return new Vector();
                    return new Slice(ilist, numberToSkip, len);
                }

                return Utils.GetSkipEnumerable(GetNonGenericEnumerableFrom(args[0]), numberToSkip);
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Skip elements in an enumerable while the condition is true.
            ///
            FunctionTable[Symbol.FromString("skip-while")] = (Vector args) =>
            {
                if (args.Count == 1)
                {
                    return curryFunction(Symbol.FromString("skip-while"), args[0]);
                }

                if (args.Count != 2 || args[0] == null || args[1] == null)
                {
                    BraidRuntimeException("skip-while: takes two non-null arguments: (skip-while <list> <lambda>).");
                }

                Callable condition = args[1] as Callable;
                if (condition == null)
                {
                    BraidRuntimeException($"skip-while: the second argument must be a lambda, not {args[1]}");
                }

                if (args[0] == null)
                {
                    return new Vector();
                }

                return Utils.GetSkipWhileEnumerable(Braid.GetNonGenericEnumerableFrom(args[0]), condition);
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Return the last item or items in a list or enumerable. If a single item is
            /// to be returned, it is returned as a scalar rather than as a vector of 1 element.
            ///
            FunctionTable[Symbol.FromString("last")] = (Vector args) =>
            {
                if (args.Count < 1 || args.Count > 2)
                {
                    BraidRuntimeException("last: takes one argument: (last <list> [<count>]).");
                }

                if (args[0] == null)
                {
                    return null;
                }

                int num = 1;
                if (args.Count != 1)
                {
                    num = ConvertToHelper<int>(args[1]);
                }

                // If it's a vector, use indexing rather than enumeration
                if (args[0] is Vector vect)
                {
                    // a request for the last item returns a scalar. 
                    if (num == 1)
                    {
                        return vect[vect.Count - 1];
                    }

                    return new Slice(vect, vect.Count - num, num);
                }

                if (args[0] is string str)
                {
                    var slen = str.Length;
                    int index;

                    if (slen == 0)
                        return "";

                    if (num >= slen)
                        index = 0;
                    else
                        index = slen - num;

                    return str.Substring(index);
                }

                var buf = new Queue();
                foreach (var obj in GetNonGenericEnumerableFrom(args[0]))
                {
                    buf.Enqueue(obj);
                    if (buf.Count > num)
                    {
                        buf.Dequeue();
                    }
                }

                if (buf.Count == 0)
                    return null;

                if (num == 1)
                    return buf.Dequeue();

                return new Vector(buf);
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Reverse a list or enumerable returning a new list.
            ///
            FunctionTable[Symbol.FromString("reverse")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException("reverse: takes one non-null arguments: (reverse <list>).");
                }

                if (args[0] == null)
                {
                    return new Vector();
                }

                if (args[0] is string str)
                {
                    return string.Concat(str.Reverse());
                }

                // create a new vector then reverse in-place
                var result = new Vector(GetNonGenericEnumerableFrom(args[0]));
                result.Reverse();
                return result;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Iterate over a list, executing the body for each item. This function returns nil (as
            /// opposed to forall which returns all of the values.) The syntax is (foreach <var> <enumerable> <body> ...)
            /// The alternate for pipelines is 'each': (range 10 | each (fn n -> (println n)))
            ///
            SpecialForms[Symbol.FromString("foreach")] = (Vector args) =>
            {
                if (args.Count < 2)
                {
                    BraidRuntimeException("foreach: requires at least 2 arguments e.g. (foreach var collection ...); number provided: " + args.Count);
                }

                PSStackFrame callStack = Braid.CallStack;
                Symbol varsym = null;
                BraidVariable loopvar = null;
                List<Symbol> symsToBind = new List<Symbol>();
                if (args[0] is VectorLiteral vlit)
                {
                    foreach (var sym in vlit.ValueList)
                    {
                        varsym = sym as Symbol;
                        if (varsym == null)
                        {
                            BraidRuntimeException("the 'foreach' function requires a symbol or vector of " +
                                            $"symbols as its first argument; not '{sym}'.");
                        }

                        symsToBind.Add(varsym);
                    }
                }
                else
                {
                    varsym = args[0] as Symbol;

                    if (varsym == null)
                    {
                        BraidRuntimeException("the 'foreach' function requires a symbol or vector of " +
                                            $"symbols as its first argument; not '{args[0]}'.");
                    }

                    if (!varsym.CompoundSymbol)
                    {
                        loopvar = callStack.GetOrCreateLocalVar(varsym);
                    }
                    else
                    {
                        symsToBind.Add(varsym);
                    }
                }

                object exprval = BraidLang.Braid.Eval(args[1]);
                if (exprval == null)
                {
                    return null;
                }

                var enumerator = GetNonGenericEnumerableFrom(exprval).GetEnumerator();
                bool shouldBreak = false;
            outer:
                while (true)
                {
                    if (_stop)
                    {
                        break;
                    }

                    int symsBound = 0;
                    if (loopvar == null)
                    {
                        foreach (var sym in symsToBind)
                        {
                            // Bind all of the items on the list
                            if (enumerator.MoveNext())
                            {
                                if (sym.CompoundSymbol)
                                {
                                    MultipleAssignment(callStack, sym, enumerator.Current, ScopeType.Local);
                                }
                                else
                                {
                                    callStack.SetLocal(sym, enumerator.Current);
                                    // v.Value = enumerator.Current;
                                }
                                symsBound++;
                            }
                            else
                            {
                                // if we run out of items; for this iteration set
                                // the variables to null. We'll still execute the body
                                // one last time.
                                if (sym.CompoundSymbol)
                                {
                                    MultipleAssignment(callStack, sym, null, ScopeType.Local);
                                }
                                else
                                {
                                    callStack.SetLocal(sym, null);
                                }

                                shouldBreak = true;
                            }
                        }
                    }
                    else
                    {
                        if (enumerator.MoveNext())
                        {
                            loopvar.Value = enumerator.Current;
                            symsBound = 1;
                        }
                    }

                    // If no symbols were bound to a value, then break immediately
                    // otherwise process with partial success.
                    if (symsBound == 0)
                    {
                        break;
                    }

                    // Evaluate the body with these bindings                                
                    int index = 2;
                    while (index < args.Count)
                    {
                        var result = BraidLang.Braid.Eval(args[index++]);
                        if (result is BraidFlowControlOperation fco)
                        {
                            if (fco is BraidContinueOperation)
                            {
                                goto outer;
                            }
                            else if (fco is BraidBreakOperation breakOp)
                            {
                                if (breakOp.HasValue)
                                {
                                    return breakOp.BreakResult;
                                }

                                return null;
                            }
                            else if (fco is BraidReturnOperation retop)
                            {
                                return retop; //.ReturnValue;
                            }
                            else if (fco is BraidRecurOperation recur)
                            {
                                return recur;
                            }
                        }
                    }

                    // If we've run out of items to process then break 
                    if (shouldBreak)
                    {
                        break;
                    }
                }

                return null;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Iterate over a list, executing the body for each item. This function returns a
            /// vector composed of the non-null values produced when executing the last expression
            /// in the body. If the body is empty, then the result of this expression is null.
            ///
            SpecialForms[Symbol.FromString("forall")] = (Vector args) =>
            {
                if (args.Count < 2)
                {
                    BraidRuntimeException("forall: requires at least 2 arguments; the number provided was: " + args.Count);
                }

                var namedParameters = CallStack.NamedParameters;
                bool flatten = namedParameters != null && Braid.IsTrue(namedParameters["flatten"]);
                PSStackFrame callStack = Braid.CallStack;
                BraidVariable loopvar = null;
                Symbol varsym = null;
                List<Symbol> symsToBind = null;

                if (args[0] is VectorLiteral vlit)
                {
                    foreach (var sym in vlit.ValueList)
                    {
                        varsym = sym as Symbol;
                        if (varsym == null)
                        {
                            BraidRuntimeException("the 'forall' function requires a symbol or vector of " +
                                            $"symbols as its first argument; not '{sym}'.");
                        }

                        if (symsToBind == null)
                        {
                            symsToBind = new List<Symbol>();
                        }

                        symsToBind.Add(varsym);
                    }
                }
                else
                {
                    varsym = args[0] as Symbol;

                    if (varsym == null)
                    {
                        BraidRuntimeException("the 'forall' function requires a symbol or vector of " +
                                            $"symbols as its first argument; not '{args[0]}'.");
                    }

                    if (varsym.CompoundSymbol)
                    {
                        symsToBind = new List<Symbol>();
                        symsToBind.Add(varsym);
                    }
                    else
                    {
                        symsToBind = new List<Symbol>();
                        loopvar = callStack.GetOrCreateLocalVar(varsym);
                    }
                }

                // evaluate the expression to iterate over
                object exprval = BraidLang.Braid.Eval(args[1]);
                if (exprval == null)
                {
                    return null;
                }

                Vector result = new Vector();

                var enumerator = GetNonGenericEnumerableFrom(exprval).GetEnumerator();
                bool shouldBreak = false;
            outer:
                while (true)
                {
                    if (_stop)
                    {
                        break;
                    }

                    int symsBound = 0;
                    if (loopvar == null)
                    {
                        foreach (var sym in symsToBind)
                        {
                            // Bind all of the items on the list
                            if (enumerator.MoveNext())
                            {
                                if (sym.CompoundSymbol)
                                {
                                    MultipleAssignment(callStack, sym, enumerator.Current, ScopeType.Local);
                                }
                                else
                                {
                                    callStack.SetLocal(sym, enumerator.Current);
                                }
                                symsBound++;
                            }
                            else
                            {
                                // if we run out of items; for this iteration set
                                // the variables to null. We'll still execute the body
                                // one last time.
                                if (sym.CompoundSymbol)
                                {
                                    MultipleAssignment(callStack, sym, null, ScopeType.Local);
                                }
                                else
                                {
                                    callStack.SetLocal(sym, null);
                                }

                                shouldBreak = true;
                            }
                        }
                    }
                    else
                    {
                        if (enumerator.MoveNext())
                        {
                            loopvar.Value = enumerator.Current;
                            symsBound = 1;
                        }
                    }

                    // If no symbols were bound to a value, then break immediately
                    // otherwise process with partial success.
                    if (symsBound == 0)
                    {
                        break;
                    }

                    // Evaluate the body with these bindings                                
                    int index = 2;
                    object val = null;
                    while (index < args.Count)
                    {
                        val = BraidLang.Braid.Eval(args[index++]);
                        if (val is BraidFlowControlOperation fco)
                        {
                            if (fco is BraidContinueOperation)
                            {
                                goto outer;
                            }
                            else if (fco is BraidBreakOperation breakOp)
                            {
                                if (breakOp.HasValue)
                                {
                                    return breakOp.BreakResult;
                                }

                                return result;
                            }
                            else if (fco is BraidReturnOperation retop)
                            {
                                return retop;
                            }
                            else if (fco is BraidRecurOperation recur)
                            {
                                return recur;
                            }
                        }
                    }

                    // Don't include null in the result
                    if (val != null)
                    {
                        if (flatten && val is IEnumerable ienum && !(val is string))
                        {
                            foreach (var inner in ienum)
                            {
                                if (inner != null)
                                {
                                    result.Add(inner);
                                }
                            }
                        }
                        else
                        {
                            result.Add(val);
                        }
                    }

                    // If we've run out of items to process then break 
                    if (shouldBreak)
                    {
                        break;
                    }
                }

                return result;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Apply a lambda to each element in the argument list in parallel then return the
            /// results of each task as it completes.
            ///
            FunctionTable[Symbol.FromString("map-parallel")] = (Vector args) =>
            {
                if (args.Count == 1)
                {
                    return curryFunction(Symbol.FromString("map-parallel"), args[0]);
                }

                if (args.Count != 2 || args[1] == null)
                {
                    BraidRuntimeException("map-parallel: requires at least 2 arguments; actual number provided was: " + args.Count);
                }

                object exprval = args[0];
                if (exprval == null)
                {
                    return null;
                }

                List<Task<object>> tasks = new List<Task<object>>();

                // Start all the tasks...
                switch (args[1])
                {
                    /* BUGBUGBUG - disable for now - the environment isn't being handled properly leading to errors.

                                        case UserFunction lambda:
                                            var ieo = GetEnumerableFrom(exprval).AsQueryable<object>();
                                            var pe = ieo.AsParallel().Select<object, object>((Func<object, object>)CreateDelegate(typeof(Func<object, object>), lambda));
                                            return new Vector(pe);

                                        case PatternFunction pattern:
                                            return new Vector(GetEnumerableFrom(exprval)
                                                        .AsQueryable<object>()
                                                        .AsParallel()
                                                        .Select<object, object>((Func<object, object>)CreateDelegate(typeof(Func<object, object>), pattern)));
                                            break;
                    BUGBUGBUG */
                    case Callable call:
                        foreach (var item in GetNonGenericEnumerableFrom(exprval))
                        {
                            if (_stop)
                            {
                                break;
                            }

                            call.Environment = (PSStackFrame)Braid.CallStack.Fork();
                            tasks.Add(ExpressionToTask(call, item));
                        }
                        break;

                    default:
                        BraidRuntimeException("map-parallel: the second argument must be a lambda to execute.");
                        break;
                }

                Vector result = new Vector(tasks.Count);

                // Now get all of the results...
                foreach (var task in tasks)
                {
                    if (_stop)
                    {
                        break;
                    }

                    result.Add(task.Result);
                }

                return result;
            };

            /////////////////////////////////////////////////////////////////////
            //
            // A function implementing if-expression semantics.
            //
            SpecialForms[Symbol.FromString("if")] = (Vector args) =>
            {
                if (args.Count < 2 || args.Count > 3)
                {
                    BraidRuntimeException("if: requires 2 or 3 arguments; not " + args.Count);
                }

                object cond = args[0];
                object ifPart = args[1];
                object elsePart = args.Count == 3 ? args[2] : null;

                if (Braid.IsTrue(Braid.Eval(cond)))
                {
                    return Braid.Eval(ifPart);
                }

                if (elsePart != null)
                {
                    return Braid.Eval(elsePart);
                }

                return null;
            };

            /////////////////////////////////////////////////////////////////////
            //
            // A function implementing if-not expression semantics.
            //
            SpecialForms[Symbol.FromString("if-not")] = (Vector args) =>
            {
                if (args.Count < 2 || args.Count > 3)
                {
                    BraidRuntimeException("if-not: requires 2 or 3 arguments; not " + args.Count);
                }

                object cond = args[0];
                object ifPart = args[1];
                object elsePart = args.Count == 3 ? args[2] : null;

                if (!Braid.IsTrue(Braid.Eval(cond)))
                {
                    return Braid.Eval(ifPart);
                }
                else if (elsePart != null)
                {
                    return Braid.Eval(elsePart);
                }

                return null;
            };


            /////////////////////////////////////////////////////////////////////
            ///
            /// A function implementing while-statement semantics.
            ///
            SpecialForms[Symbol.FromString("while")] = (Vector args) =>
            {
                if (args.Count < 1)
                {
                    BraidRuntimeException($"The 'while' function requires at least 1 argument; not {args?.Count} e.g. (while <cond> [<body...>]).");
                }

                object cond = args[0];
                int argsCount = args.Count;
                object lastResult = null;
            outer: while (Braid.IsTrue(Braid.Eval(cond)))
                {
                    int index = 1;
                    if (_stop) { return null; }

                    while (index < argsCount)
                    {
                        var result = Braid.Eval(args[index++]);
                        if (result is BraidFlowControlOperation fco)
                        {
                            switch (fco)
                            {
                                case BraidContinueOperation co:
                                    goto outer;

                                case BraidBreakOperation breakOp:
                                    if (breakOp.HasValue)
                                    {
                                        return breakOp.BreakResult;
                                    }

                                    return lastResult;

                                case BraidRecurOperation recur:
                                    return recur;

                                case BraidReturnOperation retop:
                                    return retop;
                            }
                        }

                        lastResult = result;
                    }
                }

                return lastResult;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// A function implementing while-all statement semantics.
            ///
            SpecialForms[Symbol.FromString("while-all")] = (Vector args) =>
            {
                if (args.Count < 1)
                {
                    BraidRuntimeException($"The 'while' function requires at least 1 argument; not {args?.Count} e.g. (while <cond> [<body...>]).");
                }

                object cond = args[0];
                int argsCount = args.Count;
                object lastResult = null;
                Vector results = new Vector();

            outer: while (Braid.IsTrue(Braid.Eval(cond)))
                {
                    int index = 1;
                    if (_stop) { return null; }

                    object result = null;
                    while (index < argsCount)
                    {
                        result = Braid.Eval(args[index++]);
                        if (result is BraidFlowControlOperation fco)
                        {
                            switch (fco)
                            {
                                case BraidContinueOperation co:
                                    goto outer;

                                case BraidBreakOperation breakOp:
                                    if (breakOp.HasValue)
                                    {
                                        return breakOp.BreakResult;
                                    }

                                    return lastResult;

                                case BraidRecurOperation recur:
                                    return recur;

                                case BraidReturnOperation retop:
                                    return retop;
                            }
                        }
                    }

                    results.Insert(results.Count, result);
                }

                return results;
            };


            /////////////////////////////////////////////////////////////////////
            ///
            /// Repeat evaluation of the body the specified number of times
            ///
            SpecialForms[Symbol.FromString("repeat")] = (Vector args) =>
            {
                if (args.Count == 1)
                {
                    return curryFunction(Symbol.FromString("repeat"), args[0]);
                }

                if (args.Count < 2)
                {
                    BraidRuntimeException("repeat: requires at least 2 arguments; not " + args?.Count);
                }

                int count = ConvertToHelper<int>(Eval(args[0]));

            outer:
                while (count-- > 0)
                {
                    if (_stop)
                    {
                        break;
                    }

                    int index = 1;
                    while (index < args.Count)
                    {
                        var result = Braid.Eval(args[index++]);
                        if (result is BraidFlowControlOperation fco)
                        {
                            if (fco is BraidContinueOperation)
                            {
                                goto outer;
                            }
                            else if (fco is BraidBreakOperation breakOp)
                            {
                                if (breakOp.HasValue)
                                {
                                    return breakOp.BreakResult;
                                }

                                return null;
                            }
                            else if (fco is BraidRecurOperation recur)
                            {
                                return recur;
                            }
                            else if (fco is BraidReturnOperation retop)
                            {
                                return retop; // .ReturnValue;
                            }
                        }
                    }
                }
                return null;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Repeatedly evaluate the body the specified number of times, returning all of the
            /// results.
            ///
            SpecialForms[Symbol.FromString("repeat-all")] = (Vector args) =>
            {
                if (args.Count == 1)
                {
                    return curryFunction(Symbol.FromString("repeat-all"), args[0]);
                }

                if (args.Count < 2)
                {
                    BraidRuntimeException("repeat-all: requires at least 2 arguments; not " + args?.Count);
                }

                int count = ConvertToHelper<int>(Eval(args[0]));

                Vector result = new Vector(count);

            outer:
                while (count-- > 0)
                {
                    if (_stop)
                    {
                        break;
                    }

                    int index = 1;
                    object val = null;
                    while (index < args.Count)
                    {
                        val = Braid.Eval(args[index++]);
                        if (val is BraidFlowControlOperation fco)
                        {
                            if (fco is BraidContinueOperation)
                            {
                                goto outer;
                            }
                            else if (fco is BraidBreakOperation breakOp)
                            {
                                if (breakOp.HasValue)
                                {
                                    return breakOp.BreakResult;
                                }

                                return null;
                            }
                            else if (fco is BraidRecurOperation recur)
                            {
                                return recur;
                            }
                            else if (fco is BraidReturnOperation retop)
                            {
                                return retop;
                            }
                        }
                    }

                    result.Add(val);
                }

                if (result.Count == 0)
                {
                    return null;
                }

                return result;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Do a breadth-first search: (breadth-search start goal moveGenerator)
            /// 
            FunctionTable[Symbol.FromString("breadth-search")] = (Vector args) =>
            {
                if (args.Count != 3 || args[0] == null || args[1] == null || args[2] == null)
                {
                    BraidRuntimeException("The 'breadth-search' function requires 3 non-null arguments: (breadth-search start goalOrFn moveGenerator).");
                }

                bool matched = false;
                var start = args[0];
                var moveGen = GetFunc(CallStack, args[2]) as IInvokeableValue;
                if (moveGen == null)
                {
                    BraidRuntimeException("The third argument to 'breadth-search' must be a function; not '{argv[2]}'.");
                }

                Vector result = new Vector();

                var visited = new HashSet<object>(new ObjectComparer());
                var queue = new Queue<s_Expr>();
                queue.Enqueue(new s_Expr(start));
                var argv = new Vector { null };
                s_Expr path = null;

                if (args[1] is Callable goalFn)
                {
                    while (queue.Count > 0)
                    {
                        path = queue.Dequeue();

                        argv[0] = path.Car;
                        if (visited.Contains(argv[0]))
                        {
                            continue;
                        }

                        visited.Add(argv[0]);

                        if (Braid.IsTrue(goalFn.Invoke(argv)))
                        {
                            matched = true;
                            break;
                        }
                        else
                        {
                            foreach (var move in GetEnumerableFrom(moveGen.Invoke(argv)))
                            {
                                queue.Enqueue(new s_Expr(move, path));
                            }
                        }
                    }
                }
                else
                {
                    var goal = args[1];
                    while (queue.Count > 0)
                    {
                        path = queue.Dequeue();

                        argv[0] = path.Car;
                        if (visited.Contains(argv[0]))
                        {
                            continue;
                        }

                        visited.Add(argv[0]);

                        if (Braid.CompareItems(argv[0], goal))
                        {
                            matched = true;
                            break;
                        }
                        else
                        {
                            foreach (var move in GetEnumerableFrom(moveGen.Invoke(argv)))
                            {
                                queue.Enqueue(new s_Expr(move, path));
                            }
                        }
                    }
                }

                if (matched)
                {
                    var vpath = new Vector(path.GetEnumerable());
                    vpath.Reverse();
                    return vpath;
                }
                else
                {
                    return null;
                }
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Implementation of the 'cond' function.
            /// 
            SpecialForms[Symbol.FromString("cond")] = (Vector args) =>
            {
                if (args.Count % 2 != 0)
                {
                    BraidRuntimeException(
                        "cond: requires an even number of arguments: (cond (condition1) (action1) (condition2) (action2) ...).");
                }

                bool executeAction = false;
                bool condition = true;
                for (var index = 0; index < args.Count; index++)
                {
                    var item = args[index];
                    if (condition)
                    {
                        if (item != null)
                        {
                            executeAction = Braid.IsTrue(Braid.Eval(item, false));
                        }
                        condition = false;
                    }
                    else
                    {
                        if (executeAction)
                        {
                            return Braid.Eval(item, false);
                        }
                        condition = true;
                    }
                }
                return null;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Macro to do pattern matching in the body of a function similar to a switch expression
            ///
            CallStack.Const(Symbol.sym_matchp, new Macro(Symbol.sym_matchp.Value, (Vector args) =>
            {
                Vector vexpr = new Vector();
                int index = 0;
                while (index < args.Count && !Symbol.sym_pipe.Equals(args[index]))
                {
                    vexpr.Add(args[index++]);
                }

                if (index == args.Count)
                {
                    BraidRuntimeException($"the matchp function requires arguments followed by a body " +
                                        "composed of pattern rules e.g. (matchp 1 2 | x y -> (+ x y))");
                }

                // Parse the pattern.
                var matcher = parsePattern(Symbol.sym_matchp.Value, args, index, true);

                // matchp executes in the current scope
                matcher.IsFunction = false;

                return new s_Expr(matcher, s_Expr.FromEnumerable(vexpr));
            }));

            /////////////////////////////////////////////////////////////////////
            ///
            /// Time the execution of an expression
            /// 
            SpecialForms[Symbol.FromString("time")] = (Vector args) =>
            {
                if (args.Count < 1 || args.Count > 2)
                {
                    BraidRuntimeException($"time: requires 1 or 2 arguments; not {args.Count} e.g. (time [numReps] (fib 20))");
                }

                object script = null;
                int numReps = 1;
                if (args.Count == 1)
                {
                    script = args[0];
                }
                else
                {
                    numReps = Braid.ConvertToHelper<int>(Eval(args[0], true, true));
                    script = args[1];
                }

                object result = null;

                var sw = new System.Diagnostics.Stopwatch();
                List<double> samples = new List<double>(numReps);
                for (int i = 0; i < numReps; i++)
                {
                    if (Braid._stop)
                    {
                        break;
                    }

                    sw.Start();
                    result = Braid.Eval(script);
                    sw.Stop();
                    samples.Add(sw.Elapsed.TotalMilliseconds);
                    sw.Reset();
                }

                if (samples.Count > 1)
                {
                    if (samples.Count >= 100)
                    {
                        samples.Sort();
                        samples = samples.GetRange(10, samples.Count - 10);
                    }

                    double totaltime = samples.Sum();
                    double averagetime = totaltime / samples.Count;

                    Console.WriteLine($"Total time: {Math.Round(totaltime, 6)} Average time: {Math.Round(averagetime, 6)} ms.");
                    return null;
                }
                else
                {
                    Console.WriteLine($"Elapsed time: {Math.Round(samples[0], 6)} ms.");
                }

                // If an iteration count has been specified, just return null.
                if (args.Count > 1)
                {
                    return null;
                }

                return result;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Just discards the argument values.
            /// 
            FunctionTable[Symbol.FromString("void")] = (Vector args) =>
            {
                return null;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// If the arg is IEnumerable, drain it, otherwise just discard the values
            /// 
            FunctionTable[Symbol.FromString("drain")] = (Vector args) =>
            {
                foreach (var arg in args)
                {
                    if (arg is IEnumerable ienum)
                    {
                        foreach (var ignored in ienum)
                        {
                            // ignore
                        }
                    }
                }

                return null;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Return a collection of random integers.
            /// Examples:
            ///     (random 10)     ; returns 10 numbers between 0 10
            ///     (random 5 10)   ; returns 5 numbers between 5 and 10
            ///     (random 1 5 10) ; returns 1 number between 5 and 10
            ///
            FunctionTable[Symbol.FromString("random")] = (Vector args) =>
            {
                int min = 0;
                int max = int.MaxValue;
                int number = 1;

                if (args.Count == 1)
                {
                    number = ConvertToHelper<int>(args[0]);
                    max = number;
                }
                else if (args.Count == 2)
                {
                    min = ConvertToHelper<int>(args[0]);
                    max = ConvertToHelper<int>(args[1]);
                    number = max - min;
                }
                else if (args.Count == 3)
                {
                    number = ConvertToHelper<int>(args[0]);
                    min = ConvertToHelper<int>(args[1]);
                    max = ConvertToHelper<int>(args[2]);
                }
                else
                {
                    BraidRuntimeException(
                        $"random: invalid number of args: {args.Count}; this function takes 1-3 arguments");
                }

                if (number <= 0)
                {
                    BraidRuntimeException("random: the number of numbers to generate must be greater than 0");
                }

                if (number == 1)
                {
                    return _rnd.Next(min, max);
                }

                var result = new Vector(number);
                while (number-- > 0)
                {
                    if (_stop)
                    {
                        _stop = false;
                        BraidRuntimeException("Braid is stopping because cancel was pressed.");
                    }

                    int n = _rnd.Next(min, max);

                    result.Add(n);
                }

                return result;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Return an enumerable of integers with optional bounds and increment.
            /// If there is only one argument and it's a collection, return an
            /// enumerable that covers the range of the collection.
            /// 
            FunctionTable[Symbol.FromString("range")] = (Vector args) =>
            {
                int lower = 0;
                int upper = 0;
                int step = 1;
                bool empty = false;  // used with empty collections

                switch (args.Count)
                {
                    case 1:
                        switch (args[0])
                        {
                            case IDictionary _dict:
                                BraidRuntimeException("range: the 'range' function cannot be applied to a dictionary.");
                                break;

                            //BUGBUGBUG - consider (range "123") will iterate 3 times instead of converting the string to integer 123. Is this right?
                            case string str:
                                lower = 0;
                                if ((upper = str.Length - 1) < 0)
                                {
                                    upper = 0;
                                }
                                if (lower == upper)
                                {
                                    empty = true;
                                }
                                break;

                            case ICollection col:
                                lower = 0;
                                if ((upper = col.Count - 1) < 0)
                                {
                                    upper = 0;
                                }
                                if (lower == upper)
                                {
                                    empty = true;
                                }
                                break;

                            default:
                                lower = 1;
                                upper = ConvertToHelper<int>(args[0]);
                                break;
                        }
                        break;

                    case 2:
                        lower = ConvertToHelper<int>(args[0]);
                        upper = ConvertToHelper<int>(args[1]);
                        break;

                    case 3:
                        lower = ConvertToHelper<int>(args[0]);
                        upper = ConvertToHelper<int>(args[1]);
                        step = Math.Abs(ConvertToHelper<int>(args[2]));
                        break;

                    default:
                        BraidRuntimeException(
                            $"range: invalid number of arguments; this function takes 1-3 arguments, not {args.Count}. e.g. (range [<lower>] <upper> [<increment>]");
                        break;
                }

                return new RangeList(lower, upper, step, empty);
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Filter a list using the specified lambda/function as a predicate
            ///
            /// BUGBUGBUG This whole function is a mess and needs to be cleaned up.
            SpecialForms[Symbol.FromString("where")] =
            SpecialForms[Symbol.FromString("filter")] = (Vector args) =>
            {
                if (args.Count == 1)
                {
                    return curryFunction(Symbol.FromString("filter"), args[0]);
                }

                if (args.Count != 2)
                {
                    BraidRuntimeException($"filter: requires 2 arguments; not {args.Count} e.g. (filter <data> <filterFunction>)");
                }

                // If there's no data; just return.
                var data = Eval(args[0], true, true);
                if (data == null)
                {
                    return null;
                }

                var callStack = Braid.CallStack;
                var namedParameters = callStack.NamedParameters;
                bool not = false;
                if (namedParameters != null)
                {
                    foreach (var key in namedParameters.Keys)
                    {
                        if (key.Equals("not", StringComparison.OrdinalIgnoreCase))
                        {
                            not = Braid.IsTrue(namedParameters["not"]);
                            break;
                        }

                        BraidRuntimeException($"Named parameter '-{key}' is not valid for the 'filter' function, " +
                                            "the only named parameter for 'filter' is '-not'");
                    }
                }

                object predicate = null;
                bool donteval = false;
                Func<Vector, object> func = null;
                if (args[1] is FunctionLiteral lamlit)
                {
                    predicate = lamlit.Value;
                    func = ((Callable)predicate).FuncToCall;
                }
                else
                {
                    if (args[1] is Symbol sym)
                    {
                        predicate = callStack.GetValue(sym);
                        // Since we've evaluated the argument once, indicate that it shouldn't be done later on
                        donteval = true;
                    }
                    else
                    {
                        predicate = args[1];
                    }

                    if (predicate is Regex pattern)
                    {
                        Func<Vector, object> regexFunc = (Vector matchargs) =>
                         {
                             if (matchargs != null && matchargs[0] != null)
                                 return pattern.IsMatch(matchargs[0].ToString());
                             else
                                 return false;
                         };

                        func = regexFunc;
                    }
                    else if (predicate is Type || predicate is TypeLiteral)
                    {
                        Type type;
                        if (args[1] is TypeLiteral tlit)
                        {
                            type = (Type)tlit.Value;
                        }
                        else
                        {
                            type = (Type)predicate;
                        }

                        Func<Vector, object> typeComparer = (Vector matchargs) =>
                        {
                            if (matchargs != null && matchargs[0] != null)
                            {
                                object val = matchargs[0];
                                Type valtype;
                                if (val is Type t)
                                    valtype = t;
                                else
                                    valtype = val.GetType();

                                return type.IsAssignableFrom(valtype);
                            }
                            else
                            {
                                return false;
                            }
                        };

                        func = typeComparer;
                    }
                    else if (args[1] is s_Expr sexpr)
                    {
                        if (sexpr.IsLambda)
                        {
                            func = funargs =>
                            {
                                var cond = new s_Expr(sexpr, new s_Expr(funargs[0]));
                                var evalResult = Eval(cond, true, true);
                                return evalResult;
                            };
                        }
                        else
                        {
                            if (donteval)
                            {
                                func = (Func<Vector, object>)GetFunc(callStack, predicate);
                            }
                            else
                            {
                                var fresult = GetFunc(callStack, Eval(predicate));
                                if (fresult == null)
                                {
                                    BraidRuntimeException($"filter: no predicate function was found corresponding to '{predicate}'.");
                                }

                                // BUGBUGBUG either everything gets wrapped in Callable or this needs to expand a bunch.
                                if (typeof(Callable).IsAssignableFrom(fresult.GetType()))
                                {
                                    func = ((Callable)fresult).FuncToCall;
                                }
                                else
                                {
                                    BraidRuntimeException($"filter: the predicate argument '{fresult}' doesn't implement " +
                                                        "the Callable interface and can't be used as a 'filter' predicate.");
                                }
                            }
                        }
                    }
                    else if (predicate is KeywordLiteral klit)
                    {
                        func = klit.FuncToCall;
                    }
                    else if (predicate is DictionaryLiteral dlit)
                    {
                        var ppe = new PropertyPatternElement(dlit);
                        func = funargs =>
                            {
                                int consumed;
                                return ppe.DoMatch(CallStack, funargs, 0, out consumed) == MatchElementResult.Matched;
                            };
                    }
                    else if (predicate is IInvokeableValue lam)
                    {
                        func = lam.FuncToCall;
                    }
                    else if (predicate is System.Func<BraidLang.Vector, System.Object> justfunc)
                    {
                        func = justfunc;
                    }
                }

                if (func == null)
                {
                    func = (Vector cmpargs) => (cmpargs.Count == 1) && Braid.CompareItems(cmpargs[0], predicate);
                }

                var argVect = new Vector { null };

                // Otherwise input is a collection so return a collection
                var result = new Vector();

                foreach (var item in GetNonGenericEnumerableFrom(data))
                {
                    if (_stop)
                    {
                        break;
                    }

                    try
                    {
                        argVect[0] = item;
                        object funcResult = func(argVect);
                        if (funcResult is BraidBreakOperation breakOp)
                        {
                            if (breakOp.HasValue)
                            {
                                return breakOp.BreakResult;
                            }

                            result.Add(item);
                            break;
                        }
                        else if (funcResult is BraidContinueOperation)
                        {
                            continue;
                        }

                        if (Braid.IsTrue(funcResult) != not)
                        {
                            result.Add(item);
                        }
                    }
                    catch (BraidUserException)
                    {
                        throw;
                    }
                    catch (Exception e)
                    {
                        System.Console.WriteLine("Exeception occurred filtering '{0}'", item); //BUGBUGBUGBUGBUGBUGBUG
                        BraidRuntimeException($"Exception occurred using 'filter' {e.Message}", e);
                    }
                }

                // If the vector is empty, return null instead of the empty vector.
                if (result.Count == 0)
                    return null;
                return result;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Lazy version of filter
            ///
            SpecialForms[Symbol.FromString("lazy-filter")] = (Vector args) =>
            {
                if (args.Count == 1)
                {
                    return curryFunction(Symbol.FromString("lazy-filter"), args[0]);
                }
                if (args.Count != 2)
                {
                    BraidRuntimeException($"lazy-filter: requires 2 arguments; not {args.Count} e.g. (lazy-filter data <condLambda>)");
                }

                var data = args[0];
                if (data is ValueLiteral blit)
                {
                    data = blit.Value;
                }
                else
                {
                    if (!(data is IEnumerable))
                    {
                        data = Eval(args[0], true, true);
                    }
                }

                // If theres no data; just return.
                if (data == null)
                {
                    return null;
                }

                var callStack = Braid.CallStack;
                var namedParameters = callStack.NamedParameters;
                bool not = namedParameters != null ? Braid.IsTrue(namedParameters["not"]) : false;

                object predicate = null;
                bool donteval = false;
                if (args[1] is Symbol sym)
                {
                    predicate = callStack.GetValue(sym);
                    // Since we've eval'ed the argument once, indicate that it shouldn't be done later on
                    donteval = true;
                }
                else
                {
                    predicate = args[1];
                }

                FunctionType ftype;
                string funcname;
                object func;

                if (predicate is Regex pattern)
                {
                    Func<Vector, object> regexFunc = (Vector matchargs) =>
                    {
                        if (matchargs != null && matchargs[0] != null)
                            return pattern.IsMatch(matchargs[0].ToString());
                        else
                            return false;
                    };
                    func = new Function("regex-comparer", regexFunc);
                }
                else if (predicate is Type || predicate is TypeLiteral)
                {
                    Type type;
                    if (args[1] is TypeLiteral tlit)
                    {
                        type = (Type)tlit.Value;
                    }
                    else
                    {
                        type = (Type)predicate;
                    }

                    Func<Vector, object> typeComparer = (Vector matchargs) =>
                    {
                        if (matchargs != null && matchargs[0] != null)
                        {
                            object val = matchargs[0];
                            if (val is PSObject pso)
                            {
                                val = pso.BaseObject;
                            }

                            Type valtype;
                            if (val is Type t)
                                valtype = t;
                            else
                                valtype = val.GetType();

                            return type.IsAssignableFrom(valtype);
                        }
                        else
                        {
                            return false;
                        }
                    };

                    func = new Function("type-comparer", typeComparer);
                }
                else if (predicate is s_Expr sexpr)
                {
                    if (sexpr.IsLambda)
                    {
                        func = Eval(sexpr, true, true);
                    }
                    else
                    {
                        if (donteval)
                            func = GetFunc(callStack, predicate, out ftype, out funcname);
                        else
                            func = GetFunc(callStack, Eval(predicate, true, true), out ftype, out funcname);
                    }
                }
                else if (predicate is DictionaryLiteral dlit)
                {
                    var ppe = new PropertyPatternElement(dlit);
                    Func<Vector, object> matcher = funargs =>
                    {
                        int consumed;
                        return ppe.DoMatch(CallStack, funargs, 0, out consumed) == MatchElementResult.Matched;
                    };
                    func = new Function("matcher", matcher);

                }
                else
                {
                    func = GetFunc(callStack, predicate, out ftype, out funcname);
                }

                if (func is IInvokeableValue invokeable)
                {
                    return new BraidFilterIterator(invokeable, not, GetNonGenericEnumerableFrom(data));
                }

                BraidRuntimeException(
                    $"lazy-filter: the second argument to 'lazy-filter' must resolve to a function; not '{args[1]}'");
                return null;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// (incr n) is equivalent to ++$n in PowerShell.
            ///
            SpecialForms[Symbol.FromString("incr")] = (Vector args) =>
            {
                int ac = 1;
                if ((ac = args.Count) < 1 || ac > 2 || args[0] == null)
                {
                    BraidRuntimeException($"incr: requires 1 or 2 argument; not {args.Count}; eg. (incr varname [incrValue])");
                }

                dynamic increment = (ac == 2) ? Eval(args[1]) : 1;
                dynamic val = null;

                try
                {
                    // Handle things like (incr %0) 
                    if (args[0] is ArgIndexLiteral ai)
                    {
                        val = ai.Value;
                        ai.Value = val += increment;
                        return val;
                    }

                    Symbol varsym = args[0] as Symbol;
                    if (varsym == null)
                    {
                        varsym = Symbol.FromString(args[0].ToString());
                    }

                    PSStackFrame callStack = Braid.CallStack;
                    BraidVariable targetVar = callStack.GetVariable(varsym);

                    // var doesn't exist so create and initialize it.
                    if (targetVar == null)
                    {
                        callStack.SetLocal(varsym, increment);
                        return increment;
                    }

                    val = targetVar.Value;
                    if (val == null)
                    {
                        val = 0;
                    }

                    if (val is int ival1 && increment is int ival2)
                    {
                        try
                        {
                            targetVar.Value = val = BoxInt(checked(ival1 + ival2));
                            return val;
                        }
                        catch
                        {
                        }
                    }

                    targetVar.Value = val = val + increment;
                    return val;
                }
                catch (Microsoft.CSharp.RuntimeBinder.RuntimeBinderException rbe)
                {
                    BraidRuntimeException($"Function 'incr' failed adding ({Truncate(val)}) and ({Truncate(increment)}) : {rbe.Message}", rbe);
                    return null;
                }
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// (pincr n) - post increment is equivalent to $n++ in PowerShell.
            ///
            SpecialForms[Symbol.FromString("pincr")] = (Vector args) =>
            {
                int ac = 1;
                if ((ac = args.Count) < 1 || ac > 2 || args[0] == null)
                {
                    BraidRuntimeException($"incr: requires 1 or 2 argument; not {args.Count}; eg. (incr varname [incrValue])");
                }

                dynamic increment = (ac == 2) ? Eval(args[1]) : 1;
                dynamic val = null;
                dynamic origVal = null;

                try
                {
                    // Handle things like (incr %0) 
                    if (args[0] is ArgIndexLiteral ai)
                    {
                        origVal = val = ai.Value;
                        ai.Value = val += increment;
                        return origVal;
                    }

                    if (!(args[0] is Symbol varsym))
                    {
                        varsym = Symbol.FromString(args[0].ToString());
                    }

                    PSStackFrame callStack = Braid.CallStack;
                    BraidVariable targetVar = callStack.GetVariable(varsym);

                    // var doesn't exist so create and initialize it.
                    if (targetVar == null)
                    {
                        callStack.SetLocal(varsym, increment);
                        return 0;
                    }

                    val = targetVar.Value;
                    if (val == null)
                    {
                        val = 0;
                    }

                    if (val is int ival1 && increment is int ival2)
                    {
                        try
                        {
                            targetVar.Value = BoxInt(checked(ival1 + ival2));
                            return val;
                        }
                        catch
                        {
                        }
                    }

                    targetVar.Value = val + increment;
                    return val;
                }
                catch (Microsoft.CSharp.RuntimeBinder.RuntimeBinderException rbe)
                {
                    BraidRuntimeException($"Function 'incr' failed adding ({Truncate(val)}) and ({Truncate(increment)}) : {rbe.Message}", rbe);
                    return null;
                }
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Increment a number.
            /// 
            FunctionTable[Symbol.FromString("++")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException($"++: requires 1 integer argument; not {args.Count}");
                }

                dynamic val = args[0];
                if (val == null)
                {
                    val = 0;
                }

                return val + 1;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Decrement a number
            ///
            FunctionTable[Symbol.FromString("--")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException($"--: requires 1 integer argument; not {args.Count}");
                }

                dynamic val = args[0];
                return val - 1;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// (decr n) is equivalent to --$n in PowerShell
            ///
            SpecialForms[Symbol.FromString("decr")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException($"decr: requires exactly 1 argument; not {args.Count}");
                }

                dynamic value;
                if (args[0] is ArgIndexLiteral ai)
                {
                    value = ai.Value;
                    value--;
                    ai.Value = value;
                    return value;
                }

                if (!(args[0] is Symbol varsym))
                {
                    varsym = Symbol.FromString(args[0].ToString());
                }
                // at this point, varsym will never be null

                BraidVariable currentVar = CallStack.GetVariable(varsym);
                if (currentVar != null)
                {
                    if ((value = currentVar.Value) == null)
                    {
                        value = 0;
                    }

                    value--;
                    currentVar.Value = value;
                }
                else
                {
                    value = -1;
                    CallStack.Set(varsym, value);
                }

                return value;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// (pdecr n) (post decrement) is equivalent to $n-- in PowerShell
            ///
            SpecialForms[Symbol.FromString("pdecr")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException($"pdecr: requires 1 argument; not {args.Count}");
                }

                if (args[0] is ArgIndexLiteral ai)
                {
                    var cval = ConvertToHelper<int>(ai.Value);
                    ai.Value = checked(cval - 1);
                    return cval;
                }

                Symbol varsym = args[0] as Symbol;
                if (varsym == null)
                {
                    varsym = Symbol.FromString(args[0].ToString());
                }

                BraidVariable currentVar = CallStack.GetVariable(varsym);
                int currentValue = 0;
                if (currentVar == null)
                {
                    currentValue = 0;
                }
                else
                {
                    currentValue = ConvertToHelper<int>(currentVar.Value);
                }

                if (currentVar != null)
                {
                    currentVar.Value = currentValue - 1;
                }
                else
                {
                    CallStack.Set(varsym, currentValue - 1);
                }

                return currentValue;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Returns it's arguments as a list.
            ///
            FunctionTable[Symbol.FromString("list")] = (Vector args) =>
            {
                return s_Expr.FromEnumerable(args);
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Split an enumerable based on a predicate
            ///
            FunctionTable[Symbol.FromString("list/split")] = (Vector args) =>
            {
                if (args.Count != 2)
                {
                    BraidRuntimeException($"The 'list/split' function requires 2 arguments: (list/split <list> <value or predicate>).");
                }

                if (args[0] == null)
                {
                    return new Vector { new Vector(), new Vector() };
                }

                object matchValue = null;
                Callable predicate = null;
                Func<Vector, Object> fpredicate = null;
                if (args[1] is Callable c)
                {
                    predicate = c;
                }
                else if (args[1] is Func<Vector, Object> f)
                {
                    fpredicate = f;
                }
                else
                {
                    matchValue = args[1];
                }

                Vector res1 = new Vector();
                Vector res2 = new Vector();

                if (predicate != null)
                {
                    Vector pargs = new Vector { null };

                    foreach (object item in GetNonGenericEnumerableFrom(args[0]))
                    {
                        pargs[0] = item;
                        if (Braid.IsTrue(predicate.Invoke(pargs)))
                        {
                            res1.Add(item);
                        }
                        else
                        {
                            res2.Add(item);
                        }
                    }
                }
                else if (fpredicate != null)
                {
                    Vector pargs = new Vector { null };

                    foreach (object item in GetNonGenericEnumerableFrom(args[0]))
                    {
                        pargs[0] = item;
                        if (Braid.IsTrue(fpredicate.Invoke(pargs)))
                        {
                            res1.Add(item);
                        }
                        else
                        {
                            res2.Add(item);
                        }
                    }
                }
                else
                {
                    bool hitSplitVal = false;
                    foreach (object item in GetNonGenericEnumerableFrom(args[0]))
                    {
                        if (Braid.CompareItems(item, matchValue))
                        {
                            hitSplitVal = true;
                            continue;
                        }

                        if (hitSplitVal)
                        {
                            res2.Add(item);
                        }
                        else
                        {
                            res1.Add(item);
                        }
                    }
                }

                return new Vector { res1, res2 };
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Partition an enumerable based into segments of the specified size
            ///
            FunctionTable[Symbol.FromString("list/partition")] = (Vector args) =>
            {
                if (args.Count != 2)
                {
                    BraidRuntimeException($"The 'list/partition' function requires 2 arguments: (list/split <list> <segmentSize>).");
                }

                var res = new Vector();
                var seg = new Vector();

                var list = GetNonGenericEnumerableFrom(args[0]);
                if (list == null)
                {
                    return res;
                }

                int segSize = 0;
                if (args[1] is int v)
                {
                    segSize = v;
                }
                else
                {
                    BraidRuntimeException($"The second argument to the 'list/partition' function must be an integer: (list/split <list> <segmentSize>).");
                }

                foreach (object item in list)
                {
                    seg.Add(item);
                    if (seg.Count == segSize)
                    {
                        res.Add(seg);
                        seg = new Vector();
                    }
                };

                if (seg.Count > 0)
                {
                    res.Add(seg);
                }

                return res;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Splices one list onto the end of another (destructive!).
            ///
            FunctionTable[Symbol.FromString("splice")] = (Vector args) =>
            {
                if (args.Count < 2)
                {
                    BraidRuntimeException($"splice: requires at least 2 arguments");
                }

                s_Expr result = null;
                s_Expr tail = null;

                foreach (var e in args)
                {
                    if (result == null)
                    {
                        if (e is s_Expr sexpr)
                        {
                            result = sexpr;
                            tail = sexpr.Tail();
                        }
                        else if (e is string || e is IDictionary)
                        {
                            result = tail = new s_Expr(e);
                        }
                        else if (e is IEnumerable ienum)
                        {
                            result = tail = s_Expr.FromEnumerable(ienum);
                        }
                        else if (e != null)
                        {
                            result = tail = new s_Expr(e);
                        }
                        // If e is null, just skip it
                    }
                    else
                    {
                        if (e == null)
                        {
                            continue;
                        }

                        result.Splice(e);
                    }
                }

                return result;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Add an element to the end of a list; modifying the list
            ///
            FunctionTable[Symbol.FromString("list-add")] = (Vector args) =>
            {
                if (args.Count != 2)
                {
                    BraidRuntimeException($"list-add: requires 2 arguments; not {args.Count}");
                }
                object list1 = args[0];
                object list2 = args[1];

                if (list1 == null)
                {
                    if (list2 == null)
                    {
                        return null;
                    }
                    else
                    {
                        return new s_Expr(list2, null);
                    }
                }
                else if (list1 is s_Expr sexpr1)
                {
                    // loop a maximum of 10000 times in case of loops
                    int max = 10000;
                    while (max-- > 0 && sexpr1.Cdr != null)
                    {
                        if (Braid._stop)
                        {
                            break;
                        }
                        sexpr1 = (s_Expr)sexpr1.Cdr;
                    }

                    sexpr1.Splice(new s_Expr(list2));

                    // Return the modified list.
                    return list1;
                }
                else
                {
                    return new s_Expr(list1, new s_Expr(list2, null));
                }
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Get the symbol corresponding to the argument string; return null if it doesn't exist
            ///
            FunctionTable[Symbol.FromString("get-symbol")] = (Vector args) =>
            {
                if (args.Count != 1 || args[0] == null)
                {
                    BraidRuntimeException($"get-symbol: requires 1 argument; not {args.Count}");
                }

                string symname = args[0].ToString();
                return Symbol.GetSymbol(symname);
            };

            /////////////////////////////////////////////////////////////////////
            ///
            // Create a new symbol from the argument string if it doesn't already exist.
            ///
            FunctionTable[Symbol.FromString("symbol")] = (Vector args) =>
            {
                if (args.Count != 1 || args[0] == null)
                {
                    BraidRuntimeException($"symbol: requires 1 argument; not {args.Count}");
                }

                string symname = args[0].ToString();
                if (symname.Length == 0)
                {
                    BraidRuntimeException($"The string argument to the 'symbol' function cannot be empty.");
                }

                return Symbol.FromString(symname);
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Generate a new unique symbol; useful for hygenic macros
            ///
            FunctionTable[Symbol.FromString("gen-symbol")] = (Vector args) =>
            {
                if (args != null && args.Count != 0)
                {
                    BraidRuntimeException("gen-symbol: takes no arguments.");
                }

                return Symbol.GenSymbol();
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Create a new keyword from the argument string if it doesn't already exist.
            ///
            FunctionTable[Symbol.FromString("keyword")] = (Vector args) =>
            {
                if (args.Count != 1 || args[0] == null)
                {
                    BraidRuntimeException($"The 'keyword' function requires 1 non-null argument; not {args.Count}");
                }

                string kwname = args[0].ToString();

                if (kwname.Length == 0)
                {
                    BraidRuntimeException($"The string argument to 'new-keyword' cannot be empty.");
                }

                if (kwname[0] != ':')
                {
                    kwname = ":" + kwname;
                }

                var kw = KeywordLiteral.FromString(kwname);
                var caller = CallStack.Caller;
                if (caller != null)
                {
                    kw.File = caller.File;
                    kw.LineNo = caller.LineNo;
                    kw.Offset = caller.Offset;
                    kw.Text = caller.Text;
                }

                return kw;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Create a task e.g. (Task <lambda> <args...>)
            ///
            FunctionTable[Symbol.FromString("async")] =
            FunctionTable[Symbol.FromString("task")] = (Vector args) =>
            {
                if (args.Count < 1 || args[0] == null)
                {
                    BraidRuntimeException(
                        $"async: requires at least 1 argument which must " +
                        $"be a lambda or another task e.g. (async (fn -> \"hi\") or (async (fn -> 2) | async (fn x -> (* x 2))).");
                }

                // Make a copy of the environment to be used by the task
                // and the task specific variables
                var callstack = _callStack;

                // BUGBUGBUG - this should be Task<object> but that doesn't work with other type
                //             but dynamic doesn't work either. Need to figure out a way around the type
                //             system here.
                dynamic incomingTask = null;
                Callable function = null;

                int startIndex = 0;
                if (args[0] is Task t)
                {
                    incomingTask = t;
                    if (args[1] is Callable f)
                    {
                        function = f;
                        startIndex = 2;
                    }
                    else
                    {
                        BraidRuntimeException($"async: if the first argument is a Task, the second argument should " +
                                              "be a function: (async <task> <function> <args...>).");
                    }
                }
                else
                {
                    if (args[0] is Callable f)
                    {
                        f.Environment = (PSStackFrame)Braid.CallStack.Fork();
                        function = f;
                        startIndex = 1;
                    }
                    else
                    {
                        BraidRuntimeException(
                            $"async: requires at least 1 argument which must be a Task<object> or lambda (Task <lambda> [<args...>])");
                    }
                }

                args = args.GetRangeVect(startIndex);

                if (incomingTask != null)
                {
                    Func<Task<object>, object> action = (Task<object> incoming) =>
                    {
                        callstack.Set(Symbol.sym_prior_task, incomingTask);
                        callstack.Set(Symbol.sym_task_args, args);
                        callstack.Set(Symbol.sym_prior_result, incomingTask.Result);
                        args.Insert(0, incomingTask.Result);

                        if (_callStackStack == null)
                        {
                            _callStackStack = new Stack<PSStackFrame>();
                        }


                        if (_callStack != null)
                        {
                            _callStackStack.Push(_callStack);
                        }

                        if (_globalScope == null)
                        {
                            _globalScope = callstack;
                        }

                        _callStack = callstack;

                        try
                        {
                            return function.Invoke(args);
                        }
                        catch (BraidExitException)
                        {
                            throw;
                        }
                        catch (Exception e)
                        {
                            WriteConsoleColor(ConsoleColor.Red, $"Task {Task<object>.CurrentId} threw exception: {e.Message}\n{e}");
                            throw e;
                        }
                        finally
                        {
                            if (Runspace.DefaultRunspace != null)
                            {
                                RunspaceManager.Deallocate(Runspace.DefaultRunspace);
                                Runspace.DefaultRunspace = null;
                            }
                        }
                    };

                    return incomingTask.ContinueWith<object>(action);
                }
                else
                {
                    Func<object> func = () =>
                    {
                        if (_callStackStack == null)
                        {
                            _callStackStack = new Stack<PSStackFrame>();
                        }

                        if (_callStack != null)
                        {
                            _callStackStack.Push(_callStack);
                        }

                        _callStack = callstack;
                        if (_globalScope == null)
                        {
                            _globalScope = _callStack;
                        }

                        try
                        {
                            return function.Invoke(args);
                        }
                        catch (BraidExitException)
                        {
                            throw;
                        }
                        catch (Exception e)
                        {
                            WriteConsoleColor(ConsoleColor.Red, $"Task {Task.CurrentId} threw exception: {e.Message}\n{e}");
                            throw e;
                        }
                        finally
                        {
                            if (Runspace.DefaultRunspace != null)
                            {
                                RunspaceManager.Deallocate(Runspace.DefaultRunspace);
                                Runspace.DefaultRunspace = null;
                            }
                        }
                    };

                    return Task<object>.Factory.StartNew(func);
                }
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Wait for and return the results from a list (or list of lists) of tasks
            /// e.g.
            /// (await <task> ...)
            /// (await <task1> <task2> <task3> ...)
            /// (await [<task1> <task2>] <task3> ...)
            /// (resolve <task> ...)
            ///
            FunctionTable[Symbol.FromString("await")] =
            FunctionTable[Symbol.FromString("resolve")] = (Vector args) =>
            {
                if (args.Count == 1 && args[0] is Task tsk)
                {
                    if (tsk.IsFaulted)
                    {
                        var ie = tsk.Exception.InnerException;
                        BraidRuntimeException($"task '{tsk.Id}' faulted with error: {ie.Message}", ie);
                    }

                    dynamic dtask = tsk;
                    return dtask.Result;
                }

                List<Task> tasks = new List<Task>();
                foreach (var arg in args)
                {
                    foreach (var elem in GetNonGenericEnumerableFrom(arg))
                    {
                        if (elem is Task task)
                        {
                            tasks.Add(task);
                        }
                        else
                        {
                            BraidRuntimeException($"the argument list to 'await' may only contain Task objects, not {elem}");
                        }
                    }
                }

                var taskArray = tasks.ToArray();
                Vector result = new Vector(taskArray.Length);
                Task.WaitAll(taskArray);

                foreach (Task t in taskArray)
                {
                    // If there was a task error; rethrow it.
                    if (t.IsFaulted)
                    {
                        var ie = t.Exception.InnerException;
                        BraidRuntimeException($"task '{t.Id}' faulted with error: {ie.Message}", ie);
                    }

                    dynamic dtask = t;
                    var val = dtask.Result;

                    result.Add(val);
                }

                return result;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Print a line to the console.
            ///
            FunctionTable[Symbol.FromString("console/writeline")] =
            FunctionTable[Symbol.FromString("println")] = (Vector args) =>
            {
                if (args.Count < 1)
                {
                    Console.WriteLine();
                }

                ConsoleColor fg = Console.ForegroundColor;
                ConsoleColor bg = Console.BackgroundColor;
                ConsoleColor oldForegroundColor = fg;
                ConsoleColor oldBackgroundColor = bg;

                bool do_fg = false;
                bool do_bg = false;

                Dictionary<string, NamedParameter> np = CallStack.NamedParameters;
                // If -fg or -bg was specified, use those colors
                if (np != null && np.Count > 0)
                {
                    int count = 0;
                    NamedParameter outval;
                    if (np.TryGetValue("fg", out outval))
                    {
                        np.Remove("fg");
                        fg = ConvertToHelper<ConsoleColor>(outval.Value);
                        do_fg = true;
                        count++;
                    }

                    if (np.TryGetValue("bg", out outval))
                    {
                        np.Remove("bg");
                        bg = ConvertToHelper<ConsoleColor>(outval.Value);
                        do_bg = true;
                        count++;
                    }

                    if (np.Count > 0)
                    {
                        BraidRuntimeException($"println: error processing named parameters; the only named parameters for 'println' are " +
                           $"-fg <color> and -bg <color>, not {"-" + string.Join(", -", np.Keys.Select(x => x.ToString()))}");
                    }
                }

                StringBuilder result = new StringBuilder();
                foreach (var arg in args)
                {
                    if (arg is IDictionary dict)
                    {
                        result.Append(Utils.ToStringDict(dict));
                    }
                    else if (arg != null)
                    {
                        result.Append(arg.ToString());
                        result.Append(' ');
                    }
                }

                try
                {
                    if (do_fg)
                    {
                        Console.ForegroundColor = fg;
                    }

                    if (do_bg)
                    {
                        Console.BackgroundColor = bg;
                    }

                    Console.WriteLine(result.ToString());
                }
                finally
                {
                    Console.BackgroundColor = oldBackgroundColor;
                    Console.ForegroundColor = oldForegroundColor;
                }

                return null;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Print a line to the console with optional fore and background colors.
            ///
            FunctionTable[Symbol.FromString("println-color")] = (Vector args) =>
            {
                if (args.Count < 1)
                {
                    Console.WriteLine();
                }

                ConsoleColor oldColor = Console.ForegroundColor;
                string result = string.Empty;
                bool first = true;
                foreach (var arg in args)
                {
                    if (first)
                    {
                        if (arg == null)
                        {
                            BraidRuntimeException("println-color: the first argument to this function cannot be null. " +
                                $"It must be a valid console color (or the name of a valid console color) not '{arg}'.");
                        }
                        if (arg is ConsoleColor colorlit)
                        {
                            Console.ForegroundColor = colorlit;
                        }
                        else if (arg != null)
                        {
                            string colorName = arg.ToString();
                            ConsoleColor col = (ConsoleColor)ConsoleColor.Parse(typeof(ConsoleColor), colorName);
                            Console.ForegroundColor = col;
                        }
                        first = false;
                    }
                    else
                    {
                        if (arg != null)
                        {
                            result += arg.ToString();
                            result += ' ';
                        }
                    }
                }

                Console.WriteLine(result);
                return null;
            };

            /////////////////////////////////////////////////////////////////////
            //
            // Create a slice from a collection
            //
            FunctionTable[Symbol.FromString("slice")] = (Vector args) =>
            {
                if (args.Count < 1 || args.Count > 3)
                {
                    BraidRuntimeException("slice: the slice function requires 1-3 arguments: a collection to wrap, the offest into the collection to start at and finally, the desired length of the slice.");
                }

                IEnumerable vec = null;
                if (!(args[0] is IEnumerable __vec))
                {
                     BraidRuntimeException("slice: the first argument must be an IEnumerable collection.");
                }
                else
                {
                    vec = __vec;
                }

                IList lstCollection;

                if (vec is IList _vec)
                {
                    lstCollection = _vec;
                }
                else
                {
                    // copy the enumerable into a vector
                    lstCollection = new Vector(vec);
                }

                int vecLen = lstCollection.Count;
                int start = 0;
                if (args.Count > 1)
                {
                    if (!(args[1] is int _start))
                    {
                        BraidRuntimeException("slice: the optional second argument must be an integer.");
                    }
                    else
                    {
                        start = _start;
                    }

                    if (start > vecLen || start < 0)
                    {
                        BraidRuntimeException("slice: the optional second argument must be an integer greater than 0 and less than the length of the collection.");
                    }
                }

                int length = 0;
                bool neg_len = false;
                if (args.Count == 3)
                {
                    if (!(args[2] is int __length))
                    {
                        BraidRuntimeException("slice: the optional third argument must be an integer.");
                    }
                    else
                    {
                        length = __length;
                    }

                    if (length < 0)
                    {
                        neg_len = true;
                        length = vecLen - start + length;
                    }

                    if (start + length > vecLen)
                    {
                        BraidRuntimeException("slice: the optional third argument must be an integer less than the length of the collection.");
                    }
                }

                if (length == 0 && ! neg_len)
                {
                    length = vecLen - start;
                }

                if (vec is string str)
                {
                    vecLen = str.Length;
                    if (vecLen == 1 && start + length == 0)
                        return new Slice("", start, 0);
                    else
                        return new Slice(str, start, length);
                }
                if (vecLen == 1 && start + length == 0)
                    return new Slice(lstCollection, start, 0);
                else
                    return new Slice(lstCollection, start, length);
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Print a string to the console without a newline.
            ///
            FunctionTable[Symbol.FromString("print")] = (Vector args) =>
            {
                if (args.Count < 1)
                {
                    return null;
                }

                ConsoleColor fg = Console.ForegroundColor;
                ConsoleColor bg = Console.BackgroundColor;
                ConsoleColor oldForegroundColor = fg;
                ConsoleColor oldBackgroundColor = bg;

                bool do_fg = false;
                bool do_bg = false;

                Dictionary<string, NamedParameter> np = CallStack.NamedParameters;
                // If -fg or -bg was specified, use those colors
                if (np != null && np.Count > 0)
                {
                    int count = 0;
                    NamedParameter outval;
                    if (np.TryGetValue("fg", out outval))
                    {
                        np.Remove("fg");
                        fg = ConvertToHelper<ConsoleColor>(outval.Value);
                        do_fg = true;
                        count++;
                    }

                    if (np.TryGetValue("bg", out outval))
                    {
                        np.Remove("bg");
                        bg = ConvertToHelper<ConsoleColor>(outval.Value);
                        do_bg = true;
                        count++;
                    }

                    if (np.Count > 0)
                    {
                        BraidRuntimeException($"print: error processing named parameters; the only named parameters for 'print' are " +
                           $"-fg <color> and -bg <color>, not {"-" + string.Join(", -", np.Keys.Select(x => x.ToString()))}");
                    }
                }

                StringBuilder result = new StringBuilder();
                foreach (var arg in args)
                {
                    if (arg != null)
                    {
                        if (result.Length > 0)
                        {
                            result.Append(' ');
                        }

                        result.Append(arg.ToString());
                    }
                }

                try
                {
                    if (do_fg)
                    {
                        Console.ForegroundColor = fg;
                    }

                    if (do_bg)
                    {
                        Console.BackgroundColor = bg;
                    }

                    Console.Write(result.ToString());
                }
                finally
                {
                    Console.BackgroundColor = oldBackgroundColor;
                    Console.ForegroundColor = oldForegroundColor;
                }

                return null;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Print a string to the console in green.
            ///
            FunctionTable[Symbol.FromString("alert")] = (Vector args) =>
            {
                if (args.Count < 1)
                {
                    Console.WriteLine();
                }

                StringBuilder result = new StringBuilder();
                foreach (var arg in args)
                {
                    if (arg != null)
                    {
                        result.Append(arg.ToString());
                        result.Append(' ');
                    }
                }

                WriteConsoleColor(ConsoleColor.Green, result.ToString());
                return null;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Print a string to the console in yellow.
            ///
            FunctionTable[Symbol.FromString("info")] = (Vector args) =>
            {
                if (args.Count < 1)
                {
                    Console.WriteLine();
                }

                StringBuilder result = new StringBuilder();
                foreach (var arg in args)
                {
                    if (arg != null)
                    {
                        result.Append(arg.ToString());
                        result.Append(' ');
                    }
                }

                WriteConsoleColor(ConsoleColor.Yellow, result.ToString());
                return null;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Print a string to the console in magenta.
            ///
            FunctionTable[Symbol.FromString("warn")] = (Vector args) =>
            {
                if (args.Count < 1)
                {
                    Console.WriteLine();
                }

                StringBuilder result = new StringBuilder();
                foreach (var arg in args)
                {
                    if (arg != null)
                    {
                        result.Append(arg.ToString());
                        result.Append(' ');
                    }
                }

                WriteConsoleColor(ConsoleColor.Magenta, result.ToString());
                return null;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Print a string to the console in red.
            ///
            FunctionTable[Symbol.FromString("error")] = (Vector args) =>
            {
                if (args.Count < 1)
                {
                    return null;
                }

                StringBuilder result = new StringBuilder();
                foreach (var arg in args)
                {
                    if (arg != null)
                    {
                        result.Append(arg.ToString());
                        result.Append(' ');
                    }
                }

                var oldColor = Console.ForegroundColor;
                try
                {
                    Console.ForegroundColor = ConsoleColor.Red;
                    Console.WriteLine(result.ToString());
                }
                finally
                {
                    Console.ForegroundColor = oldColor;
                }
                return null;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Print text on the screen at the specified location optionally using the
            /// specified colors.
            ///
            FunctionTable[Symbol.FromString("printat")] =
            FunctionTable[Symbol.FromString("console/writeat")] = (Vector args) =>
            {
                if (args.Count != 3)
                {
                    BraidRuntimeException("console/writeat requires 3 parameters e.g. (console/writeat xPos yPos \"Message\").");
                }

                var np = CallStack.NamedParameters;
                ConsoleColor oldForegroundColor = Console.ForegroundColor;
                ConsoleColor fg = oldForegroundColor;
                ConsoleColor oldBackgroundColor = Console.BackgroundColor;
                ConsoleColor bg = oldBackgroundColor;

                bool do_fg = false;
                bool do_bg = false;

                // If -foreground or -background was specified, use those colors
                if (np != null)
                {
                    if (np.TryGetValue("Foreground", out NamedParameter outval))
                    {
                        fg = ConvertToHelper<ConsoleColor>(outval.Value);
                        do_fg = true;
                    }

                    if (np.TryGetValue("fg", out outval))
                    {
                        fg = ConvertToHelper<ConsoleColor>(outval.Value);
                        do_fg = true;
                    }

                    if (np.TryGetValue("Background", out outval))
                    {
                        do_bg = true;
                        bg = ConvertToHelper<ConsoleColor>(outval.Value);
                    }

                    if (np.TryGetValue("bg", out outval))
                    {
                        do_bg = true;
                        bg = ConvertToHelper<ConsoleColor>(outval.Value);
                    }
                }

                try
                {
                    int x = ConvertToHelper<int>(args[0]);
                    int y = ConvertToHelper<int>(args[1]);
                    if (do_bg)
                        Console.BackgroundColor = bg;
                    if (do_fg)
                        Console.ForegroundColor = fg;
                    Console.SetCursorPosition(x, y);
                    Console.Write(args[2]);
                }
                finally
                {
                    if (do_bg)
                        Console.BackgroundColor = oldBackgroundColor;

                    if (do_fg)
                        Console.ForegroundColor = oldForegroundColor;
                }

                return null;
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Get/set the console background color.
            ///
            FunctionTable[Symbol.FromString("console/backcolor")] = (Vector args) =>
            {
                if (args.Count < 1)
                {
                    return Console.BackgroundColor;
                }

                return (Console.BackgroundColor = ConvertToHelper<ConsoleColor>(args[0]));
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Get/set the console foreground color.
            ///
            FunctionTable[Symbol.FromString("console/forecolor")] = (Vector args) =>
            {
                if (args.Count < 1)
                {
                    return Console.ForegroundColor;
                }

                return (Console.ForegroundColor = ConvertToHelper<ConsoleColor>(args[0]));
            };

            /////////////////////////////////////////////////////////////////////
            ///
            /// Clear the console
            ///
            FunctionTable[Symbol.FromString("console/clear")] =
            FunctionTable[Symbol.FromString("cls")] = (Vector args) =>
            {
                Console.Clear();
                return null;
            };


            /////////////////////////////////////////////////////////////////////
            ///
            /// Implements pipeline execution semantics.
            ///
            SpecialForms[Symbol.FromString("->>")] =
            SpecialForms[Symbol.FromString("pipe")] = pipe_function = (Vector args) =>
            {
                if (args.Count < 1)
                {
                    return null;
                }

                object func;
                var callStack = CallStack;
                object pipeline_data = null;
                int index = 0;
                Vector argvect = new Vector();
                foreach (object cmd in args)
                {
                    if (index == 0)
                    {
                        // Special handling since the first element in the pipe can be a value or non-function variable
                        BraidVariable v;
                        if (cmd is Symbol sym && (v = callStack.GetVariable(sym)) != null)
                        {
                            switch (v.Value)
                            {
                                case IInvokeableValue invokable:
                                    pipeline_data = invokable.Invoke(argvect);
                                    break;
                                case Func<Vector, object> binfunc:
                                    pipeline_data = binfunc.Invoke(argvect);
                                    break;
                                case s_Expr sexpr when (sexpr.IsLambda):
                                    pipeline_data = Eval(new s_Expr(sexpr));
                                    break;
                                case ScriptBlock sb:
                                    pipeline_data = sb.Invoke();
                                    break;
                                case CommandInfo ci:
                                    pipeline_data = InvokePowerShellCommand(null, null, ci, null);
                                    break;
                                default:
                                    // It's a variable so just return the data
                                    pipeline_data = v.Value;
                                    break;
                            }
                        }
                        else if (cmd is IInvokeableValue lambda)
                        {
                            pipeline_data = lambda.Invoke(argvect);
                        }
                        else if (cmd is Func<Vector, object> binfunc)
                        {
                            pipeline_data = binfunc.Invoke(argvect);
                        }
                        else if (cmd is Symbol)
                        {
                            // The symbol wasn't a variable so look for a function
                            pipeline_data = Eval(new s_Expr(cmd));
                        }
                        else
                        {
                            // if the command is an s-expression or just a data object, evaluate it
                            pipeline_data = Eval(cmd);
                        }
                    }
                    else
                    {
                        argvect.Clear();
                        argvect.Add(pipeline_data);
                        if (cmd is IInvokeableValue iiv)
                        {
                            pipeline_data = iiv.Invoke(argvect);
                            continue;
                        }

                        // BUGBUGBUG - this is probably wrong - need to fix the whole 'pipe' function.
                        func = GetFunc(callStack, cmd);
                        if (func is IInvokeableValue iiv2)
                        {
                            pipeline_data = iiv2.Invoke(argvect);
                            continue;
                        }

                        s_Expr cmdexpr = cmd as s_Expr;
                        if (cmdexpr == null)
                        {
                            BraidRuntimeException($"pipe: pipeline elements after the first one must be expressions, not '{cmd}'.");
                        }

                        FunctionType ftype;
                        string funcname;
                        object funcToGet;

                        if (cmdexpr.Car is s_Expr cx)
                        {
                            // Handle the case where you have ... | (fn x -> (length x)) ...
                            func = Eval(cx, true, true);
                            funcToGet = func;
                            ftype = FunctionType.Function;
                            funcname = "lambda";
                        }
                        else
                        {
                            funcToGet = cmdexpr.Car;
                            func = GetFunc(callStack, funcToGet, out ftype, out funcname);
                        }

                        if (func is Callable || func is Func<Vector, object>)
                        {
                            // Evaluate the remaining args
                            cmdexpr = (s_Expr)cmdexpr.Cdr;
                            Dictionary<string, NamedParameter> namedParams = null;
                            while (cmdexpr != null)
                            {
                                var cmdcar = cmdexpr.Car;

                                // If it's a parameter e.g. -param or -param: don't evaluate it.
                                if (cmdcar is NamedParameter np)
                                {
                                    if (namedParams == null)
                                    {
                                        namedParams = new Dictionary<string, NamedParameter>(new ObjectComparer());
                                    }

                                    if (np.TakesArgument)
                                    {
                                        // Handle the case where a named parameter takes an argument.
                                        object val;
                                        cmdexpr = (s_Expr)cmdexpr.Cdr;
                                        if (ftype != FunctionType.SpecialForm)
                                        {
                                            val = Eval(cmdexpr.Car);
                                        }
                                        else
                                        {
                                            val = cmdexpr.Car;
                                        }

                                        np.Expression = val;
                                        namedParams[np.Name] = np;
                                    }
                                    else
                                    {
                                        // Switch parameter
                                        np.Expression = true;
                                        namedParams[np.Name] = np;
                                    }
                                }
                                else
                                {
                                    // Don't evaluate arguments to special functions...
                                    if (ftype != FunctionType.SpecialForm)
                                        argvect.Add(Eval(cmdexpr.Car));
                                    else
                                        argvect.Add(cmdexpr.Car);
                                }

                                cmdexpr = (s_Expr)cmdexpr.Cdr;
                            }

                            if (func is Callable lambda)
                            {
                                // "Quote" the first argument for special forms to avoid double evaluation
                                if (ftype == FunctionType.SpecialForm)
                                {
                                    argvect[0] = new ValueLiteral(argvect[0]);
                                }

                                pipeline_data = lambda.Invoke(argvect, namedParams);
                            }
                            else
                            {
                                var old_np = callStack.NamedParameters;
                                callStack.NamedParameters = namedParams;
                                var binfunc = func as Func<Vector, object>;
                                try
                                {
                                    // "Quote" the first argument for special forms to avoid double evaluation
                                    if (ftype == FunctionType.SpecialForm)
                                    {
                                        argvect[0] = new ValueLiteral(argvect[0]);
                                    }

                                    pipeline_data = binfunc.Invoke(argvect);
                                }
                                catch (BraidExitException)
                                {
                                    throw;
                                }
                                finally
                                {
                                    callStack.NamedParameters = old_np;
                                }
                            }
                        }
                        // If it's a PowerShell command just execute it.
                        else if (func is CommandInfo)
                        {
                            pipeline_data = Eval(cmd, false, false, pipeline_data);
                        }
                        else
                        {
                            // Build up the new expression to evaluate, adding the pipeline
                            // value as the first argument. The pipeline arg
                            // is already evaluated but We need to eval the remaining args
                            // explicitly because we're going to invoke Eval() with no argument
                            // evaluation because we don't want to eval the pipeline data twice.
                            // Actually rewriting (a | b | c) would be better in general but
                            // it won't work for PowerShell commands which take explicit input.
                            // 
                            s_Expr newcmd;

                            if (ftype == FunctionType.SpecialForm)
                            {
                                // If the command is a special form, quote the pipeline data to avoid double evaluation
                                newcmd = new s_Expr(funcToGet, new s_Expr(new s_Expr(Symbol.sym_quote, pipeline_data)));
                            }
                            else
                            {
                                newcmd = new s_Expr(funcToGet, new s_Expr(pipeline_data));
                            }

                            s_Expr end = newcmd.LastNode();
                            cmdexpr = (s_Expr)cmdexpr.Cdr;
                            while (cmdexpr != null)
                            {
                                var cmdcar = cmdexpr.Car;
                                // If it's a parameter e.g. -param or -param: don't evaluate it.
                                if (cmdcar is Symbol s && s.Value[0] == '-')
                                {
                                    end = end.Add(cmdcar);
                                }
                                else
                                {
                                    // Don't evaluate arguments to special functions...
                                    if (ftype != FunctionType.SpecialForm)
                                        end = end.Add(Eval(cmdexpr.Car));
                                    else
                                        end = end.Add(cmdexpr.Car);
                                }
                                cmdexpr = (s_Expr)cmdexpr.Cdr;
                            }
                            pipeline_data = Eval(newcmd, true, false);
                        }
                    }
                    index++;
                }

                return pipeline_data;
            };


            /////////////////////////////////////////////////////////////////////
            //
            // Interpret a string as a PowerShell script
            //
            FunctionTable[Symbol.FromString("shell")] = (Vector args) =>
            {
                if (args.Count != 1)
                {
                    BraidRuntimeException("The 'shell' function takes a single argument which is a string of PowerShell script text.");
                }

                if (args[0] == null)
                {
                    return null;
                }

                string script = args[0].ToString();
                Runspace allocatedRS = null;
                PowerShell pl;
                if (Runspace.DefaultRunspace == null || Runspace.CanUseDefaultRunspace == false)
                {
                    pl = PowerShell.Create().AddScript(script);
                    allocatedRS = RunspaceManager.Allocate();
                    pl.Runspace = allocatedRS;
                }
                else
                {
                    pl = PowerShell.Create(RunspaceMode.CurrentRunspace).AddScript(script);
                }

                try
                {
                    int retry = 2;
                    Collection<PSObject> psresult = null;
                    while (retry-- > 0)
                    {
                        try
                        {
                            psresult = pl.Invoke();
                            retry = 0;
                        }
                        catch (InvalidOperationException)
                        {
                            System.Threading.Thread.Sleep(300);
                        }
                    }

                    if (pl.Streams.Error != null && pl.Streams.Error.Count != 0)
                    {
                        // If there was both output and errors, show the output before throwing the exception.
                        // This is necessary for native commands like 'git'.
                        if (psresult != null && psresult.Count > 0)
                        {
                            int limit = 100;
                            foreach (var o in psresult)
                            {
                                if (Braid._stop || limit-- <= 0)
                                {
                                    Console.WriteLine("======================== [Output too long. Truncated] =============================");
                                    break;
                                }

                                Console.WriteLine(o);
                            }
                        }

                        string s = string.Empty;
                        foreach (var err in pl.Streams.Error)
                        {
                            s += $"    {err}\n";
                        }

                        BraidRuntimeException($"Error running 'shell' command: '{script}':\n{s}");
                    }

                    if (psresult.Count == 0)
                    {
                        return null;
                    }

                    if (psresult.Count == 1 && psresult[0] != null)
                    {
                        return psresult[0];
                    }

                    // Return the results of the object as a vector instead of a list
                    Vector vresult = new Vector(psresult.Count);
                    foreach (var item in psresult)
                    {
                        vresult.Add(item);
                    }

                    return vresult;
                }
                finally
                {
                    if (allocatedRS != null)
                    {
                        RunspaceManager.Deallocate(allocatedRS);
                    }
                    pl.Dispose();
                }
            };

            ///////////////////////////////////////////////////////////////////////////////
            //
            //  Now copy the functions and special forms into the variable table.
            //
            foreach (var sf in FunctionTable)
            {
                var func = new Function(sf.Key.Value, sf.Value)
                {
                    File = "built-in",
                    NameSymbol = sf.Key.Value,
                    LineNo = -1
                };
                CallStack.Const(sf.Key, func);
            }

            foreach (var sf in SpecialForms)
            {
                var func = new Function(sf.Key.Value, sf.Value);
                func.FType = FunctionType.SpecialForm;
                func.File = "built-in";
                func.NameSymbol = sf.Key.Value;
                func.LineNo = -1;
                CallStack.Const(sf.Key, func);
            }

            /////////////////////////////////////////////////////////////
            //
            // Set up the ctrl-C handler to stop the Braid evaluator and any
            // running PowerShell sub-commands without causing the top level PowerShell
            // instance to also stop.
            //
            Console.CancelKeyPress += (object sender, ConsoleCancelEventArgs e) =>
            {
                e.Cancel = true;
                _stop = true;
                Debugger &= ~DebugFlags.Trace;

                // Stop the current PowerShell pipeline if there is one.
                if (_current_pipeline != null)
                {
                    try
                    {
                        _current_pipeline.Stop();
                    }
                    catch
                    {
                    }
                }
            };
        }
    }
}
