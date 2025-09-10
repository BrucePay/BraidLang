/////////////////////////////////////////////////////////////////////////////
//
// The Braid Programming Language - the variable and stack frame classes
//
//
// Copyright (c) 2023 Bruce Payette (see LICENCE file) 
//
////////////////////////////////////////////////////////////////////////////

using System;
using System.Linq;
using System.Text.RegularExpressions;
using System.Collections.Generic;
using System.Management.Automation;

namespace BraidLang
{
    ///////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// A BraidLang dynamic variable.
    /// </summary>
    public sealed class BraidVariable
    {
        public Symbol Name { get; private set; }

        // Marks the variable as being a constant value
        public bool Const { get; set; }

        // Marks the variable as a sink - assigning to it just
        // ignores the result.
        public bool Sink { get; set; }

        public TypeLiteral TypeConstraint { get; set; }

        public IInvokeableValue Setter;
        public IInvokeableValue Getter;

        public object Value
        {
            get
            {
                if (Getter != null)
                {
                    return Getter.Invoke(new Vector { _value });
                }
                return _value;
            }

            set
            {
                if (Sink)
                {
                    return;
                }

                if (Const)
                {
                    Braid.BraidRuntimeException($"Variable {Name} is constant and cannot be set");
                }

                object valueToSet = value;

                // Execute the setter function before processing the type constraint.
                if (Setter != null)
                {
                    valueToSet = Setter.Invoke(new Vector { valueToSet });
                }

                if (Getter != null)
                {
                    Braid.BraidRuntimeException($"Cannot set variable '{Name}' because it is a tied variable with no setter defined.");
                }

                if (TypeConstraint != null)
                {
                    try
                    {
                        valueToSet = TypeConstraint.Invoke(valueToSet);
                    }
                    catch (Exception e)
                    {
                        Braid.BraidRuntimeException($"type constraint violation occurred while trying to set " +
                                                 $"variable ^{TypeConstraint} '{Name}' to value '{valueToSet}: {e.Message}", e);
                    }
                }
                _value = valueToSet;
            }
        }
        object _value;

        public BraidVariable Clone()
        {
            var psv = new BraidVariable(Name, _value)
            {
                TypeConstraint = TypeConstraint,
                Const = Const,
                Sink = Sink,
                Setter = Setter,
                Getter = Getter
            };
            return psv;
        }

        public BraidVariable(Symbol name, object value, TypeLiteral typeConstraint)
        {
            Name = name;
            TypeConstraint = typeConstraint;
            // If there's a type constraint, apply it when setting the value
            if (typeConstraint != null)
            {
                Value = value;
            }
            else
            {
                _value = value;
            }
        }

        public BraidVariable(Symbol name, object value)
        {
            Name = name;
            _value = value;
        }

        public override string ToString()
        {
            if (_value == null) {
                return "nil";
            }
            else {
                return _value.ToString();
            }
        }
    }

    ///////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// Determines where a variable will be set.
    /// </summary>
    public enum ScopeType
    {
        Global = 0,
        Lexical = 1,
        Local = 2
    };

    ///////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// Represents the environment associated with a BraidLang function or lambda.
    /// </summary>
    public sealed class PSStackFrame : ICloneable
    {
        public PSStackFrame Parent { get; set; }

        public Dictionary<Symbol, BraidVariable> Vars
        {
            get
            {
                if (_vars == null)
                {
                    _vars = new Dictionary<Symbol, BraidVariable>();
                }

                return _vars;
            }

            set
            {
                _vars = value;
            }
        }

        Dictionary<Symbol, BraidVariable> _vars;

        public Dictionary<string, NamedParameter> NamedParameters { get; set; }

        public Vector Arguments { get; set; }

        public int LineNo { get; set; }
        public string File { get; set; }
        public string Function { get; set; }
        public ISourceContext Caller { get; set; }

        public bool IsInteractive { get; set; }

        public PSStackFrame(string file, string name, int lineno)
        {
            Vars = new Dictionary<Symbol, BraidVariable>();
            LineNo = lineno;
            File = file;
            Function = name;
        }

        public PSStackFrame(string file, string name, ISourceContext caller, PSStackFrame parent)
        {
            if (parent == null)
            {
                Braid.BraidRuntimeException("new PSStackFrame: argument 'parent' was null");
            }

            if (caller == null)
            {
                Braid.BraidRuntimeException("new PSStackFrame: argument 'caller' was null. File:'{file}' Name:'{name}'.");
            }

            Parent = parent;
            Caller = caller;
            LineNo = caller.LineNo;
            File = file;
            Function = name;
        }

