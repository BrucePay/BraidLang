/////////////////////////////////////////////////////////////////////////////
//
// The Braid Programming Language - classes implementing Patterns and Pattern Elements
//
////////////////////////////////////////////////////////////////////////////

using System;
using System.Linq;
using System.Collections;
using System.Text;
using System.Text.RegularExpressions;
using System.Collections.Generic;
using System.Management.Automation;

namespace BraidLang
{
    //////////////////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// The return value from the pattern matcher.
    /// </summary>
    public enum MatchElementResult
    {
        Matched = 1,
        NoMatch = 2,
        Fail    = 3,
    }

    //////////////////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// Base class for all of the pattern element types.
    /// </summary>
    public abstract class MatchElementBase
    {
        public Symbol Variable { get; set; }
        abstract public MatchElementResult DoMatch(PSStackFrame callstack, object thingToMatch, int start, out int consumed);

        public void SetDefaultValue(object val)
        {
            DefaultValue = val;
            HasDefault = true;
        }

        public MatchElementResult DoDefault(PSStackFrame callstack)
        {
            if (HasDefault)
            {
                if (Variable != null)
                {
                    callstack.SetLocal(Variable, Braid.Eval(DefaultValue));
                }

                return MatchElementResult.Matched;
            }

            return MatchElementResult.NoMatch;
        }

        public object DefaultValue { get; set; }
        public bool   HasDefault   { get; set; }
        public bool   HasAndArgs   { get; set; }
    }

    //////////////////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// Implements variable matching including vector matching like "x:xs"
    /// </summary>
    public sealed class VarElement : MatchElementBase
    {
        internal Symbol PinnedVariable { get; set; }

        List<Symbol> Names;
        bool MatchMany = true;
        bool pinned;

        public VarElement(Symbol var) : this(var, null) { }

        public VarElement(Symbol varsym, Symbol pinsym)
        {
            // BUGBUGBUG - need to add a lot of error checking here...
            if (pinsym != null)
            {
                if (pinsym.Value[0] == '&')
                {
                    HasAndArgs = true;
                    Variable = Symbol.FromString(pinsym.Value.Substring(1));
                }
                else 
                {
                    Variable = pinsym;
                }

                PinnedVariable = Symbol.FromString(varsym.Value.Substring(1));
                pinned = true;
            }
            else if (varsym.Value[0] == '%')
            {
                PinnedVariable = Symbol.FromString(varsym.Value.Substring(1));
                pinned = true;
            }
            else
            {
                if (varsym.Value[0] == '&')
                {
                    HasAndArgs = true;
                    Variable = Symbol.FromString(varsym.Value.Substring(1));
                }
                else
                {
                    Variable = varsym;
                }
            }

            if (Variable != null)
            {
                MatchMany = Variable._bindRestToLast;
                if (Variable.CompoundSymbol)
                {
                    Names = Variable.ComponentSymbols;
                }
            }
        }

        public override string ToString()
        {
            string vname = "";
            if (PinnedVariable != null)
                vname = '%' + PinnedVariable.Value;
            else if (Variable != null)
                vname = Variable.Value;

            if (HasDefault)
            {
                return $"({vname} {Utils.ToSourceString(DefaultValue)})";
            }

            return vname;
        }

        public override MatchElementResult DoMatch(PSStackFrame callstack, object thingToMatch, int start, out int consumed)
        {
            consumed = 0;

            // Only matches a single element
            if (thingToMatch is IList lst)
            {
                if (start >= lst.Count)
                {
                    return MatchElementResult.NoMatch;
                }

                thingToMatch = lst[start];
            }

            // Handle destructuring variable patterns like "x:xs" or "x:y:z:".
            if (Names != null)
            {
                ISeq argvect = thingToMatch as ISeq;
                if (argvect == null)
                {
                    if (thingToMatch is VectorLiteral vlit)
                    {
                        argvect = (ISeq)vlit.Value;
                    }
                    else if (thingToMatch is string str)
                    {
                        argvect = new Slice(str);
                    }
                    else
                    {
                        if (thingToMatch is KeyValuePair<object, object> pair && Names.Count != 2)
                        {
                            Braid.BraidRuntimeException("Multiple assignment of a Key/Value pair requires exactly 2 target variables.");
                        }

                        if (Braid.MultipleAssignment(callstack, Variable, thingToMatch, ScopeType.Local, quiet: true))
                        {
                            return MatchElementResult.Matched;
                        }
                        else
                        {
                            return MatchElementResult.NoMatch;
                        }
                    }
                }

                if (argvect is IList argvectilist && argvectilist.Count < Names.Count - 1)
                {
                    return MatchElementResult.NoMatch;
                }

                int i = 0;
                while (i < Names.Count - 1)
                {
                    if (argvect == null)
                    {
                        return MatchElementResult.NoMatch;
                    }

                    callstack.SetLocal(Names[i++], argvect.Car);
                    argvect = (ISeq)argvect.Cdr;
                }

                // BUGBUGBUG - validate the null check
                // Remaining elements go into the last name as a sequence but if there's only one,
                // store it as a scalar so that "x:y -> (+ x y)" will work.
                if (MatchMany)
                {
                    callstack.SetLocal(Names[i], argvect);
                    consumed = 1;
                    return MatchElementResult.Matched;
                }
                else if (argvect != null && argvect.Cdr == null)
                {
                    consumed = 1;
                    callstack.SetLocal(Names[i], argvect.Car);
                    return MatchElementResult.Matched;
                }
                else
                {
                    return MatchElementResult.NoMatch;
                }
            }
            else
            {
                if (pinned)
                {
                    object pinnedValue = callstack.GetValue(PinnedVariable);
                    switch (pinnedValue)
                    {
/* BUGBUGBUG - doing this means you can't use pinned variables to match functions as is done in 'pprint2.tl' i.e. you can't do '%break' - you have to do '(== break)' instead.  */
                        case Callable callable:
                            var fresult = callable.Invoke(new Vector { thingToMatch });
                            if (Braid.IsTrue(fresult))
                            {
                                if (Variable != null)
                                {
                                    callstack.SetLocal(Variable, thingToMatch);
                                }

                                consumed = 1;
                                return MatchElementResult.Matched;
                            }

                            return MatchElementResult.NoMatch;


                        case Regex re:
                            if (re.Match(thingToMatch.ToString()).Success)
                            {
                                if (Variable != null)
                                {
                                    callstack.SetLocal(Variable, thingToMatch);
                                }

                                consumed = 1;
                                return MatchElementResult.Matched;
                            }
                            return MatchElementResult.NoMatch;

                        case Type ty:
                            if (ty.IsAssignableFrom(thingToMatch.GetType()))
                            {
                                if (Variable != null)
                                {
                                    callstack.SetLocal(Variable, thingToMatch);
                                }

                                consumed = 1;
                                return MatchElementResult.Matched;
                            }

                            return MatchElementResult.NoMatch;

                        case TypeLiteral tlit:
                            object _testout;
                            if (tlit.TestValue(thingToMatch, out _testout))
                            {
                                if (Variable != null)
                                {
                                    callstack.SetLocal(Variable, _testout);
                                }

                                consumed = 1;
                                return MatchElementResult.Matched;
                            }

                            return MatchElementResult.NoMatch;

                        default:
                            if (Braid.CompareItems(pinnedValue, thingToMatch))
                            {
                                if (Variable != null)
                                {
                                    callstack.SetLocal(Variable, thingToMatch);
                                }

                                consumed = 1;
                                return MatchElementResult.Matched;
                            }

                            return MatchElementResult.NoMatch;
                    }
                }

                callstack.SetLocal(Variable, thingToMatch);
                consumed = 1;

                return MatchElementResult.Matched;
            }
        }
    }

