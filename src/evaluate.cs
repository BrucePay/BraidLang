/////////////////////////////////////////////////////////////////////////////
//
// The Braid Programming Language - the core runtime evaluation routines.
//
//
// Copyright (c) 2023 Bruce Payette (see LICENCE file) 
//
////////////////////////////////////////////////////////////////////////////

using System;
using System.Linq;
using System.Collections;
using System.Collections.ObjectModel;
using System.Collections.Generic;
using System.Management.Automation;
using System.Management.Automation.Internal; // needed for AutomationNull 
using System.Management.Automation.Runspaces;
using System.Reflection;

namespace BraidLang
{
    public partial class Braid
    {
        /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
        /// <summary>
        /// The core evaluator function
        /// </summary>
        /// <param name="val">
        /// The value to evaluate; this needs to be resolved in a function by calling GetFunc
        /// </param>
        /// <param name="dontEvalArgs">
        /// This routine is called for all command types so you need to tell it if you are going to evaluate the args first or not.
        /// </param>
        /// <param name="dontProcessKeywords">
        /// Functions may have keyword arguments like -foo. For braid function types, these should be processed.
        /// For PowerShell command types, they should just be passed through unchanged
        /// </param>
        /// <param name="pipeline_input">
        /// The pipeline data being passed to this function
        /// </param>
        /// <returns>The result of the evaluation><returns>
        public static object Eval(object val, bool dontEvalArgs = false, bool dontProcessKeywords = false, object pipeline_input = null)
        {
            if (val == null)
            {
                return val;
            }

            Type valType = val.GetType();
            if (valType == typeof(int) || valType == typeof(string))
            {
                return val;
            }

            if (valType == typeof(PSObject) && !(((PSObject)val).BaseObject is PSCustomObject))
            {
                val = ((PSObject)val).BaseObject;
                valType = val.GetType();
            }

            if (valType != typeof(s_Expr))
            {
                if (val is Symbol sval)
                {
                    if (sval.SymId <= Symbol.sym_unquotesplat.SymId)
                    {
                        return sval;
                    }

                    BraidVariable myvar;
                    if (sval.CompoundSymbol)
                    {
                        // Handle compound symbols by concatenating the values of the composite symbols
                        // essentially performing the inverse of destructuring 
                        var symList = sval.ComponentSymbols;
                        var symListLen = symList.Count;
                        Vector result = new Vector(symListLen);
                        for (int i = 0; i < symListLen; i++)
                        {
                            Symbol sym = symList[i];
                            if ((myvar = _callStack.GetVariable(sym)) != null) //megabug
                            {
                                object vval = myvar.Value;

                                if (i < symListLen - 1)
                                {
                                    // only the last symbol is special, everything else gets added as is
                                    result.Add(vval);
                                }
                                else
                                {
                                    if (!sval._bindRestToLast)
                                    {
                                        result.Add(vval);
                                    }
                                    else
                                    {
                                        if (vval is IEnumerable ieval)
                                        {
                                            foreach (object o in ieval)
                                            {
                                                result.Add(o);
                                            }
                                        }
                                        else
                                        {
                                            result.Add(vval);
                                        }
                                    }
                                }
                            }
                            else
                            {
                                sval = Utils.HandleUnboundSymbol(CallStack, sym);
                            }
                        }

                        return result;
                    }
                    else
                    {
                        if ((myvar = _callStack.GetVariable(sval)) != null)
                        {
                            return myvar.Value;
                        }
                    }

                    sval = Utils.HandleUnboundSymbol(CallStack, sval);
                    if (sval != null)
                    {
                        var func = GetFunc(_callStack, sval);
                        if (func != null)
                        {
                            return func;
                        }
                    }

                    return null;
                }

                // Literals evaluate to their value
                if (val is BraidLiteral lit)
                {
                    return lit.Value;
                }

                // Other types evaluate to themselves.
                return val;
            }

            PSStackFrame callStack = _callStack;
            s_Expr sexpr = val as s_Expr;
            object car = sexpr.Car;

            // Handle the various special Symbols
            Symbol carsym = car as Symbol;
            if (carsym != null)
            {
                // handle quoted values e.g. 'foo '(1 2 3)
                if (Symbol.sym_quote.SymId == carsym.SymId)
                {
                    return sexpr.Cdr;
                }

                if (Symbol.sym_quasiquote.SymId == carsym.SymId)
                {
                    var quasival = sexpr.Cdr;
                    return ExpandQuasiQuotes(quasival);
                }

                // If it's splatted; return the whole s-expression so it can be handled at higher layers
                if (Symbol.sym_splat.SymId == carsym.SymId)
                {
                    return sexpr;
                }

                //BUGBUGBUG - we'll get here if the expression is something like:
                //      ((cons lambda '((x) (* x x))) 5)
                // Maybe we should return a function or lambda literal if this happens.
                // Note - if a lambda is already bound to an environment don't re-evaluate it.
                if (Symbol.sym_lambda.SymId == carsym.SymId && sexpr.Environment != null)
                {
                    return sexpr;
                }
            }

            // Should be set before calling BraidRuntimeException().
            var oldCaller = callStack.Caller;
            callStack.Caller = sexpr;

            if (_stop)
            {
                _stop = false;
                BraidRuntimeException("Braid is stopping because cancel was pressed.");
            }