        public PSStackFrame(string file, string name, ISourceContext caller, PSStackFrame parent, Dictionary<Symbol, BraidVariable> environment)
        {
            if (caller == null)
            {
                Braid.WriteConsoleColor(ConsoleColor.Red, $"In 'new PSStackFrame' : CallStack.Caller was null'.");
                Braid.BraidRuntimeException("new PSStackFrame: argument 'caller' was null.");
            }

            Vars = environment;
            Parent = parent;
            Caller = caller;
            LineNo = caller.LineNo;
            File = caller.File;
            Function = name;
        }

        /// <summary>
        /// Clone the lambda with it's own copy of the parent variable table.
        /// This is needed so that things like:
        ///      let fs (forall i (range 10) (\ -> (println "i is ${i}")))
        /// will work. This is not done in the global scope.
        /// </summary>
        /// <returns>The cloned stack framed</returns>
        public object Clone()
        {
            //BUGBUGBUG... - don't clone the environment - it breaks stuff
            return this;
            //return new PSStackFrame(File, Function, Caller, this, new Dictionary<Symbol, BraidVariable>());
            /*
                        var newVars = new Dictionary<Symbol, BraidVariable>();

                        if (Parent != null)
                        {
                            foreach (var pair in Vars)
                            {
                                newVars[pair.Key] = pair.Value.Clone();
                            }
                        }
                        var nf = new PSStackFrame(File, Function, Caller, this, newVars);

                        return nf;
            */
        }

        public int Depth()
        {
            return Braid._callStackStack.Count;
        }

        /// <summary>
        /// Get the script context info for showing the stack trace.
        /// </summary>
        /// <returns></returns>
        public string GetContextMessage()
        {
            if (Caller != null)
                return $"   at ({Caller.File}:{Caller.LineNo})";
            else
                return $"   at ({File}:{LineNo})";
        }

        // Returns the current value associated with the symbol
        public object GetValue(Symbol sym)
        {
            return GetVariable(sym)?.Value;
        }

        // Returns the local variable corresponding to the sym or creates it if it doesn't exist.
        public BraidVariable GetOrCreateLocalVar(Symbol sym)
        {
            if (_vars != null && _vars.TryGetValue(sym, out BraidVariable var))
            {
                return var;
            }

            var result = new BraidVariable(sym, null);
            if (_vars == null)
            {
                _vars = new Dictionary<Symbol, BraidVariable> { { sym, result } };
            }
            else
            {
                _vars.Add(sym, result);
            }

            return result;
        }

        // Returns the current variable object associated with the symbol
        public BraidVariable GetVariable(Symbol sym)
        {
            BraidVariable var;
            var cs = this;
            while (cs != null)
            {
                if (cs._vars != null && cs._vars.TryGetValue(sym, out var))
                {
                    return var;
                }

                cs = cs.Parent;
            }

            return null;
        }

        /// <summary>
        /// Removes a binding from all lexical scopes.
        /// </summary>
        /// <param name="sym">The symbol identifying the binding to remove.</param>
        /// <returns>True if a binding was removed, false otherwise.</returns>
        public bool RemoveVariable(Symbol sym)
        {
            bool result = false;
            if (_vars != null && Vars.ContainsKey(sym))
            {
                Vars.Remove(sym);
                result = true;
            }

            if (Parent != null)
            {
                result = result || Parent.RemoveVariable(sym);
            }

            return result;
        }

        //
        // Bind the value to the variable associated with the symbol.
        // Looks up the call stack to find variables. Creates new lexical
        // variables in the parent scope.
        //
        public object Set(Symbol sym, object value)
        {
            BraidVariable varToSet = null;
            var cs = this;

            while (cs != null)
            {
                if (cs._vars != null && cs._vars.TryGetValue(sym, out varToSet))
                {
                    break;
                }

                cs = cs.Parent;
            }