    //////////////////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// Handles matching a recursive pattern function.
    /// </summary>
    public sealed class StarFunctionElement : MatchElementBase
    {
        internal Symbol FunctionVariable { get; set; }

        public StarFunctionElement(Symbol var) : this(var, null) { }

        public StarFunctionElement(Symbol funcVar, Symbol varToBind)
        {
            FunctionVariable = funcVar;
            Variable = varToBind;
            if (FunctionVariable.CompoundSymbol)
            {
                Braid.BraidRuntimeException($"A star function can't have a multi-part name: '*{FunctionVariable}'");
            }
        }

        public override string ToString()
        {
            return "*" + FunctionVariable.Value;
        }

        public override MatchElementResult DoMatch(PSStackFrame callstack, object thingToMatch, int start, out int consumed)
        {
            consumed = 0;
            object func = callstack.GetValue(FunctionVariable);
            if (func is PatternFunction pfunc)
            {
                Vector funcArgs = thingToMatch as Vector;
                if (funcArgs == null || funcArgs.Count < start)
                {
                    return MatchElementResult.NoMatch;
                }

                if (funcArgs != null && start > 0)
                {
                    funcArgs = funcArgs.GetRangeVect(start);
                }

                if (funcArgs == null && thingToMatch is ISeq seq)
                {
                    while (start-- > 0)
                    {
                        seq = (ISeq)(seq.Cdr);
                    }

                    funcArgs = new Vector(seq);
                }

                if (funcArgs == null)
                {
                    funcArgs = new Vector() { thingToMatch };
                }

                object result = pfunc.Invoke(funcArgs, null, true, ref consumed);
                if (result == null)
                {
                    consumed = 0;
                    return MatchElementResult.NoMatch;
                }

                if (Variable != null)
                {
                    if (Variable.CompoundSymbol)
                    {
                        if (result is IEnumerable en)
                        {
                            int index = 0;
                            foreach (var val in en)
                            {
                                if (index < Variable.ComponentSymbols.Count)
                                {
                                    callstack.SetLocal(Variable.ComponentSymbols[index++], val);
                                }
                                else
                                {
                                    Braid.BraidRuntimeException("matching star function: too many values were returned than there are variables.");
                                }
                            }
                        }
                        else
                        {
                            Braid.BraidRuntimeException($"matching star function: an enumerable value was expected, got {result?.GetType()} instead.");
                        }
                    }
                    else
                    {
                        callstack.SetLocal(Variable, result);
                    }
                }

                return MatchElementResult.Matched;
            }

            Braid.BraidRuntimeException($"The star function name '*{FunctionVariable}' did not resolve to a Callable function.");

            return MatchElementResult.NoMatch;
        }
    }

    //////////////////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// A regular-expression based pattern matching element.
    /// </summary>
    public sealed class RegexElement : MatchElementBase
    {
        public Regex Regex;

        public RegexElement(Regex regex, Symbol variable)
        {
            Variable = variable;
            Regex = regex;
            if (variable != null && variable.CompoundSymbol)
            {
                int gc = regex.GetGroupNumbers().Length;
                if (gc < variable.ComponentSymbols.Count || (gc > variable.ComponentSymbols.Count && ! variable._bindRestToLast))
                {
                    Braid.BraidRuntimeException($"Processsing regex pattern element #\"{regex}\": the number of regex groups doesn't match the number of elements in '{variable}'.");
                }
            }
        }

        public override MatchElementResult DoMatch(PSStackFrame callstack, object thingToMatch, int start, out int consumed)
        {
            // Only matches a single element
            if (thingToMatch is IList lst)
            {
                thingToMatch = lst[start];
            }

            consumed = 0;
            if (thingToMatch == null)
            {
                return MatchElementResult.NoMatch;
            }
            var matchResult = Regex.Match(thingToMatch.ToString());
            if (matchResult.Success)
            {
                var matchArray = new Vector();
                if (matchResult != null)
                {
                    for (var index = 0; index < matchResult.Groups.Count; index++)
                    {
                        matchArray.Add(matchResult.Groups[index]);
                    }
                }

                if (Variable != null)
                {
                    if (Variable.CompoundSymbol)
                    {
                        Braid.BindMultiple(callstack, matchArray, ScopeType.Local, Variable.ComponentSymbols, Variable._bindRestToLast);
                    }
                    else
                    {
                        callstack.SetLocal(Variable, matchArray);
                    }
                }
                else
                {
                    callstack.SetLocal(Symbol.sym_matches, matchArray);
                }

                consumed = 1;
                return MatchElementResult.Matched;
            }
            else
            {
                return MatchElementResult.NoMatch;
            }
        }