            try
            {
                // Check for stack overflow.
                if (++_evalDepth > MaxDepth)
                {
                    // The finally clauses will decrement the counter down to zero.
                    BraidRuntimeException($"Call stack too deep (> {_evalDepth}); execution is terminated " +
                                        $"executing function: '{_current_function}'.", null, sexpr);
                }

                if (carsym == null && car is s_Expr funcfunc)
                {
                    // Deal with the situation where the first argument is an expression
                    // that returns a function like:
                    //      ((if 1 + *) 2 3)
                    // or
                    //      ((cons lambda '((x) (* x x))) 5)
                    //
                    car = Eval(funcfunc);
                }

                // Look up the command to execute.
                FunctionType ftype;
                string funcName;
                object func;
                if (car is Callable callable)
                {
                    func = callable;
                    funcName = callable.Name;
                    ftype = callable.FType;
                }
                else
                {
                    func = GetFunc(callStack, car, out ftype, out funcName);
                    if (func == null)
                    {
                        if (car is Symbol symToFind)
                        {
                            symToFind = Utils.HandleUnboundSymbol(callStack, symToFind);
                            func = GetFunc(callStack, symToFind, out ftype, out funcName);
                        }

                        if (func == null)
                        {
                            BraidRuntimeException($"no function or script named '{car}' was found.", null, sexpr);
                        }
                    }
                }

                Vector evaledArgs;
                Dictionary<string, NamedParameter> namedParameters;
                EvaluateArgs(callStack, dontEvalArgs, dontProcessKeywords, true, sexpr, ftype, out evaledArgs, out namedParameters);

                switch (func)
                {
                    case Callable funcToCall:
                        return funcToCall.Invoke(evaledArgs, namedParameters);

                    case IInvokeableValue iv:
                        return iv.Invoke(evaledArgs);

                    case Func<Vector, object> func_o_o:
                        var oldNamedParameters = callStack.NamedParameters;
                        callStack.NamedParameters = namedParameters;
                        try
                        {
                            return func_o_o(evaledArgs);
                        }
                        finally
                        {
                            callStack.NamedParameters = oldNamedParameters;
                        }

                    case s_Expr fnexpr:
                        // BUGBUGBUGBUG - this clause shouldn't be needed. Find out how we get here
                        if (!fnexpr.IsLambda)
                        {
                            BraidRuntimeException($"only lambda expressions can be executed, not: {fnexpr}.", null, sexpr);
                        }

                        var env = fnexpr.Environment;

                        // unclosed function expression
                        if (env == null)
                        {
                            env = callStack;
                        }

                        var list = (s_Expr)fnexpr.Cdr;
                        Vector funargs = null;
                        Dictionary<string, KeywordLiteral> kwargs = null;

                        // BUGBUGBUGBUGBUG - this isn't right - need to handle kw args in both cases
                        if (list.Car is VectorLiteral vlit)
                        {
                            funargs = new Vector();

                            if (vlit.ValueList != null)
                            {
                                foreach (var e in vlit.ValueList)
                                {
                                    if (e is KeywordLiteral kwa)
                                    {
                                        if (kwargs == null)
                                        {
                                            kwargs = new Dictionary<string, KeywordLiteral>(new ObjectComparer());
                                        }

                                        kwargs.Add(kwa.BaseName, kwa);
                                    }
                                    else
                                    {
                                        funargs.Add(e);
                                    }
                                }
                            }
                        }
                        else
                        {
                            funargs = ((Vector)list.Car);
                        }

                        var body = (s_Expr)(list.Cdr);
                        var returnType = fnexpr.ReturnType;

                        var newSF = new PSStackFrame(fnexpr.File, fnexpr.Function, fnexpr, env);
                        newSF.Caller = fnexpr;
                        env = Braid.PushCallStack(newSF);
                        try
                        {
                            return InvokeUserFunction(funcName, evaledArgs, namedParameters, funargs, kwargs, body, env, returnType);
                        }
                        finally
                        {
                            Braid.PopCallStack();
                        }

                    case ApplicationInfo appInfo when _evalDepth < 2:
                        // This is a hack to allow top-level interactive commands to be run from within braid.
                        // If there is a single top-level executable then execute it directly instead
                        // of passing it off to PowerShell. This allows commands like "git.exe :diff" or "vim.exe" to work
                        // properly. As the current implementation is rather a hack it probably won't work in some cases.
                        // An inprovement would be to use the ArgumentList interface instead of Arguments but that isn't available
                        // in the Desktop CLR.
                        using (System.Diagnostics.Process myProcess = new System.Diagnostics.Process())
                        {
                            myProcess.StartInfo.UseShellExecute = false;
                            myProcess.StartInfo.FileName = appInfo.Path;
                            myProcess.StartInfo.CreateNoWindow = false;
                            myProcess.StartInfo.RedirectStandardOutput = false;
                            myProcess.StartInfo.RedirectStandardError = false;
                            string args = "";
                            foreach (object arg in evaledArgs)
                            {
                                var sarg = arg.ToString();
                                if (sarg.Contains(' '))
                                {
                                    args += "\"" + sarg + "\" ";
                                }
                                else
                                {
                                    args += sarg + " ";
                                }
                            }
                            myProcess.StartInfo.Arguments = args;
                            myProcess.Start();
                            try
                            {
                                myProcess.WaitForInputIdle();
                            }
                            catch {
                                myProcess.WaitForExit();
                            }

                            // User might have used ctrl-c to stop the child process so clear the stop flag.
                            Braid._stop = false;

                            return null;
                        }

                    case CommandInfo cmdinfo:
                        return InvokePowerShellCommand(evaledArgs, namedParameters, cmdinfo, pipeline_input);

                    case ScriptBlock sb:
                        // Allocate a runspace on-demand for scriptblocks
                        bool allocatedRS = false;
                        if (Runspace.DefaultRunspace == null)
                        {
                            Runspace.DefaultRunspace = RunspaceManager.Allocate();
                            allocatedRS = true;
                        }

                        try
                        {
                            var sbresult = sb.InvokeReturnAsIs(evaledArgs.ToArray());
                            if (sbresult is PSObject respso2 && !(respso2.BaseObject is PSCustomObject))
                            {
                                sbresult = respso2.BaseObject;
                            }

                            return sbresult;
                        }
                        finally
                        {
                            if (allocatedRS)
                            {
                                RunspaceManager.Deallocate(Runspace.DefaultRunspace);
                                Runspace.DefaultRunspace = null;
                            }
                        }

                    default:
                        BraidRuntimeException($"Unexpected command type: '{func}' ({func?.GetType()})", null, sexpr);
                        break;
                }
            }
            catch (BraidExitException)
            {
                throw;
            }
            catch (BraidCompilerException)
            {
                throw;
            }
            catch (BraidBaseException e)
            {
                if (Braid.Debugger != 0)
                {
                    if ((Braid.Debugger & DebugFlags.Trace) != 0 && (Braid.Debugger & DebugFlags.TraceException) == 0 && !TracedException)
                    {
                        var oldColor = Console.ForegroundColor;
                        try
                        {
                            Console.ForegroundColor = ConsoleColor.Red;
                            Console.WriteLine("TRACE ERROR: " + e.Message);
                            Console.WriteLine("EXPR: " + Truncate(sexpr));
                            TracedException = true;
                        }
                        finally
                        {
                            Console.ForegroundColor = oldColor;
                        }
                    }
                }
                throw;
            }
            catch (TargetInvocationException tie)
            {
                Exception inner = tie.InnerException;
                while (inner is TargetInvocationException)
                {
                    inner = inner.InnerException;
                }

                if (inner is BraidUserException)
                {
                    throw inner;
                }

                string msg = $"error invoking method: {inner.Message}.";
                if (Braid.Debugger != 0)
                {
                    if ((Braid.Debugger & DebugFlags.Trace) != 0 && (Braid.Debugger & DebugFlags.TraceException) == 0 && !_stop)
                    {
                        TracedException = true;
                        var oldColor = Console.ForegroundColor;
                        try
                        {
                            WriteConsoleColor(ConsoleColor.Red, $"TRACE ERROR: {inner.GetType()}\nMessage: {msg}\nEXPR: {Truncate(sexpr)}");
                            TracedException = true;
                        }
                        finally
                        {
                            Console.ForegroundColor = oldColor;
                        }

                        // Reenter the listener
                        var oldDebugger = Debugger;
                        try
                        {
                            Debugger = 0;
                            StartBraid();
                        }
                        finally
                        {
                            Debugger = oldDebugger;
                        }
                    }
                }

                if (!TracedException)
                {
                    Braid.BraidRuntimeException(msg, inner, sexpr);
                }
            }
            catch (Exception e)
            {
                string msg = e.Message;

                if (Braid.Debugger != 0)
                {
                    if ((Braid.Debugger & DebugFlags.Trace) != 0 && (Braid.Debugger & DebugFlags.TraceException) == 0 && !_stop)
                    {
                        TracedException = true;
                        var oldColor = Console.ForegroundColor;
                        WriteConsoleColor(ConsoleColor.Red, $"TRACE ERROR: {e.GetType()}\nMessage: {msg}\nEXPR: {Truncate(sexpr)}");

                        // Reenter the listener
                        var oldDebugger = Debugger;
                        try
                        {
                            Debugger = 0;
                            StartBraid();
                        }
                        finally
                        {
                            Debugger = oldDebugger;
                        }
                    }
                }

                if (!TracedException)
                {
                    BraidRuntimeException(msg, e, sexpr);
                }
            }
            finally
            {
                callStack.Caller = oldCaller;
                _evalDepth--;
            }
            return null;
        }