            if (varToSet == null)
            {
                if (this.Parent != null)
                {
                    cs = this.Parent;
                }
                else
                {
                    cs = this;
                }

                // If no var was found; create a var in the parent scope
                if ((Braid.Debugger & DebugFlags.Trace) != 0 && (Braid.Debugger & DebugFlags.TraceException) == 0)
                {
                    Console.WriteLine("CallStack.SetLocal {0} (depth {1}) '{2}' = '{3}'", Braid.spaces(Braid._evalDepth + 2), Braid._callStackStack.Count, varToSet, Braid.Truncate(value));
                }
                cs.Vars.Add(sym, new BraidVariable(sym, value));
            }
            else if (varToSet.Sink)
            {
                return value;
            }
            else
            {
                if (varToSet.Const)
                {
                    Braid.BraidRuntimeException($"The name '{varToSet.Name}' is a constant and cannot be rebound");
                }

                if ((Braid.Debugger & DebugFlags.Trace) != 0 && (Braid.Debugger & DebugFlags.TraceException) == 0)
                {
                    Console.WriteLine("CallStack.Set    {0} (depth {1}) '{2}' = '{3}'", Braid.spaces(Braid._evalDepth + 2), Braid._callStackStack.Count, varToSet, Braid.Truncate(value));
                }

                varToSet.Value = value;
            }

            return value;
        }

        // Create a constant value in the current scope.
        // BUGBUGBUG - this code isn't quite right - it should always create a new variable.
        public object Const(Symbol sym, object value)
        {
            if (Vars.TryGetValue(sym, out BraidVariable varToSet))
            {
                if (varToSet.Const)
                {
                    Braid.BraidRuntimeException($"The name '{varToSet.Name}' is a constant and cannot be rebound");
                }

                varToSet.Value = value;
            }
            else
            {
                varToSet = new BraidVariable(sym, value);
                Vars.Add(sym, varToSet);
            }

            varToSet.Const = true;

            return value;
        }

        // Create a sink
        public object Sink(Symbol sym)
        {
            BraidVariable varToSet;
            if (!Vars.TryGetValue(sym, out varToSet))
            {
                if (Parent != null)
                {
                    varToSet = Parent.GetVariable(sym);
                }
            }

            if (varToSet != null)
            {
                if (varToSet.Const)
                {
                    Braid.BraidRuntimeException($"The name '{varToSet.Name}' is a constant and cannot be rebound");
                }

                varToSet.Value = null;
            }
            else
            {
                varToSet = new BraidVariable(sym, null);
                Vars.Add(sym, varToSet);
            }

            varToSet.Sink = true;

            return null;
        }

        public BraidVariable SetLocal(Symbol sym, object value)
        {
            if (sym == null)
            {
                Braid.BraidRuntimeException($"The symbol (1st) arguement to 'SetLocal' can't be null.");
            }

            BraidVariable varToSet;
            if (!Vars.TryGetValue(sym, out varToSet))
            {
                varToSet = new BraidVariable(sym, value);
                Vars[sym] = varToSet;
            }
            else
            {
                if (varToSet.Sink)
                {
                    return varToSet;
                }

                if (varToSet.Const)
                {
                    Braid.BraidRuntimeException($"The name '{varToSet.Name}' is a constant and cannot be rebound.");
                }

                varToSet.Value = value;
            }

            return varToSet;
        }