        public override string ToString()
        {
            return $"#\"{Regex}\"";
        }
    }

    //////////////////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// A type-based pattern matching element.
    /// </summary>
    public sealed class TypeElement : MatchElementBase
    {
        public TypeLiteral Tlit { get; set; }

        public TypeElement(TypeLiteral tlit, Symbol variable)
        {
            Variable = variable;
            Tlit = tlit;
        }

        public override string ToString()
        {
            string result = "";
            if (Variable != null)
            {
                result += $"({Tlit} {Variable}";

                if (HasDefault)
                {
                    result += ' ' + Utils.ToSourceString(DefaultValue);
                }

                result += ")";
            }
            else
            {
                result += $"{Tlit}";
            }

            return result;
        }

        public override MatchElementResult DoMatch(PSStackFrame callstack, object thingToMatch, int start, out int consumed)
        {
            consumed = 0;

            if (thingToMatch == null)
            {
                return MatchElementResult.NoMatch;
            }

            // Only matches a single element
            if (thingToMatch is IList lst)
            {
                thingToMatch = lst[start];
            }

            object result;
            if (Tlit.TestValue(thingToMatch, out result))
            {
                if (Variable != null)
                {
                    if (Variable.CompoundSymbol)
                    {
                        PSObject psThingToMatch = PSObject.AsPSObject(result);
                        foreach (var sym in Variable.ComponentSymbols)
                        {
                            var mi = psThingToMatch.Members[sym.Value];
                            if (mi == null)
                            {
                                Braid.BraidRuntimeException(
                                    $"Pattern matching: member '{sym}' cannot be found on an object '{Braid.Truncate(thingToMatch)}' of type {thingToMatch.GetType()}]");
                            }

                            callstack.SetLocal(sym, mi.Value);
                        }
                    }
                    else
                    {
                        callstack.SetLocal(Variable, result);
                    }
                }

                consumed = 1;
                return MatchElementResult.Matched;
            }

            return MatchElementResult.NoMatch;
        }
    }

    //////////////////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// Constant value pattern matching element. Matches values like strings, numbers, etc.
    /// It also handles executing lambda pattern elements.
    /// </summary>
    public sealed class GenericElement : MatchElementBase
    {
        object Pattern { get; set; }

        FunctionLiteral _lambda;
        s_Expr _predicate;
        Vector matchArgs;

        public GenericElement(object pattern, Symbol variable)
        {
            // Special handling for '| so you can use a literal pipe in a pattern
            if (pattern is s_Expr sexpr && sexpr.IsQuote && sexpr.Cdr is Symbol sym && sym == Symbol.sym_pipe)
            {
                Pattern = Symbol.sym_pipe;
            }
            else
            {
                Pattern = pattern;
            }

            Variable = variable;
            _lambda = Pattern as FunctionLiteral;
            if (_lambda == null && Pattern is s_Expr cexpr)
            {
                if (cexpr.Car is Callable || cexpr.Car is Func<Vector, object> || cexpr.IsLambda)
                {
                    _predicate = cexpr;
                }
            }
        }

        public override string ToString()
        {
            if (Pattern == null)
            {
                return "nil";
            }

            string result;
            if (Pattern is IList ilist && ilist.Count == 0)
            {
                return "[]";
            }

            result = Pattern.ToString();
            if (result.Contains(" "))
            {
                return result = '"' + result.Replace("\"", "\\\"") + '"';
            }

            return result;
        }

        public override MatchElementResult DoMatch(PSStackFrame callstack, object thingToMatch, int start, out int consumed)
        {
            consumed = 0;

            // Only matches a single element.
            if (thingToMatch is IList lst)
            {
                if (start >= lst.Count)
                {
                    return MatchElementResult.NoMatch;
                }

                thingToMatch = lst[start];
            }

            // If the pattern was a BriadLiteral, resolve it to the actual value before comparing.
            if (Pattern is BraidLiteral mlit)
            {
                Pattern = mlit.Value;
            }

            if (_lambda != null)
            {
                var argvec = new Vector(1);
                argvec.Add(thingToMatch);
                Callable funcToCall = _lambda.Value as Callable;
                if (Braid.IsTrue(funcToCall.Invoke(argvec)))
                {
                    if (Variable != null)
                    {
                        callstack.SetLocal(Variable, thingToMatch);
                    }

                    consumed = 1;
                    return MatchElementResult.Matched;
                }

                return MatchElementResult.NoMatch;
            }

            if (_predicate != null)
            {
                if (matchArgs == null)
                {
                    matchArgs = new Vector { null };
                }
                matchArgs[0] = thingToMatch;

                // Evaluate the predicate expression
                var evalresult = Braid.Eval(_predicate);

                // If the predicate evaluation returned a callable, then call it (double evaluation)
                var presult = (evalresult is Callable callable) ? callable.Invoke(matchArgs) : evalresult;

                // Test the final result
                if (Braid.IsTrue(presult))
                {
                    if (Variable != null)
                    {
                        callstack.SetLocal(Variable, thingToMatch);
                    }

                    consumed = 1;
                    return MatchElementResult.Matched;
                }

                return MatchElementResult.NoMatch;
            }

            // Treat null as matching []
            if ((Pattern == null && thingToMatch is IList listToMatch && listToMatch.Count == 0) ||
                Braid.CompareItems(Pattern, thingToMatch))
            {
                if (Variable != null)
                {
                    callstack.SetLocal(Variable, thingToMatch);
                }

                consumed = 1;
                return MatchElementResult.Matched;
            }

            return MatchElementResult.NoMatch;
        }
    }

    //////////////////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// Represents a fail 'guard' in a pattern. Once the matcher passes this element it won't
    /// backtrack for additional matches.
    /// </summary>
    public sealed class FailElement : MatchElementBase
    {
        public override MatchElementResult DoMatch(PSStackFrame callstack, object thingToMatch, int start, out int consumed)
        {
            consumed = 0;
            return MatchElementResult.Fail;
        }