        ////////////////////////////////////////////////////////////////////
        /// <summary>
        /// Routine to evaluate the arguments to a Braid function
        /// </summary>
        /// <param name="dontEvalArgs">If true. the arguments are returned (mostly) unevaluated (Type literals still get evaluated.)</param>
        /// <param name="dontProcessKeywords">If true, don't extract keywords</param>
        /// <param name="skipFunc">Skip the car of the argument list</param>
        /// <param name="fncall">The Braid expression whose arguments are to be evaluated.</param>
        /// <param name="ftype">The type of function being called.</param>
        /// <param name="evaledArgs">The resulting argument collection.</param>
        /// <param name="namedParameters">Any named parameters that were passed to the function.</param>
        public static void EvaluateArgs(
            PSStackFrame callStack,
            bool dontEvalArgs,
            bool dontProcessKeywords,
            bool skipFunc,
            s_Expr fnCall,
            FunctionType ftype,
            out Vector evaledArgs,
            out Dictionary<string, NamedParameter> namedParameters)
        {
            namedParameters = null;

            ISeq sequence;
            if (skipFunc)
            {
                // The first element of an s_Expr is the function, the actual arguments start at the Cdr.
                if (fnCall.Cdr == null)
                {
                    evaledArgs = new Vector();
                    return;
                }
                sequence = fnCall.Cdr as ISeq;
            }
            else
            {
                sequence = fnCall as ISeq;
            }

            if (sequence == null)
            {
                BraidRuntimeException($"invalid argument structure; arguments must be a list, not '{fnCall.Cdr}'.");
            }

            // Allocate a buffer to hold the evaluated arguments.
            evaledArgs = new Vector(sequence.Count);

            if (ftype != FunctionType.SpecialForm && ftype != FunctionType.Macro && dontEvalArgs == false)
            {
                NamedParameter parameter = null;
                while (sequence != null)
                {
                    var it = sequence.Car;

                    if (it == null)
                    {
                        evaledArgs.Add(null);
                    }
                    else if (parameter != null)
                    {
                        // Process the value for the named paramter
                        object val = Eval(it);
                        if (namedParameters == null)
                        {
                            namedParameters = new Dictionary<string, NamedParameter>(StringComparer.OrdinalIgnoreCase);
                        }

                        parameter.Expression = val;
                        namedParameters[parameter.Name] = parameter;
                        parameter = null;
                    }
                    else
                    {
                        if (it is NamedParameter np)
                        {
                            if (namedParameters == null)
                            {
                                namedParameters = new Dictionary<string, NamedParameter>(StringComparer.OrdinalIgnoreCase);
                            }

                            if (np.TakesArgument)
                            {
                                parameter = np;
                            }
                            else
                            {
                                np.Expression = true;
                                namedParameters[np.Name] = np;
                            }
                        }
                        else
                        {
                            if (it is s_Expr sargval && sargval.IsSplat)
                            {
                                object cdr = sargval.Cdr;
                                if (cdr is s_Expr sexpr_cdr)
                                {
                                    cdr = sexpr_cdr.Car;
                                }

                                object  splatVal = Eval(cdr);

                                //BUGBUGBUGBUG - this is a hack that goes along with the hack in new-dict. There has
                                // to be a better, more regular way to do this rather than hard-coding it to the new-dict function.
                                // Special handling for dictionaries when calling new-dict. This
                                // allows this dictionary to be merged with the one created by new-dict.
                                if (splatVal is IDictionary && _current_function != null
                                    && _current_function.Equals("new-dict", StringComparison.OrdinalIgnoreCase))
                                {
                                    evaledArgs.Add(new s_Expr(Symbol.sym_splat, splatVal));
                                    sequence = (s_Expr)(sequence.Cdr);
                                    continue;
                                }

                                // Special handing of dictionaries in general - flatten out the
                                // keys and values into individual arguments.
                                if (splatVal is DictionaryLiteral dlit)
                                {
                                    splatVal = dlit.Value;
                                }
                                else if (splatVal is IDictionary dict)
                                {
                                    foreach (object obj in dict)
                                    {
                                       DictionaryEntry pair;
                                        if (obj is DictionaryEntry kvp)
                                        {
                                            pair = kvp;
                                            evaledArgs.Add(pair.Key);
                                            evaledArgs.Add(pair.Value);
                                        }
                                        else
                                        {
                                            BraidRuntimeException(
                                                $"Conversion to DictionaryEntry failed, obj is '{obj}' obj type is '{obj.GetType()}'",
                                                null, fnCall);
                                        }
                                    }

                                    sequence = (s_Expr)(sequence.Cdr);
                                    continue;
                                }

                                foreach (var e in GetEnumerableFrom(splatVal))
                                {
                                    if (e is IDictionary ed)
                                    {
                                        foreach (object key in ed.Keys)
                                        {
                                            evaledArgs.Add(key);
                                            evaledArgs.Add(ed[key]);
                                        }
                                    }
                                    else if (e is DictionaryEntry kvp)
                                    {
                                        evaledArgs.Add(kvp.Key);
                                        evaledArgs.Add(kvp.Value);
                                    }
                                    else
                                    {
                                        evaledArgs.Add(e);
                                    }
                                }

                                sequence = (s_Expr)(sequence.Cdr);
                                continue;
                            }

                            evaledArgs.Add(Eval(it));
                            parameter = null;
                        }
                    }

                    sequence = (ISeq)(sequence.Cdr);
                }
            }
            else
            {
                // The args are not to be evaluated so just copy them into evaledArgs
                // Named parameters are still extracted for special forms but not for macros.
                NamedParameter parameter = null;
                foreach (var it in sequence)
                {
                    // Always try to resolve type literals
                    object itValue = it;

                    //BUGBUGBUG - check error handling, make sure the semantic is correct...
                    // Handle splatted arguments.
                    // BUGBUGBUG Should this happen when args are not being evaluated? Need to rethink this.
                    object splatVal = null;
                    if (itValue is s_Expr sargval && sargval.IsSplat)
                    {
                        // BUGBUGBUGBUGBUG - this is a hack - @x should be (splat "x") it should be a symbol.
                        // not sure why this is happening, need to check the parser.    
                        switch (sargval.Cdr)
                        {
                            case string str:
                                splatVal = callStack.GetValue(Symbol.FromString(str));
                                break;
                            case Symbol sym:
                                splatVal = callStack.GetValue(sym);
                                break;
                            case s_Expr splatexpr:
                                splatVal = Eval(splatexpr.Car);
                                break;
                            default:
                                splatVal = Eval(sargval.Cdr);
                                break;
                        }

                        //BUGBUGBUGBUG - this is a hack that goes along with the hack in new-dict. There has
                        // to be a better, more regular way to do this rather than hard-coding it to the new-dict function.
                        // Special handling for dictionaries when calling new-dict. This
                        // allows this dictionary to be merged with the one created by new-dict.
                        if (splatVal is IDictionary && _current_function != null &&
                            _current_function.Equals("new-dict", StringComparison.OrdinalIgnoreCase)
                        )
                        {
                            evaledArgs.Add(new s_Expr(Symbol.sym_splat, splatVal));
                            continue;
                        }

                        // Special handing of dictionaries in general - flatten out the
                        // keys and values into individual arguments.
                        if (splatVal is IDictionary dict)
                        {
                            foreach (var key in dict.Keys)
                            {
                                evaledArgs.Add(key);
                                evaledArgs.Add(dict[key]);
                            }

                            continue;
                        }

                        if (splatVal is DictionaryEntry kvp)
                        {
                            evaledArgs.Add(kvp.Key);
                            evaledArgs.Add(kvp.Value);

                            continue;
                        }

                        foreach (var e in GetEnumerableFrom(splatVal))
                        {
                            if (e is IDictionary ed)
                            {
                                foreach (object key in ed.Keys)
                                {
                                    evaledArgs.Add(key);
                                    evaledArgs.Add(ed[key]);
                                }
                            }
                            else
                            {
                                evaledArgs.Add(e);
                            }
                        }

                        continue;
                    }

                    if (parameter != null)
                    {
                        if (namedParameters == null)
                        {
                            namedParameters = new Dictionary<string, NamedParameter>(StringComparer.OrdinalIgnoreCase);
                        }

                        parameter.Expression = itValue;
                        namedParameters[parameter.Name] = parameter;
                        parameter = null;
                    }
                    else
                    {
                        if (dontProcessKeywords)
                        {
                            evaledArgs.Add(itValue);
                        }
                        else
                        {
                            if (itValue is NamedParameter np)
                            {
                                parameter = np;
                            }

                            if (parameter != null)
                            {
                                if (namedParameters == null)
                                {
                                    namedParameters = new Dictionary<string, NamedParameter>(StringComparer.OrdinalIgnoreCase);
                                }

                                if (! parameter.TakesArgument)
                                {
                                    if (namedParameters.ContainsKey(parameter.Name))
                                    {
                                        namedParameters[parameter.Name].Expression = true;
                                    }
                                    else
                                    {
                                        parameter.Expression = true;
                                        namedParameters[parameter.Name] = parameter;
                                    }
                                    parameter = null;
                                }
                            }
                            else
                            {
                                parameter = null;
                                evaledArgs.Add(itValue);
                            }
                        }
                    }
                }
            }
        }