        public BraidVariable SetLocal(TypeLiteral tlit, Symbol sym, object value)
        {
            if (sym == null)
            {
                Braid.BraidRuntimeException($"The symbol (1st) arguement to 'SetLocal' can't be null.");
            }

            BraidVariable varToSet;
            if (!Vars.TryGetValue(sym, out varToSet))
            {
                varToSet = new BraidVariable(sym, null);
                Vars[sym] = varToSet;
            }

            if (tlit != null)
            {
                varToSet.TypeConstraint = tlit;
            }

            if (varToSet.Const)
            {
                Braid.BraidRuntimeException($"The name '{varToSet.Name}' is a constant and cannot be rebound");
            }

            // Make sure the value matches the type constraint.
            if (varToSet.TypeConstraint != null)
            {
                Type targetType = varToSet.TypeConstraint.Value as Type;

                if (targetType == null)
                {
                    Braid.BraidRuntimeException("SetLocal(tlit, sym, obj): couldn't resolve tlit '{varToSet.TypeConstraint}' " +
                                             "'{varToSet.TypeConstraint?.GetType()}'.");
                }

                if (!(value != null && targetType.IsAssignableFrom(value.GetType())))
                {
                    if (targetType == typeof(Regex))
                    {
                        // Special-case regex so it gets created with the right options.
                        if (value is s_Expr sexpr && sexpr.IsQuote)
                        {
                            value = sexpr.Cdr;
                        }

                        string strval = value == null ? string.Empty : value.ToString();
                        value = new Regex(strval, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
                    }
                    else
                    {
                        value = Braid.ConvertTo(value, targetType);
                    }
                }
            }

            varToSet.Value = value;
            return varToSet;
        }

        public bool IsBound(Symbol sym) {
            if (_vars != null && Vars.ContainsKey(sym)) {
                return true;
            }
            if (Parent != null) {
                return Parent.IsBound(sym);
            }
            return false;
        }

        Dictionary<Symbol, BraidVariable> GetSnapshotInternal()
        {
            Dictionary<Symbol, BraidVariable> dict;
            if (Parent == null)
            {
                dict = new Dictionary<Symbol, BraidVariable>();
            }
            else
            {
                dict = Parent.GetSnapshotInternal();
            }

            foreach (var pair in Vars)
            {
                dict[pair.Key] = pair.Value?.Clone();
            }

            return dict;
        }

        /// <summary>
        /// Clones/forks the current stack frame.
        /// </summary>
        /// <returns></returns>
        public PSStackFrame Fork()
        {
            var dict = new Dictionary<Symbol, BraidVariable>();
            foreach (var pair in this.Vars)
            {
                dict[pair.Key] = pair.Value.Clone();
            }

            var newFrame = new PSStackFrame(this.File, this.Function, this.Caller, this, dict);

            return newFrame;
        }

        /// <summary>
        /// Print the current stackframe contents to the console. If detailed 
        /// set all levels of lexical scope will be printed otherwise only the first
        /// level will be printed.
        /// </summary>
        /// <param name="detailed"></param>
        public void PrintStackFrame(bool detailed, Regex filter)
        {
            Braid.WriteConsoleColor(ConsoleColor.Green, $"STACK FRAME: File:{this.File} Line:{this.LineNo} Function:{this.Function}");
            foreach (var pair in Vars.OrderBy(p => p.Key.Value))
            {
                if (filter.IsMatch(pair.Key))
                {
                    if (detailed)
                        Console.WriteLine($" ['{pair.Key}' {Braid.Truncate(pair.Value)}]");
                    else
                        Console.Write($" '{pair.Key}'");
                }
            }

            Console.WriteLine(" |");
            var parent = Parent;
            while (parent != null && parent.Parent != null)
            {
                foreach (var pair in parent.Vars.OrderBy(p => p.Key.Value))
                {
                    if (filter.IsMatch(pair.Key))
                    {
                        if (detailed)
                            Console.WriteLine($"  ['{pair.Key}', {Braid.Truncate(pair.Value)}] ");
                        else
                            Console.Write($"   '{pair.Key}'");
                    }
                }
                parent = parent.Parent;
                Console.WriteLine(" |");

            }

            if (!detailed)
            {
                Console.WriteLine();
            }

            if (detailed)
            {
                if (Parent != null)
                {
                    Parent.PrintStackFrame(true, filter);
                }
            }
        }

        public PSStackFrame GetSnapshot()
        {
            var dict = GetSnapshotInternal();
            var newFrame = new PSStackFrame(this.File, this.Function, this.Caller, null, dict)
            {
                Types = GetTypes()
            };
            return newFrame;
        }

        public override string ToString()
        {
            return $"StackFrame file: {this.File}:{this.LineNo} function ({this.Function})";
        }

        public Dictionary<string, Type> Types;

        public Dictionary<string, Type> GetTypes()
        {
            Dictionary<string, Type> result = (Parent == null) ?
                                                new Dictionary<string, Type>(StringComparer.OrdinalIgnoreCase) :
                                                Parent.GetTypes();

            if (Types != null)
            {
                foreach (var pair in Types)
                {
                    result[pair.Key] = pair.Value;
                }
            }

            return result;
        }

        public Type LookUpType(string name)
        {
            if (Types != null)
            {
                Type result;
                if (Types.TryGetValue(name, out result))
                {
                    return result;
                }
            }

            if (Parent != null)
            {
                return Parent.LookUpType(name);
            }

            return null;
        }

        public bool RemoveType(string name)
        {
            if (Types != null && Types.Remove(name))
            {
                return true;
            }

            if (Parent != null)
            {
                return Parent.RemoveType(name);
            }

            return false;
        }

        public void SetTypeAlias(string name, Type type)
        {
            if (Types == null)
            {
                Types = new Dictionary<string, Type>(StringComparer.OrdinalIgnoreCase);
            }

            Types[name] = type;
        }
    }
}