        public override string ToString() => "!";
    }

    //////////////////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// Represents an ignored elementin a pattern.
    /// </summary>
    public sealed class IgnoreElement : MatchElementBase
    {
        public override MatchElementResult DoMatch(PSStackFrame callstack, object thingToMatch, int start, out int consumed)
        {
            consumed = 1;

            if (Variable != null)
            {
                callstack.SetLocal(Variable, thingToMatch);
            }

            return MatchElementResult.Matched;
        }

        public override string ToString() => "_";
    }

    //////////////////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// Represents a property pattern element. Property patterns are dictionary literals
    /// containing the names of properties that must be present on the object under evaluation
    /// as well as the types/values those elements must contain.
    /// </summary>
    public sealed class PropertyPatternElement : MatchElementBase
    {
        public Dictionary<object, MatchElementBase> _patternElements = new Dictionary<object, MatchElementBase>(new ObjectComparer());

        public PropertyPatternElement(DictionaryLiteral dictionaryLiteral)
        {
            object key = null;

            foreach (var obj in dictionaryLiteral.ValueList)
            {
                if (key == null)
                {
                    switch (obj)
                    {
                        case string str:
                            key = str;
                            break;
                        case Symbol sym:
                            key = sym.Value;
                            break;
                        case KeywordLiteral klit:
                            key = klit;
                            break;
                        default:
                            Braid.BraidRuntimeException(
                                $"In a property pattern, the keys must be string literals, symbols or keywords, not '{obj}'",
                                null,
                                dictionaryLiteral);
                            break;
                    }

                    if (!Regex.IsMatch(key.ToString(), @"^\w[\w\d_]*$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant))
                    {
                        Braid.BraidRuntimeException(
                            $"Invalid property name '{obj}'. In a property pattern, the property name must start with a letter " +
                            "followed by zero or more letters, numbers or '_' characters. Other characters are not permitted.",
                            null, dictionaryLiteral);
                    }
                }
                else
                {
                    var pe = PatternClause.CompilePatternElement(obj);

                    // BUGBUGBUG - reject pattern elements that don't makse sense here.

                    // Property patterns always set a variable. If no variable is provided
                    // then default to the name of the property.
                    if (pe.Variable == null)
                    {
                        pe.Variable = Symbol.FromString(key.ToString());
                    }

                    _patternElements.Add(key, pe);

                    key = null;
                }
            }

            if (key != null)
            {
                Braid.BraidRuntimeException($"Missing pattern after key '{key}' in property pattern.", null, dictionaryLiteral);
            }
        }

        public override MatchElementResult DoMatch(PSStackFrame callstack, object thingToMatch, int start, out int consumed)
        {
            consumed = 0;

            // Only matches a single element
            if (thingToMatch is IList lst)
            {
                if (lst.Count < 1)
                {
                    return MatchElementResult.NoMatch;
                }

                thingToMatch = lst[start];
            }

            if (thingToMatch == null)
            {
                return MatchElementResult.NoMatch;
            }

            Vector objectHolder = new Vector { null };

// BUGBUGBUGBUGBUG - add error for KeyValue pair, error if key type doesn't match gereric key type?
            if (thingToMatch is IDictionary dict)
            {
                foreach (var item in _patternElements)
                {
                    object keyVal = item.Key;
                    if (! dict.Contains(keyVal))
                    {
                        return MatchElementResult.NoMatch;
                    }

                    var mivalue = dict[keyVal];
                    if (mivalue is IList)
                    {
                        objectHolder[0] = mivalue;
                        mivalue = objectHolder;
                    }

                    var pe = item.Value;
                    var matchResult = pe.DoMatch(callstack, mivalue, 0, out consumed);
                    if (matchResult != MatchElementResult.Matched)
                    {
                        return matchResult;
                    }
                }
            }
            else
            {
                PSObject psThingToMatch = PSObject.AsPSObject(thingToMatch);

                foreach (var item in _patternElements)
                {
                    string keyVal = item.Key.ToString();
                    var mi = psThingToMatch.Members[keyVal];
                    if (mi == null)
                    {
                        return MatchElementResult.NoMatch;
                    }

                    // BUGBUGBUG - cardinality issue here scalar vs collection
                    object mivalue = mi.Value;
                    if (mivalue is IList)
                    {
                        objectHolder[0] = mivalue;
                        mivalue = objectHolder;
                    }

                    var pe = item.Value;
                    var matchResult = pe.DoMatch(callstack, mivalue, 0, out consumed);
                    if (matchResult != MatchElementResult.Matched)
                    {
                        return matchResult;
                    }
                }
            }

            consumed = 1;
            return MatchElementResult.Matched;
        }

        public override string ToString()
        {
            var sb = new StringBuilder("{");
            bool first = true;
            foreach (KeyValuePair<object, MatchElementBase> pair in _patternElements)
            {
                if (! first)
                {
                    sb.Append(", ");
                }
                else
                {
                    first = false;
                }

                sb.Append(pair.Key.ToString());
                sb.Append(" : ");
                sb.Append(pair.Value?.ToString());
            }

            sb.Append("}");
            return sb.ToString();
        }
    }

    //////////////////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// Represents a "nested pattern element" - basically a vector literal containing pattern elements.
    /// </summary>
    public sealed class NestedPatternElement : MatchElementBase
    {
        List<MatchElementBase> Elements;
        Symbol RemainingArgsVar;
        bool HasStarFunction;
        int NestedArity;
        bool NestedHasAndArgs;

        public NestedPatternElement(List<MatchElementBase> elements, int nestedArity, bool hasStarFunction)
        {
            Elements = elements;
            HasStarFunction = hasStarFunction;
            MatchElementBase last = null;
            if (Elements.Count > 0)
            {
                last = Elements[Elements.Count - 1];
            }

            NestedArity = nestedArity;
            if (last != null && last is VarElement ve && ve.HasAndArgs)
            {
                NestedHasAndArgs = true;
                RemainingArgsVar = ve.Variable;
                NestedArity--;
            }
        }

        public override MatchElementResult DoMatch(PSStackFrame callStack, object thingToMatch, int start, out int consumed)
        {
            // Only matches a single element
            if (thingToMatch is IList lst)
            {
                thingToMatch = lst[start];
            }

            consumed = 0;

            // In this context, treat a string as a list of characters.
            IList targetList = null;
            switch (thingToMatch)
            {
                case string str:
                    targetList = str.ToCharArray();
                    break;
                case IList ilist:
                    targetList = ilist;
                    break;
                case IEnumerable en:
                    //BUGBUGBUG - need a better way that doesn't copy the whole list.
                    targetList = new Vector(en);
                    break;
                default:
                    return MatchElementResult.NoMatch;
            }

            // If there are more values than pattern elements, terminate the match process early
            // unless there is a star function or &args patern element.
            if (targetList.Count > NestedArity && !NestedHasAndArgs && !HasStarFunction)
            {
                return MatchElementResult.NoMatch;
            }

            int argIndex = 0;
            int patternIndex = 0;

            while (patternIndex < NestedArity)
            {
                if (argIndex >= targetList.Count)
                {
                    return MatchElementResult.NoMatch;
                }

                var pe = Elements[patternIndex];
                var result = pe.DoMatch(callStack, targetList, argIndex, out consumed);
                if (result != MatchElementResult.Matched)
                {
                    return result;
                }

                patternIndex++;
                argIndex += consumed;
            }

            if (NestedHasAndArgs)
            {
                if (patternIndex < targetList.Count)
                {
                    callStack.SetLocal(RemainingArgsVar, new Slice(targetList, patternIndex, targetList.Count - patternIndex));
                }
                else
                {
                    callStack.SetLocal(RemainingArgsVar, null);
                }
            }
            else if (!HasStarFunction && patternIndex < NestedArity)
            {
                consumed = 0;
                return MatchElementResult.NoMatch;
            }

            consumed = 1;
            return MatchElementResult.Matched;
        }

        public override string ToString()
        {
            StringBuilder sb = new StringBuilder();
            sb.Append('[');
            foreach (var element in Elements)
            {
                if (sb.Length > 1)
                {
                    sb.Append(' ');
                }
                sb.Append(element.ToString());
            }
            sb.Append(']');

            return sb.ToString();
        }
    }

    //////////////////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// Class to handle the pattern/action clauses
    /// </summary>
    public sealed class PatternClause
    {
        public List<MatchElementBase> Elements;
        public Vector Actions;
        public bool HasAndArgs;
        public Symbol RemainingArgsVar;
        public s_Expr WhereCondition;
        public bool IsFunction;
        // the ariety of the pattern i.e. the number of pattern elements. FailElements are not included in the count.
        public int PatternArity;
        public bool AllowBacktracking = false;
        public bool HasStarFunction = false;

        public PatternClause(Vector patternElements, Vector actions, s_Expr whereCondition, bool isFunction, bool allowBacktracking)
        {
            WhereCondition = whereCondition;
            IsFunction = isFunction;
            AllowBacktracking = allowBacktracking;
            Elements = CompilePatternElements(patternElements, out PatternArity, out HasStarFunction);
            Actions = actions;
            var last = Elements[Elements.Count - 1];
            if (last is VarElement ve && ve.HasAndArgs)
            {
                HasAndArgs = true;
                RemainingArgsVar = ve.Variable;
                PatternArity--;
            }
        }

        public MatchElementResult Match(PSStackFrame callstack, Vector args, int start, bool starFunction, out object result, out int consumed)
        {
            result = null;
            consumed = 0;

            IList rest = null;

            int acount = args.Count;
            /* BUGBUGBUG - this needs to account for &args and elements with initializers
                            if (PatternArity > acount)
                            {
                                result = null;
                                return MatchElementResult.NoMatch;
                            }
            */
            int max = Elements.Count;
            if (HasAndArgs)
            {
                max--;
            }

            bool fail = false;
            int argIndex = start;
            int pecount = 0;    // counts active elements, not '!'
            for (int index = 0; index < max; index++)
            {
                var pe = Elements[index];

                if (pe is FailElement)
                {
                    fail = true;
                    continue;
                }

                if (pecount++ >= acount)
                {
                    if (pe.HasAndArgs)
                    {
                        break;
                    }
                    else if (pe.HasDefault)
                    {
                        pe.DoDefault(callstack);
                        continue;
                    }
                    else
                    {
                        result = null;
                        if (fail)
                        {
                            return MatchElementResult.Fail;
                        }

                        return MatchElementResult.NoMatch;
                    }
                }

                MatchElementResult matchStatus = pe.DoMatch(callstack, args, argIndex, out consumed);
                if (matchStatus != MatchElementResult.Matched)
                {
                    if (Braid.Debugger != 0)
                    {
                        if ((Braid.Debugger & DebugFlags.Trace) != 0 && (Braid.Debugger & DebugFlags.TraceException) == 0)
                        {
                            object av = argIndex >= args.Count ? "<OOB>" : args[argIndex];
                            Console.WriteLine(
                                $"    |  {Braid.spaces(Braid._evalDepth)}  " +
                                $"<Match failed matching pattern element #{index} '{pe}' against value '{Braid.Truncate(av)}'>");
                        }
                    }

                    if (fail)
                    {
                        return MatchElementResult.Fail;
                    }
                    else
                    {
                        return MatchElementResult.NoMatch;
                    }
                }

                argIndex += consumed;
            }

            if (WhereCondition != null && !Braid.IsTrue(Braid.Eval(WhereCondition)))
            {
                if (fail)
                {
                    return MatchElementResult.Fail;
                }
                else
                {
                    return MatchElementResult.NoMatch;
                }
            }

            if (HasAndArgs)
            {
                // Consume any left-over args. If there aren't any then set the variable to null
                rest = new Slice(args, argIndex, acount - argIndex);
                if (rest.Count == 0)
                {
                    callstack.SetLocal(RemainingArgsVar, null);
                }
                else
                {
                    callstack.SetLocal(RemainingArgsVar, rest);
                }
            }
            else if (!starFunction && argIndex < acount)
            {
                // If there are left-over args and the pattern didn't have a star function then the pattern fails.
                if (Braid.Debugger != 0)
                {
                    if ((Braid.Debugger & DebugFlags.Trace) != 0 && (Braid.Debugger & DebugFlags.TraceException) == 0)
                    {
                        Console.WriteLine(
                            $"    |  {Braid.spaces(Braid._evalDepth)}  Pattern match failed - {acount - argIndex} too many arguments were passed. Consider using &args if appropriate.");
                    }
                }
                consumed = 0;

                if (fail)
                {
                    return MatchElementResult.Fail;
                }
                else
                {
                    return MatchElementResult.NoMatch;
                }
            }

            if (Braid.Debugger != 0)
            {
                if ((Braid.Debugger & DebugFlags.Trace) != 0 && (Braid.Debugger & DebugFlags.TraceException) == 0)
                {
                    Console.WriteLine(
                        $"    |  {Braid.spaces(Braid._evalDepth)}  Pattern match succeeded - Running actions.");
                }
            }

            // Run the associated actions, special-casting an arg count of 1 as a scalar value
            RunActions(args.Count == 1 ? args[0] : args, Actions, out result);

            consumed = argIndex;
            return MatchElementResult.Matched;
        }

        static internal MatchElementBase CompilePatternElement(object pe)
        {
            int nestedArity;
            switch (pe)
            {
                case VectorLiteral vlit:
                    var nestedElements = CompilePatternElements(new Vector(vlit.ValueList), out nestedArity, out bool nestedStarFunction);
                    return new NestedPatternElement(nestedElements, nestedArity, nestedStarFunction);

                case DictionaryLiteral plit:
                    return new PropertyPatternElement(plit);

                case TypeLiteral tlit:
                    return new TypeElement(tlit, null);

                // handle (^int foo)
                case s_Expr sexpr when sexpr.Car is TypeLiteral tlit:
                    return new TypeElement(tlit, ((s_Expr)(sexpr.Cdr)).Car as Symbol);

                case Type type:
                    // this is ugly but the alternative is to have both a TypeLiteralElement
                    // and a TypeElement which may be worse than wrapping types in TypeLiteral objects.
                    return new TypeElement(new TypeLiteral(type), null);

                case s_Expr sexpr when sexpr.Car is Type type:
                    return new TypeElement(new TypeLiteral(type), ((s_Expr)(sexpr.Cdr)).Car as Symbol);

                case Regex re:
                    return new RegexElement(re, null);

                case s_Expr sexpr when sexpr.Car is Regex re:
                    return new RegexElement(re, ((s_Expr)(sexpr.Cdr)).Car as Symbol);

                case Symbol sym:
                    if (sym == Symbol.sym_fail)
                    {
                        return new FailElement();
                    }
                    else if (sym == Symbol.sym_underbar)
                    {
                        return new IgnoreElement();
                    }
                    else if (sym == Symbol.sym_null || sym == Symbol.sym_nil)
                    {
                        return new GenericElement(null, null);
                    }
                    else if (sym.Value[0] == '*')
                    {
                        return new StarFunctionElement(Symbol.FromString(sym.Value.Substring(1)));
                    }
                    else
                    {
                        return new VarElement(sym);
                    }

                case s_Expr sexpr when (sexpr.Car is Symbol sym && sexpr.Cdr is s_Expr sym2 && sym2.Car is Symbol pinsym && (sym.Value[0] == '%')):
                    return new VarElement(sym, pinsym);

                case s_Expr sexpr when (sexpr.Car is Symbol sym && (sym.Value[0] == '%')):
                    return new VarElement(sym, null);

                case s_Expr sexpr when (sexpr.Car is Symbol sym && sym.Value[0] == '*'):
                    return new StarFunctionElement(sym.Value.Substring(1), ((s_Expr)(sexpr.Cdr)).Car as Symbol);

                case s_Expr sexpr when (sexpr.Car is Symbol sym && sexpr.Cdr is s_Expr scdr):
                    var initVal = scdr.Car;
                    var meb = new VarElement(sym);
                    meb.SetDefaultValue(initVal);
                    return meb;

                case s_Expr sexpr when !(sexpr.Car is Symbol || sexpr.Car is Callable):
                    return new GenericElement(sexpr.Car, ((s_Expr)(sexpr.Cdr)).Car as Symbol);

                default:
                    return new GenericElement(pe, null);
            }
        }

        internal static List<MatchElementBase> CompilePatternElements(Vector elements, out int patternArity, out bool HasStarFunction)
        {
            var compiledElements = new List<MatchElementBase>();
            patternArity = 0;
            HasStarFunction = false;
            foreach (var pe in elements)
            {
                var element = CompilePatternElement(pe);
                if (!(element is FailElement))
                {
                    patternArity++;
                }

                if (element is StarFunctionElement)
                {
                    HasStarFunction = true;
                }

                compiledElements.Add(element);
            }

            return compiledElements;
        }

        static internal void RunActions(object arg, Vector actions, out object result)
        {
            result = null;
            int actionsCount = actions.Count;
            for (int index = 0; index < actionsCount; index++)
            {
                result = Braid.Eval(actions[index]);
                if (result is BraidFlowControlOperation)
                {
                    if (result is BraidReturnOperation)
                    {
                        return;
                    }
                    else if (result is BraidRecurOperation)
                    {
                        return;
                    }
                    else if (result is BraidFailOperation)
                    {
                        return;
                    }
                    else if (result is BraidBreakOperation)
                    {
                        break;
                    }
                    else if (result is BraidContinueOperation)
                    {
                        continue;
                    }
                }
            }
        }

        public override string ToString()
        {
            string patstring = string.Join(" ", Elements
                                                    .Select(p => {
                                                        if (p == null) return "nil";
                                                        if (p is IList ilist && ilist.Count == 0) return "[]";
                                                        return p.ToString();
                                                    })
                                                    .ToArray());
            if (WhereCondition != null)
            {
                patstring += " :where " + WhereCondition.ToString();
            }

            patstring += " -> ";
            string actionstring = string.Join(" ", Actions.Select(element => (element == null) ? "nil" : element.ToString()));

            return patstring + actionstring;
        }

        public string Signature
        {
            get => string.Join(" ", Elements.Select(obj => Utils.ToSourceString(obj)).ToArray());
        }
    }

    /////////////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// Implements the pattern matcher for Braid 
    /// </summary>
    public sealed class PatternFunction: Callable
    {
        // If true then the matcher. If false then its a 'matchp' call.
        public bool IsFunction;

        public TypeLiteral ReturnType { get; set; }

        public PatternFunction(string name, string file, int lineno, string text, int offset) : base(name)
        {
            this.FuncToCall = (Vector args) => this.Invoke(args);
            this.File = file;
            this.LineNo = lineno;
            this.Text = text;
            this.Offset = offset;
        }

        public ISourceContext Caller { set; get; } = Braid.CallStack.Caller;

        public List<PatternClause> Clauses = new List<PatternClause>();
        Vector DefaultActions    = null;
        bool   HadDefaultActions = false;
        Vector BeginActions      = null;
        bool   HadBeginActions   = false;
        Vector EndActions        = null;
        bool   HadEndActions     = false;

        public PatternFunction AddClause(s_Expr patterns, s_Expr actions, s_Expr whereClause, bool isFunction, bool allowBackTracking)
        {
            return AddClause(patterns == null ? null : new Vector(patterns), new Vector(actions), whereClause, isFunction, allowBackTracking);
        }

        public PatternFunction AddClause(Vector patterns, Vector actions, s_Expr whereClause, bool isFunction, bool allowBackTracking)
        {
            IsFunction = isFunction;
            if (patterns == null || patterns.Count == 0)
            {
                DefaultActions = actions;
                HadDefaultActions = true;
            }
            else if (patterns.Count == 1 && patterns[0] != null && patterns[0].ToString() == "^")
            {
                BeginActions = actions;
                HadBeginActions = true;
            }
            else if (patterns.Count == 1 && patterns[0] != null && patterns[0].ToString() == "$")
            {
                EndActions = actions;
                HadEndActions = true;
            }
            else
            {
                var clause = new PatternClause(patterns, actions, whereClause, isFunction, allowBackTracking);
                Clauses.Add(clause);
            }

            return this;
        }

        internal Func<Vector, object> GetFunction()
        {
            return Invoke;
        }

        public override object Invoke(Vector args)
        {
            int consumed = 0;
            return Invoke(args, null, false, ref consumed);
        }

        public override object Invoke(Vector args, Dictionary<string, NamedParameter> namedParameters)
        {
            int consumed = 0;
            return Invoke(args, namedParameters, false, ref consumed);
        }

        public object Invoke(Vector argvect, Dictionary<string, NamedParameter> namedParameters, bool starFunction, ref int consumed)
        {
            if (argvect == null)
            {
                var ie = new ArgumentException("argvect");
                Braid.BraidRuntimeException($"Invoking pattern function '{Name}': Invoking PatternFunction: {ie.Message}", ie, this);
            }

            object result;
            PSStackFrame callstack = Braid.CallStack;
            var oldNamedParameters = callstack.NamedParameters;
            try
            {
                if (Match(argvect, out result, starFunction, ref consumed))
                {
                    if (IsFunction && result is BraidReturnOperation retop)
                    {
                        return retop.ReturnValue;
                    }

                    return result;
                }
                else
                {
                    Braid.BraidRuntimeException($"Pattern function '{Name}': Match failed on '{Braid.Truncate(argvect)}'.");
                    return null;
                }
            }
            finally
            {
                callstack.NamedParameters = oldNamedParameters;
            }
        }

        internal bool Match(Vector args, out object result, bool starFunction, ref int consumed)
        {
            result = null;
            object ignored;
            PSStackFrame callStack;
            string argstr = null;

            if (Environment != null)
            {
                callStack = Braid.PushCallStack(
                    new PSStackFrame(this.File, this.Name, this, Environment));
            }
            else
            {
                callStack = Braid.CallStack;
            }

            var oldCaller = callStack.Caller;
            callStack.Caller = this;
            var oldCallStackArguments = callStack.Arguments;

            int totalConsumed = 0;
            try
            {
            recur_loop:

                if (Braid.Debugger != 0)
                {
                    if ((Braid.Debugger & DebugFlags.Trace) != 0 && (Braid.Debugger & DebugFlags.TraceException) == 0)
                    {

                        argstr = Braid.Truncate(string.Join(" ", args.Select(e => Utils.ToSourceString(e)).ToArray()));
                        Braid.WriteConsoleColor(ConsoleColor.Yellow, $"PTRN:  {Braid.spaces(Braid._evalDepth)} ({Name} {argstr})");
                    }
                }

                totalConsumed = 0;
                // Make the function args available as %1 %2 etc.
                callStack.Arguments = args;
                if (HadBeginActions && BeginActions != null)
                {
                    PatternClause.RunActions(args, BeginActions, out result);
                    if (result is BraidLang.BraidRecurOperation recur)
                    {
                        if (! IsFunction)
                        {
                            return true;
                        }

                        if (Braid._stop)
                        {
                            return false;
                        }

                        if (recur.Target == null || recur.Target == this)
                        {
                            args = recur.RecurArgs;
                            goto recur_loop;
                        }
                        else
                        {
                            return true;
                        }
                    }
                    else if (IsFunction && result is BraidLang.BraidReturnOperation retop)
                    {
                        result = retop.ReturnValue;
                        return true;
                    }
                }

                int start = 0;
                for (int index = 0; index < Clauses.Count; index++)
                {
                    var clause = Clauses[index];

                    if (Braid.Debugger != 0)
                    {
                        if ((Braid.Debugger & DebugFlags.Trace) != 0 && (Braid.Debugger & DebugFlags.TraceException) == 0)
                        {
                            Console.WriteLine("    |  {0} Matching clause #{1} << {2} >>", Braid.spaces(Braid._evalDepth), index,
                                Braid.Truncate(string.Join(" ", clause.Elements.Select(e => e.ToString()).ToArray())));
                        }
                    }

                    MatchElementResult status = clause.Match(callStack, args, start, starFunction, out result, out consumed);

                    // BUGBUGBUGBUG - If ! (fail) was specified in a pattern then the remaining
                    // elements must succeed or the whole match is a failure.?????????
                    if (status == MatchElementResult.Fail)
                    {
                        return false;
                    }

                    if (result is BraidLang.BraidFailOperation)
                    {
                        if (clause.AllowBacktracking)
                            continue;
                        else
                            return false;
                    }

                    totalConsumed += consumed;

                    if (status == MatchElementResult.Matched)
                    {
                        if (result is BraidLang.BraidRecurOperation recur)
                        {
                            if (! IsFunction)
                            {
                                return true;
                            }

                            if (Braid._stop)
                            {
                                return false;
                            }

                            // Needed for 'recur-to'.
                            if (recur.Target == null || recur.Target == this)
                            {
                                args = recur.RecurArgs;
                                goto recur_loop;
                            }
                            else
                            {
                                return true;
                            }
                        }
                        else if (IsFunction && result is BraidLang.BraidReturnOperation retop)
                        {
                            result = retop.ReturnValue;
                            return true;
                        }

                        return true;
                    }
                }

                // Handle pattern  | -> stuff...
                if (HadDefaultActions)
                {
                    if (DefaultActions != null && DefaultActions.Count > 0)
                    {
                        PatternClause.RunActions(args, DefaultActions, out result);
                        if (result is BraidLang.BraidRecurOperation recur)
                        {
                            if (! IsFunction)
                            {
                                return true;
                            }

                            if (Braid._stop)
                            {
                                return false;
                            }

                            if (recur.Target == null || recur.Target == this)
                            {
                                args = recur.RecurArgs;
                                goto recur_loop;
                            }
                            else
                            {
                                return true;
                            }
                        }
                        else if (IsFunction && result is BraidLang.BraidReturnOperation retop)
                        {
                            result = retop.ReturnValue;
                            return true;
                        }
                    }
                    return true;
                }

                // If there was no default handler, treat a failure to match as an error.
                if (args.Count == 0)
                {
                    Braid.BraidRuntimeException(
                        $"Processing pattern function '{Name}': The value to match "
                        + "was empty and no null pattern (| -> ) was specified.", null, this);
                }
                else
                {
                    Braid.BraidRuntimeException($"Processing pattern function '{Name}': "
                        + "No pattern matched the provided data: <<"
                        + Braid.Truncate(args).Trim(new char[] { '[', ']' }) // BUGBUGBUG - clean this up...
                        + ">>", null, this);
                }

                return false;
            }
            finally
            {
                if (HadEndActions && EndActions != null)
                {
                    PatternClause.RunActions(args, EndActions, out ignored);
                }

                if (Braid.Debugger != 0)
                {
                    if ((Braid.Debugger & DebugFlags.Trace) != 0 && (Braid.Debugger & DebugFlags.TraceException) == 0)
                    {
                        Braid.WriteConsoleColor(ConsoleColor.Yellow,
                            $"ENDP:  {Braid.spaces(Braid._evalDepth)} ({Name} {argstr}) <-- {Braid.Truncate(result)}");
                    }
                }

                callStack.Caller = oldCaller;
                callStack.Arguments = oldCallStackArguments;
                consumed = totalConsumed;

                if (Environment != null)
                {
                    Braid.PopCallStack();
                }
            }
        }

        /// <summary>
        /// Clone (copy) a function and its environment.
        /// </summary>
        /// <param name="environment"></param>
        /// <returns></returns>
        public override Callable CloneWithEnv(PSStackFrame environment)
        {
            var np = new PatternFunction(this.Name, this.File, this.LineNo, this.Text, this.Offset);
            np.Caller = this.Caller;
            np.IsFunction = this.IsFunction;
            if (np.IsFunction)
            {
                np.Environment = environment;
            }

            np.ReturnType = this.ReturnType;
            np.FType = this.FType;
            np.FuncToCall = this.FuncToCall;
            np.File = this.File;
            np.LineNo = this.LineNo;
            np.Clauses = this.Clauses;
            np.BeginActions = this.BeginActions;
            np.HadBeginActions = this.HadBeginActions;
            np.EndActions = this.EndActions;
            np.HadEndActions = this.HadEndActions;
            np.EndActions = this.EndActions;
            np.DefaultActions = this.DefaultActions;
            np.HadDefaultActions = this.HadDefaultActions;
            np.ReturnType = this.ReturnType;
            np.Name = this.Name;
            return np;
        }

        // Used for pretty printing source
        public string ToStringIndent(int n) => ToString(n, ' ');

        // Used in tracing
        public override string ToString() => ToString(0, '.');

        /// <summary>
        /// ToString function that formats patterns as source (more or less).
        /// </summary>
        /// <param name="depth">The nesting depth of the pattern</param>
        /// <param name="prefix">The prefix character to use when formatting the output</param>
        /// <returns></returns>
        public string ToString(int depth, char prefix)
        {
            string result = string.Empty;

            if (depth > 1000)
            {
                Braid.BraidRuntimeException("Processing .toString() on a list: recursion depth is greater than 1000; quitting.", null, this);
            }

            string indent = Braid.spaces(depth, prefix);
            if (BeginActions != null)
            {
                result += indent + "    | ^ -> " + BeginActions.ToString().Trim(new char[] { '[', ']' }) + "\n";
            }

            foreach (var clause in Clauses)
            {
                result += indent + "    | " + clause.ToString() + "\n";
            }

            if (DefaultActions != null && DefaultActions.Count > 0)
            {
                result += indent + "    | -> " + DefaultActions.ToString().Trim(new char[] { '[', ']' }) + "\n";
            }

            if (EndActions != null)
            {
                result += indent + "    | $ -> " + EndActions.ToString().Trim(new char[] { '[', ']' }) + "\n";
            }

            return result;
        }

        public Vector Arguments {get; set;} = new Vector();

        public string Signature
        {
            get {
                string result = "[ ";
                if (ReturnType != null)
                {
                    result = $"{ReturnType} [";
                }

                result += string.Join(" | ", Clauses.Select(c => c.Signature.Trim(new char[] { '[', ']' })));

                return result + " ]";
            }
        }
    }
}