        /// <summary>
        /// Function for executing the code contained in a user-defined function. This code
        /// does not create a new scope.
        /// </summary>
        /// <param name="funcName"></param>
        /// <param name="evaledArgs"></param>
        /// <param name="namedParameters"></param>
        /// <param name="funArgs"></param>
        /// <param name="functionBody"></param>
        /// <param name="environment"></param>
        /// <param name="returnType"></param>
        /// <returns></returns>
        public static object InvokeUserFunction(
            string funcName,
            Vector evaledArgs,
            Dictionary<string, NamedParameter> namedParameters,
            Vector funArgs,
            Dictionary<string, KeywordLiteral> kwargs,
            s_Expr functionBody,
            PSStackFrame environment,
            TypeLiteral returnType
        )
        {
            if (Braid.Debugger != 0)
            {
                if ((Braid.Debugger & DebugFlags.Trace) != 0 && (Braid.Debugger & DebugFlags.TraceException) == 0)
                {
                    var argstr = evaledArgs != null ? string.Join(" ", evaledArgs.ToArray()) : "";
                    WriteConsoleColor(ConsoleColor.Green, $"CALL:  {spaces(_evalDepth)} ({funcName} {argstr})");
                }
            }

            object userFuncResult = null;
            s_Expr userFunction = functionBody;

            userFuncResult = null;
            environment.NamedParameters = namedParameters;
            environment.Arguments = evaledArgs;
            var callStack = CallStack;

            try
            {
                // BUGBUGBUGBUG This code is used to collect the set of keyword parameters exported by the function
                // This is currently recomputed on every function call. Compiling functions ahead of
                // time would speed things up.
                HashSet<string> keywordSet = null;
                int index = 0;
                if (funArgs != null)
                {
                    bool got_and_args = false;
                    Symbol and_args_symbol = null;
                    for (int i = 0; i < funArgs.Count; i++)
                    {
                        object arg = funArgs[i];
                        Symbol varsym;
                        object initializer = AutomationNull.Value;
                        TypeLiteral typeConstraint = null;

                        // Handle initializers & type constraints (^Type <varname> <initializer>)

                        if (arg is MatchElementBase meb)
                        {
                            if (evaledArgs == null || evaledArgs.Count <= index)
                            {
                                if (meb.DoDefault(callStack) != MatchElementResult.Matched)
                                {
                                    if (meb.HasAndArgs)
                                    {
                                        callStack.SetLocal(meb.Variable, null);
                                        break;
                                    }
                                    else
                                    {
                                        BraidRuntimeException(
                                            $"When attempting to call function '{funcName}' there was no argument " +
                                            $"or initializer for the parameter '{meb}'");
                                    }
                                }

                                continue;
                            }

                            if (meb.HasAndArgs)
                            {
                                // BUGBUGBUG - should be a compile time check
                                if (index != funArgs.Count - 1)
                                {
                                    BraidRuntimeException($"In funciion '{funcName}' the & variable '{arg}' must be the last variable in the function's signature.");
                                }

                                var remArgs = new Slice(evaledArgs, index, evaledArgs.Count - index);
                                index = evaledArgs.Count;
                                callStack.SetLocal(meb.Variable, remArgs);
                                break;
                            }

                            if (meb.DoMatch(callStack, evaledArgs, index, out int consumed) != MatchElementResult.Matched)
                            {
                                BraidRuntimeException($"In function '{funcName}': failed to bind value '{Braid.Truncate(evaledArgs[index])}' to parameter pattern '{meb}'.");
                            }

                            if (++index <= evaledArgs.Count)
                            {
                                continue;
                            }
                            else
                            {
                                varsym = meb.Variable;
                            }
                        }
                        else if (arg is s_Expr arglist)
                        {
                            // Check for type constraints first
                            if (arglist.Car is Type targ)
                            {
                                typeConstraint = new TypeLiteral(targ);
                                arglist = (s_Expr)arglist.Cdr;
                            }
                            else if (arglist.Car is TypeLiteral tlitconstraint)
                            {
                                typeConstraint = tlitconstraint;
                                arglist = (s_Expr)arglist.Cdr;
                            }

                            // Now the parameter symbol
                            varsym = arglist.Car as Symbol;
                            if (varsym == null)
                            {
                                BraidRuntimeException(
                                    $"Formal parameters to functions must be symbols, not '{arglist.Car}'");
                            }

                            if (varsym.Value[0] == '&')
                            {
                                BraidRuntimeException(
                                    $"{varsym} cannot be used in parameter qualifier expressions like [(^int varsym 0)].");
                            }

                            arglist = arglist.Cdr as s_Expr;
                            if (arglist != null)
                            {
                                //BUGBUGBUG- need custom exception here. Should defer this in case it's not needed
                                initializer = Eval(arglist.Car, false, true); //BUGBUGBUG
                                if (typeConstraint != null)
                                {
                                    initializer = typeConstraint.Invoke(initializer);
                                }
                            }
                        }
                        else
                        {
                            // Not an s-expression, just a simple variable
                            if (arg is KeywordLiteral klit)
                            {
                                string kname = (string)klit.BaseName;  // string has the colon trimmed off
                                if (keywordSet == null)
                                {
                                    keywordSet = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                                }

                                keywordSet.Add(kname);
                                NamedParameter kval = null;
                                varsym = Symbol.FromString(kname);

                                if (namedParameters != null && namedParameters.TryGetValue(kname, out kval))
                                {
                                    environment.SetLocal(varsym, kval.Expression);
                                }
                                else
                                {
                                    // handle the case where the parameter was not specified.

                                    environment.SetLocal(varsym, null);
                                }
                                // Keyword args don't consume a positional argument
                                continue;
                            }

                            varsym = arg as Symbol;
                            if (varsym == null)
                            {
                                varsym = Symbol.FromString(arg.ToString());
                            }

                            // If we encounter &var in the args list, bind everything after this to 'var'.
                            got_and_args = varsym.Value.Length > 1 && varsym.Value[0] == '&';
                            if (got_and_args)
                            {
                                and_args_symbol = Symbol.FromString(varsym.Value.Substring(1));
                                break;
                            }
                        }

                        if (index < evaledArgs.Count)
                        {
                            var valToBind = evaledArgs[index++];
                            if (typeConstraint != null)
                            {
                                try
                                {
                                    valToBind = typeConstraint.Invoke(valToBind);
                                }
                                catch (Exception e)
                                {
                                    string typeStr = valToBind == null ? "null" : ("^" + valToBind.GetType());
                                    BraidRuntimeException(
                                        $"Type constraint on variable '{varsym}' failed: unable to convert value " +
                                        $"'{Braid.Truncate(valToBind)}' of type {typeStr} to type [{typeConstraint}].", e);
                                }
                            }

                            // If the name looks like a:b then deconstruct the value
                            if (!MultipleAssignment(environment, varsym, valToBind, ScopeType.Local))
                            {
                                environment.SetLocal(varsym, valToBind);
                            }
                        }
                        else
                        {
                            if (initializer == AutomationNull.Value)
                            {
                                BraidRuntimeException(
                                    $"When attempting to call function '{funcName}' there was no argument " +
                                    $"or initializer for the parameter '{varsym}'");
                            }

                            environment.SetLocal(varsym, initializer);
                        }
                    }

                    if (index < evaledArgs.Count && !got_and_args)
                    {
                        BraidRuntimeException($"{funcName}: {evaledArgs.Count - index} too many arguments "
                                   + $"were specified for this function. ('{funcName}' takes {funArgs.Count} arguments, not {evaledArgs.Count}.)");
                    }

                    // Match defined keywords against actual keywords...
                    if (kwargs != null && kwargs.Count != 0)
                    {
                        foreach (var keyword in kwargs.Values)
                        {
                            NamedParameter np;
                            if (namedParameters != null && namedParameters.TryGetValue(keyword.BaseName, out np))
                            {
                                if (keyword.RequiresArgument && np.TakesArgument)
                                {
                                    // BUGBUGBUG - shouldn't have to generate symbols all the time.
                                    environment.SetLocal(Symbol.FromString(keyword.BaseName), np.Expression);
                                }
                                else if (keyword.RequiresArgument == false && np.TakesArgument == false)
                                {
                                    environment.SetLocal(Symbol.FromString(keyword.BaseName), true);
                                }
                                else
                                {
                                    BraidRuntimeException($"the switch -{keyword.BaseName}: requires an argument and none was provided.");
                                }
                            }
                            else
                            {
                                environment.SetLocal(keyword.BaseName, null);
                            }
                        }
                    }

                    // BUGBUGBUG - this check should be done at compile time...
                    // Make sure that all of the named parameters that where specified correspond
                    // to an actual named parameter.
                    if (namedParameters != null && namedParameters.Count != 0)
                    {
                        foreach (var pair in namedParameters)
                        {
                            if (kwargs == null)
                            {
                                BraidRuntimeException($"The keyword -{pair.Key} is not valid for this function " +
                                                    $"because this command defines no keywords ");
                            }
                            else if (!kwargs.ContainsKey(pair.Key))
                            {
                                string validKeywords = string.Join(", ", kwargs.Keys);
                                BraidRuntimeException($"The keyword -{pair.Key} is not valid for this function. Valid keywords are: {validKeywords}.");
                            }
                        }
                    }
                }

                // It's not considered an error if the function body is null.
                if (functionBody != null)
                {
                    // Evaluate the body of the function
                    s_Expr listOfFunctions = functionBody;
                    while (listOfFunctions != null)
                    {
                        if (_stop)
                        {
                            _stop = false;
                            BraidRuntimeException("Braid is stopping because cancel was pressed.");
                        }

                        object func = listOfFunctions.Car;
                        userFuncResult = Eval(func);
                        if (userFuncResult is BraidFlowControlOperation fco)
                        {
                            if (fco is BraidReturnOperation retop)
                            {
                                userFuncResult = retop.ReturnValue;
                                break;
                            }
                            else if (fco is BraidRecurOperation recur)
                            {
                                return recur;
                            }
                            else if (fco is BraidContinueOperation)
                            {
                                return userFuncResult;
                            }
                            else if (fco is BraidBreakOperation)
                            {
                                return userFuncResult;
                            }
                        }

                        listOfFunctions = (s_Expr)listOfFunctions.Cdr;
                    }

                    if (returnType != null)
                    {
                        try
                        {
                            return returnType.Invoke(userFuncResult);
                        }
                        catch (TargetInvocationException tie)
                        {
                            Exception exception = tie.InnerException;
                            while (exception is TargetInvocationException tie2)
                            {
                                exception = tie2.InnerException;
                            }

                            BraidRuntimeException($"Return failed; Exception was raised converting '{userFuncResult}' of " +
                                    $"type ^{userFuncResult?.GetType()} to return type ^{returnType.Value}: {exception.Message}", exception);
                        }
                        catch (System.Management.Automation.PSInvalidCastException psic)
                        {
                            var exception = psic.InnerException;
                            BraidRuntimeException($"Return failed; Exception was raised converting '{userFuncResult}' of " +
                                $"type ^{userFuncResult?.GetType()} to return type ^{returnType.Value}: {exception.Message}", exception);
                        }
                    }

                    return userFuncResult;
                }

                return null;
            }
            finally
            {
                if (Braid.Debugger != 0)
                {
                    if ((Braid.Debugger & DebugFlags.Trace) != 0 && (Braid.Debugger & DebugFlags.TraceException) == 0)
                    {
                        var argstr = Braid.Truncate(string.Join(" ", evaledArgs.ToArray()));
                        WriteConsoleColor(ConsoleColor.Green, $"RTRN:  {spaces(_evalDepth)} ({funcName} {argstr}) <-- {Braid.Truncate(userFuncResult)}");
                    }
                }
            }
        }

        ////////////////////////////////////////////////////////////////////
        /// <summary>
        /// Wrapper around the PowerShell API
        /// </summary>
        /// <param name="evaledArgs">The list of arguments to pass to the PowerShell command</param>
        /// <param name="namedParameters">List of parameter/valu pairs to pass to the cmdlet.</param>
        /// <param name="cmdinfo">The command info of the command to run.</param>
        /// <param name="pipeline_input">Pipeline input to pass to the command (may be null)</param>
        /// <param name="trackPipeline">If true, set this pipeline as the global _current_pipeline so it can be stopped.</param>
        /// <returns></returns>
        private static object InvokePowerShellCommand(
            Vector evaledArgs,
            Dictionary<string, NamedParameter> namedParameters,
            CommandInfo cmdinfo,
            object pipeline_input,
            bool trackPipeline = true
        )
        {
            Runspace allocatedRS = null;
            PowerShell pl = null;
            if (Runspace.DefaultRunspace == null || Runspace.CanUseDefaultRunspace == false)
            {
                pl = PowerShell.Create();
                allocatedRS = RunspaceManager.Allocate();
                pl.Runspace = allocatedRS;
            }
            else
            {
                pl = PowerShell.Create(RunspaceMode.CurrentRunspace);
            }

            try
            {
                // Make sure the process current directory matches the PowerShell current
                // directory.
                if (_getLocationCommand == null)
                {
                    _getLocationCommand = pl.AddCommand("Get-Command").AddArgument("Get-Location").Invoke()[0].BaseObject as CommandInfo;
                    pl.Commands.Clear();
                }

                dynamic pwshpath = pl.AddCommand(_getLocationCommand).Invoke()[0];
                System.Environment.CurrentDirectory = pwshpath.Path;
                pl.Commands.Clear();

                pl.AddCommand(cmdinfo);
                if (trackPipeline)
                {
                    _current_pipeline = pl;
                }

                if (evaledArgs != null)
                {
                    for (int i = 0; i < evaledArgs.Count; i++)
                    {
                        object arg = evaledArgs[i];

                        // BUGBUGBUG - autoconvert symbols and keywords to strings. This lets you use
                        // keywords symbols as arguments to strongly typed string parameters but it also
                        // means that symbols and keywords can't be passed to PowerShell commands which
                        // may be desirable in the future.
                        if (arg is Symbol sym)
                        {
                            arg = sym.Value;
                        }
                        else if (arg is KeywordLiteral klit)
                        {
                            arg = klit.BaseName;
                        }

                        pl.AddArgument(arg);
                    }
                }

                if (namedParameters != null)
                {
                    foreach (var pair in namedParameters)
                    {
                        NamedParameter p = pair.Value as NamedParameter;
                        if (p == null)
                        {
                            BraidRuntimeException($"InvokePowerShell: No NamedParameter object was passed for parameter -{pair.Key}: " +
                                "the value passed was null.");
                        }

                        object parmValue = p.Expression;
                        if (parmValue is Symbol sym)
                        {
                            parmValue = sym.Value;
                        }
                        else if (parmValue is KeywordLiteral klit)
                        {
                            parmValue = klit.BaseName;
                        }

                        pl.AddParameter(pair.Key, parmValue);
                    }
                }

                Collection<PSObject> psresult = null;

                if (pipeline_input == null)
                {
                    psresult = pl.Invoke();
                }
                else
                {
                    var enumerableData = GetNonGenericEnumerableFrom(pipeline_input);
                    psresult = pl.Invoke(enumerableData);
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
                                Console.WriteLine("======================== [Output too long (too many lines). Truncated] =============================");
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
                    BraidRuntimeException($"Error running PowerShell command: '{cmdinfo}':\n{s}");
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
                return new Vector(psresult);
            }
            finally
            {
                if (allocatedRS != null)
                {
                    RunspaceManager.Deallocate(allocatedRS);
                }

                if (pl != null)
                {
                    pl.Dispose();
                }
            }
        }
        
        // Cache the Get-Location CommandInfo to avoid having to look it up all the time.
        static CommandInfo _getLocationCommand;

        ////////////////////////////////////////////////////////////////////
        /// <summary>
        /// Do substitution (expansion) on quasiquoted lists such that
        ///    (let a 1) (let b '(1 2 3)) `(a is ~a b is ~@b)
        /// expands to
        ///    (a is 1 b is 1 2 3)
        /// This is used in macros to generate new code.
        /// </summary>
        /// <param name="quasival">The value to expand (usually a list.)</param>
        /// <returns>The expanded list.</returns>
        public static object ExpandQuasiQuotes(object quasival)
        {
            if (quasival == null)
            {
                return null;
            }

            if (quasival is s_Expr quasiexpr)
            {
                if (quasiexpr.IsUnquote)
                {
                    // Expand ~a
                    if (quasiexpr.Cdr is Symbol sym)
                    {
                        return Braid.CallStack.GetValue(sym);
                    }

                    return Eval(quasiexpr.Cdr);
                }

                if (quasiexpr.IsUnquoteSplat)
                {
                    if (quasiexpr.Cdr is Symbol sym)
                    {
                        var val = Braid.CallStack.GetValue(sym);
                        if (val == null)
                        {
                            return val;
                        }
                        return new s_Expr(Symbol.sym_unquotesplat, val);
                    }

                    if (quasiexpr.Cdr is s_Expr cdrexpr && cdrexpr.Car is Symbol sym2)
                    {
                        var val = Braid.CallStack.GetValue(sym2);
                        if (val == null)
                        {
                            return val;
                        }
                        return new s_Expr(Symbol.sym_unquotesplat, val);
                    }

                    return new s_Expr(Symbol.sym_unquotesplat, Eval(quasiexpr.Cdr));
                }

                if (quasiexpr.Car == Symbol.sym_new_dict)
                {
                    Vector nde = new Vector { Symbol.sym_new_dict };
                    foreach (var el in (s_Expr) quasiexpr.Cdr)
                    {
                        nde.Add(ExpandQuasiQuotes(el));
                    }
                    
                    return s_Expr.FromEnumerable(nde);
                }

                var car = ExpandQuasiQuotes(quasiexpr.Car);
                var cdr = ExpandQuasiQuotes(quasiexpr.Cdr);

                s_Expr result = null;
                if (car != null)
                {
                    if (car is s_Expr scar && scar.IsUnquoteSplat)
                    {
                        var cdrval = scar.Cdr;
                        if (cdrval is s_Expr cdrvalsexpr)
                        {
                            result = cdrvalsexpr.Clone();
                        }
                        else if (cdrval is IEnumerable ienum && ! (cdrval is string))
                        {
                            result = s_Expr.FromEnumerable(ienum);
                        }
                        else
                        {
                            result = new s_Expr(cdrval);
                        }
                    }
                    else
                    {
                        result = new s_Expr(car, null);
                    }
                }

                if (cdr != null)
                {
                    var cdrsexpr = cdr as s_Expr;
                    if (cdrsexpr == null)
                    {
                        if (result == null)
                            result = new s_Expr(cdr);
                        else
                            result.LastNode().Add(cdr);
                    }
                    else
                    {
                        if (result == null)
                        {
                            result = cdrsexpr.Clone();
                        }
                        else
                        {
                            result.LastNode().Cdr = cdrsexpr.Clone();
                        }
                    }
                }

                return result;
            }
            else if (quasival is VectorLiteral vectlist)
            {
                Vector newvallist = new Vector();
                foreach (var e in vectlist.ValueList)
                {
                    newvallist.Add(ExpandQuasiQuotes(e));
                }

                return new VectorLiteral(s_Expr.FromEnumerable(newvallist), vectlist.LineNo);
            }
            else if (quasival is DictionaryLiteral dlit)
            {
                var newvallist = new Vector();
                foreach (var e in dlit.ValueList)
                {
                    newvallist.Add(ExpandQuasiQuotes(e));
                }

                return new DictionaryLiteral(newvallist, dlit.File, dlit.LineNo, dlit.Text, dlit.Offset);
            }
            else if (quasival is HashSetLiteral orighs)
            {
                Vector processedValues = new Vector();
                foreach (var e in orighs.ValueList)
                {
                    processedValues.Add(ExpandQuasiQuotes(e));
                }

                return new HashSetLiteral(s_Expr.FromEnumerable(processedValues), orighs.LineNo);
            }
            else
            {
                return quasival;
            }
        }
    }
}
