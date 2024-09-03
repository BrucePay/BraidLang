/////////////////////////////////////////////////////////////////////////////
//
// The Braid Programming Language - classes implementing literals
//
//
// Copyright (c) 2023 Bruce Payette (see LICENCE file) 
//
////////////////////////////////////////////////////////////////////////////

using System;
using System.Linq;
using System.Collections;
using System.Text;
using System.Text.RegularExpressions;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Management.Automation;
using System.Threading;
using System.Reflection;

namespace BraidLang
{
    ///////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// A base class for all of BraidLang's literal classes
    /// </summary>
    public abstract class BraidLiteral : ISourceContext
    {
        public int LineNo { get; set; }
        public string File { get; set; }
        public string Function { get; set; }
        public int Offset { get; set; }
        public string Text { get; set; } = string.Empty;

        public virtual object Value { get { return null; } set { } }
    }

    ///////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// Represents an expandable string literal in an s-Expression
    /// </summary>
    public sealed class ExpandableStringLiteral : BraidLiteral
    {
        public string RawStr { get; set; }

        public ExpandableStringLiteral(string str)
        {
            RawStr = str;
        }

        public override object Value
        {
            get
            {
                //BUGBUGBUG - most of the logic in Expand string should move here, with the fragments pre-calculated
                // and the code elements pre-parsed and verified.
                return Braid.ExpandString(RawStr);
            }
        }

        public override string ToString()
        {
            return RawStr;
        }
    }


    ///////////////////////////////////////////////////////////////////////////
    /// <summary>
    ///  Represents a literal type e.g. ^int in a Braid expression. The typename to
    ///  to type resolution is deferred to runtime. If used in the function position
    ///  it operates as a cast function.
    /// </summary>
    public sealed class TypeLiteral : BraidLiteral, IInvokeableValue
    {
        public TypeLiteral(string typeName, int lineno, string filename)
        {
            _tostringstring = "^" + typeName;

            // See if strict matching is requested BUGBUGBUG - finish this
            if (typeName[typeName.Length - 1] == '?')
            {
                _strict = false;
                TypeName = typeName.Substring(0, typeName.Length - 1);
            }
            else
            {
                _strict = true;
                TypeName = typeName;
            }

            LineNo = lineno;
            File = filename;

            // Set the invokable cast function.
            _function = args =>
            {
                if (args.Count == 0)
                {
                    return Value;
                }
                else if (args.Count == 1)
                {
                    return Invoke(args[0]);
                }

                Braid.BraidRuntimeException($"Type casting to {Value}: only 1 argument is allowed, not {args.Count}");
                return null;
            };
        }

        public TypeLiteral(Type type)
        {
            _type = type;
            _typeName = type.FullName;
            _strict = true;
        }

        public string TypeName
        {
            get => _typeName;
            private set => _typeName = value;
        }

        public Type Type
        {
            get
            {
                // If the type has been resolved, just return it...
                if (_type != null)
                {
                    return _type;
                }

                // BUGBUGBBUG - this needs to be fixed.
                string typename = TypeName.Replace('<', '[').Replace('>', ']');
                try
                {
                    _type = Braid.ConvertToHelper<Type>(typename);
                }
                catch (PSInvalidCastException psice)
                {
                    Braid.BraidRuntimeException($"Invalid type literal ^{TypeName}: no such type was found.", psice);
                }
                catch (InvalidCastException ice)
                {
                    Braid.BraidRuntimeException($"Invalid type literal ^{TypeName}: no such type was found.", ice);
                }

                return _type;
            }
        }

        Type _type;
        string _typeName;
        string _tostringstring;
        bool _strict;
        public bool Strict { get => _strict; set => _strict = value; }

        public override object Value { get => Type; }

        /// <summary>
        /// Convert an object to match the type represented by the literal.
        /// </summary>
        /// <param name="argument"></param>
        /// <returns></returns>
        public object Invoke(object arg)
        {
            if (_type == null)
            {
                var _ = this.Value;
            }

            if (_type == typeof(void))
            {
                return null;
            }

            if (_strict)
            {
                if (arg == null)
                {
                    if (_type == typeof(s_Expr))
                    {
                        return null;
                    }

                    Braid.BraidRuntimeException($"Strict type check failed: null cannot be cast to type ^{TypeName}");
                }

                if (arg is Type vtype)
                {
                    if (_type.IsAssignableFrom(vtype))
                    {
                        return arg;
                    }
                }

                var argType = arg.GetType();
                if (arg != null && _type.IsAssignableFrom(argType))
                {
                    return arg;
                }

                if (_type == typeof(string))
                {
                    if (arg is string)
                    {
                        return arg;
                    }

                    if (arg is Symbol sym)
                    {
                        return sym.Value;
                    }

                    if (arg is KeywordLiteral klit)
                    {
                        return klit.BaseName;
                    }

                    // BUGBUGBUG - this shouldn't be necessary '.foo shouldn't turn into a member literal?
                    if (arg is MemberLiteral mlit)
                    {
                        return mlit.ToString();
                    }
                }

                Braid.BraidRuntimeException($"Strict type check failed: " +
                     $"an object '{Braid.Truncate(arg)}' of type ^{arg?.GetType()} cannot be cast to type ^{TypeName}");
            }
            else
            {
                if (_type == typeof(Boolean))
                {
                    return Braid.BoxBool(Braid.IsTrue(arg));
                }

                // Special-case regex so it gets created with the right options.
                if (_type == typeof(Regex))
                {
                    if (arg is s_Expr sexpr && sexpr.IsQuote)
                    {
                        arg = sexpr.Cdr;
                    }

                    string strval = arg == null ? string.Empty : arg.ToString();
                    return new Regex(strval, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
                }

                try
                {
                    return Braid.ConvertTo(arg, _type);
                }
                catch (Exception e)
                {
                    Braid.BraidRuntimeException($"Soft type constraint violation: " +
                         $"an object '{Braid.Truncate(arg)}' of type ^{arg?.GetType()} cannot be cast type {_tostringstring}: {Braid.Truncate(e.Message)}", e);
                }
            }

            return null;
        }

        public bool TestValue(object valToTest, out object result)
        {
            result = null;

            if (Type == typeof(void))
            {
                return true;
            }

            if (valToTest is PSObject pso)
            {
                if (Type == typeof(PSObject))
                {
                    return true;
                }

                if (!(pso.BaseObject is PSCustomObject))
                {
                    valToTest = pso.BaseObject;
                }
            }

            if (_strict)
            {
                // When doing a strict type check, if the value is null, always fail the check.
                // In pattern matching this allows for an explicit null to be checked for. e.g.
                //      (matchp null | ^Exception -> "boom" | null -> "null")
                if (valToTest is null)
                {
                    // Special case null for lists - null is the empty list.
                    if (Type == typeof(s_Expr))
                    {
                        return true;
                    }

                    return false;
                }

                if (valToTest is Type vtype)
                {
                    if (_type.IsAssignableFrom(vtype))
                    {
                        result = valToTest;
                        return true;
                    }
                }

                var argType = valToTest.GetType();

                if (_type == typeof(string))
                {
                    if (valToTest is string)
                    {
                        result = valToTest;
                        return true;
                    }

                    if (valToTest is Symbol sym)
                    {
                        result = sym.Value;
                        return true;
                    }

                    if (valToTest is KeywordLiteral klit)
                    {
                        result = klit.Value;
                        return true;
                    }

                    // BUGBUGBUG - this shouldn't be necessary '.foo shouldn't turn into a member literal?
                    if (valToTest is MemberLiteral mlit)
                    {
                        result = mlit.ToString();
                        return true;
                    }
                }

                if (_type.IsAssignableFrom(argType))
                {
                    result = valToTest;
                    return true;
                }

                return false;
            }

            return Braid.TryConvertTo(valToTest, _type, out result);
        }


        // Then a type is used as a function (i.e. as a cast) this function is used
        // by the runtime.
        Func<Vector, object> _function;

        public Func<Vector, object> FuncToCall
        {
            get => _function;
        }

        public object Invoke(Vector args)
        {
            return FuncToCall(args);
        }

        public override string ToString() => _tostringstring;
    }

    ///////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// Represents a static property accessor e.g. .consolecolor/red
    /// </summary>
    public sealed class StaticPropertyLiteral : BraidLiteral, IInvokeableValue
    {
        string _literalString;
        Type _propertyType;
        PropertyInfo _propertyInfo;

        public override string ToString() => _literalString;

        public StaticPropertyLiteral(string literalString, Type propertyType, PropertyInfo propertyInfo)
        {
            _literalString = literalString;
            _propertyType = propertyType;
            _propertyInfo = propertyInfo;
        }

        public override object Value
        {
            get => _propertyInfo.GetValue(null);
        }

        Func<Vector, object> _function;
        public Func<Vector, object> FuncToCall
        {
            get
            {
                if (_function == null)
                {
                    _function = args =>
                    {
                        if (args.Count > 1)
                        {
                            Braid.BraidRuntimeException($"Error setting {_literalString}: a property setter only takes 1 argument.");
                        }

                        if (args.Count == 0)
                        {
                            return Value;
                        }

                        // BUGBUGBUG - why does this fail?
                        // object value = Braid.ConvertTo(args[0], _propertyType);

                        _propertyInfo.SetValue(null, args[0]);

                        return args[0];
                    };
                }
                return _function;
            }
        }

        public object Invoke(Vector args)
        {
            return FuncToCall(args);
        }
    }

    ///////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// Represents a static method accessor e.g .string/concat
    /// </summary>
    public sealed class StaticMethodLiteral : BraidLiteral, IInvokeableValue
    {
        string _literalString;
        Type _methodType;
        MethodInfo _methodInfo;

        public StaticMethodLiteral(string literalString, Type methodType, MethodInfo methodInfo)
        {
            _literalString = literalString;
            _methodType = methodType;
            _methodInfo = methodInfo;
        }

        public override string ToString() => _literalString;

        public override object Value
        {
            get => _methodInfo;
        }

        Func<Vector, object> _function;
        public Func<Vector, object> FuncToCall
        {
            get
            {
                if (_function == null)
                {
                    _function = args =>
                    {
                        return _methodInfo.Invoke(null, args.ToArray());
                    };
                }
                return _function;
            }
        }

        public object Invoke(Vector args)
        {
            return FuncToCall(args);
        }
    }

    ///////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// Represents an indexed argument reference e.g. %0 %1 %2 etc.
    /// </summary>
    public sealed class ArgIndexLiteral : BraidLiteral, IEquatable<ArgIndexLiteral>, IComparable
    {
        int Index;
        string str;

        public ArgIndexLiteral(int index, int lineno, string file)
        {
            Index = index;
            LineNo = lineno;
            File = file;
            str = $"%{Index}";
        }

        public override object Value
        {
            get
            {
                var callStack = Braid.CallStack;
                Vector arguments = callStack.Arguments;
                // Walk up the scope chain to see if a parent scope has arguments
                while (arguments == null && callStack != null)
                {
                    arguments = callStack.Arguments;
                    callStack = callStack.Parent;
                }

                if (arguments == null || Index >= arguments.Count)
                {
                    Braid.BraidRuntimeException(
                        $"pattern argument index '%{Index}' was beyond the length of the argument collection.");
                }

                return arguments[Index];
            }

            set
            {
                var callStack = Braid.CallStack;
                Vector arguments = callStack.Arguments;
                // Walk up the scope chain to see if a parent scope has arguments
                while (arguments == null && callStack != null)
                {
                    arguments = callStack.Arguments;
                    callStack = callStack.Parent;
                }

                if (arguments == null || Index >= arguments.Count)
                {
                    Braid.BraidRuntimeException(
                        $"pattern argument index '%{Index}' was beyond the length of the argument collection.");
                }

                arguments[Index] = value;
            }
        }

        public bool Equals(ArgIndexLiteral aie)
        {
            return Index == aie.Index;
        }

        public int CompareTo(object obj)
        {
            if (obj is ArgIndexLiteral aie)
            {
                if (aie.Index > Index)
                    return 1;
                if (aie.Index == Index)
                    return 0;
                return -1;
            }
            else
            {
                return -1;
            }
        }

        public override bool Equals(object obj)
        {
            if (obj is ArgIndexLiteral aie)
            {
                return aie.Index == Index;
            }
            return false;
        }

        public override int GetHashCode() => Index;

        public override string ToString() => str;
    }

    ///////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// Represents a keyword token in BraidLang i.e. :aKeyword
    /// As arguments, keywords are essentially literal strings.
    /// As functions, they access their namespace in a dictionary,
    /// </summary>
    public sealed class KeywordLiteral : BraidLiteral, IEquatable<object>, IComparable, IInvokeableValue
    {
        string _keyword;
        string _baseName;
        bool _requiresArg = false;

        KeywordLiteral(string name)
        {
            if (string.IsNullOrWhiteSpace(name))
            {
                Braid.BraidRuntimeException("When creating a keyword object, the name cannot be null, empty or just whitespace.");
            }

            _keyword = name;
            _baseName = name.Substring(1);
            if (_keyword[_keyword.Length - 1] == ':')
            {
                _requiresArg = true;
                _baseName = _baseName.Substring(0, _baseName.Length - 1);
            }

            KeywordLiteral keywordOut;
            if (_keywordTable.TryGetValue(name, out keywordOut))
            {
                _keywordId = keywordOut._keywordId;
            }
            else
            {
                _keywordId = Interlocked.Increment(ref _nextKeywordId);
            }
        }

        static object _lockObj = new object();

        public static KeywordLiteral FromString(string name)
        {
            KeywordLiteral keywordOut;

            lock (_lockObj)
            {
                if (_keywordTable.TryGetValue(name, out keywordOut))
                {
                    return keywordOut;
                }

                keywordOut = new KeywordLiteral(name);
                _keywordTable[name] = keywordOut;
                return keywordOut;
            }
        }

        static int _nextKeywordId;

        // Used to intern keywords
        public static ConcurrentDictionary<string, KeywordLiteral> _keywordTable =
            new ConcurrentDictionary<string, KeywordLiteral>(StringComparer.OrdinalIgnoreCase);

        public int KeywordId { get { return _keywordId; } }
        int _keywordId;

        /// <summary>
        /// BUGBUGBUG - this should really be 'this' - keywords are supposed to evaluate to themselves.
        /// </summary>
        public override object Value { get => this; }

        public bool RequiresArgument { get => _requiresArg; }

        public string BaseName { get => _baseName; }

        public override string ToString() => _baseName;

        public override int GetHashCode() => _keywordId;

        public override bool Equals(object obj)
        {
            if (obj == null) return false;
            if (obj is KeywordLiteral sobj)
            {
                return this._keywordId == sobj._keywordId;
            }
            else
            {
                return false;
            }
        }

        public bool Equals(KeywordLiteral kw) => this._keywordId == kw._keywordId;

        public int CompareTo(object obj)
        {
            if (obj is KeywordLiteral keyword)
            {
                if (this.KeywordId == keyword.KeywordId)
                    return 0;

                return string.Compare(_keyword, keyword._keyword, StringComparison.OrdinalIgnoreCase);
            }
            else
            {
                return -1;
            }
        }

        // Implicit conversion from keyword to string/regex and vise versa.
        public static implicit operator String(KeywordLiteral s) => s._keyword;

        public static implicit operator KeywordLiteral(string str) => KeywordLiteral.FromString(":" + str);

        public static implicit operator Regex(KeywordLiteral s) => new Regex(s._keyword, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

        public static implicit operator KeywordLiteral(Regex re) => KeywordLiteral.FromString(":" + re.ToString());

        // Returns a function that will look up the key in the dictionary
        Func<Vector, object> _function;
        public Func<Vector, object> FuncToCall
        {
            get
            {
                if (_function == null)
                {
                    _function = (args) =>
                    {
                        int ac = args.Count;
                        if (ac < 1 || ac > 2)
                        {
                            Braid.BraidRuntimeException(
                                $":{_keyword}: requires one (for get) or two (for set) arguments, the first of which must be a dictionary.");
                        }

                        IDictionary dict = args[0] as IDictionary;
                        if (dict == null)
                        {
                            string typestr = args[0] == null ? "null" : args[0].GetType().ToString();
                            Braid.BraidRuntimeException(
                                $"The first argument to keyword '{_keyword}' must be a dictionary, not ^{typestr}");
                        }

                        if (ac == 1)
                        {
                            // retrieve the key
                            // return dict[this];
                            // BUGBUGBUG KEYWORD - remove this when keywords are rationaized
                            return dict[this];
                        }
                        else
                        {
                            // update the key and return the updated dictionary
                            // BUGBUGBUG KEYWORD - remove this when keywords are rationaized
                            // dict[this] = args[1];
                            dict[this] = args[1];
                            return dict;
                        }
                    };
                }
                return _function;
            }
        }

        public object Invoke(Vector args)
        {
            return FuncToCall(args);
        }

        public static KeywordLiteral klit_defm = KeywordLiteral.FromString(":defm");
    }
    ///////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// Class representing a member access e.g. (.substring "hello" 1 2)
    /// </summary>
    public sealed class MemberLiteral : BraidLiteral, IInvokeableValue
    {
        string _member;
        Symbol _member_symbol;
        string _toString;
        string StaticTypeName { get; set; }
        Type _staticType;
        bool quiet; // If a nonexistent property is accessed, return null instead of throwing an error

        public MemberLiteral(string member, int lineno, string file)
        {
            _toString = member;
            _member = member.Substring(1);
            _member_symbol = Symbol.FromString(_member);

            if (_member[0] == '?')
            {
                quiet = true;
                _member = _member.Substring(1);
            }
            else
            {
                quiet = false;
            }

            string[] parts = _member.Split('/');
            if (parts.Length == 2)
            {
                StaticTypeName = parts[0];
                _member = parts[1];
            }

            LineNo = lineno;
            File = file;
        }

        public override object Value
        {
            get
            {
                if (StaticTypeName != null)
                {
                    // BUGBUGBUG - add better error handling here for bad type names
                    // BUGBUGBUG - need better logic around when it's safe to resolve type names
                    if (_staticType == null)
                    {
                        try
                        {
                            // BUGBUGBUGBUG - this should work but does not - _staticType = Braid.ConvertToHelper<Type>(StaticTypeName);
                            _staticType = Braid.ConvertTo(StaticTypeName, typeof(Type)) as Type;

                        }
                        catch (Exception e)
                        {
                            while (e is MethodInvocationException)
                            {
                                e = e.InnerException;
                            }

                            if (e is BraidUserException)
                            {
                                throw e;
                            }

                            Braid.BraidRuntimeException($"Error resolving static reference '{_toString}': {e.Message}", e);
                        }
                    }

                    var propertyInfo = _staticType.GetProperty(_member,
                                            BindingFlags.Public | BindingFlags.Static | BindingFlags.IgnoreCase);
                    if (propertyInfo != null)
                    {
                        return propertyInfo.GetValue(null);
                    }

                    var fieldInfo = _staticType.GetField(_member,
                                                        BindingFlags.Public
                                                        | BindingFlags.Static
                                                        | BindingFlags.IgnoreCase
                                                        );

                    if (fieldInfo != null)
                    {
                        return fieldInfo.GetValue(null);
                    }
                }

                return this;
            }
        }

        // Returns a function that will look up the member on the object
        // or execute a method.
        Func<Vector, object> _function;
        public Func<Vector, object> FuncToCall
        {
            get
            {
                if (_function == null)
                {
                    _function = args =>
                    {
                        // Deal with PSObjects first
                        if (args.Count > 0 && args.Any(o => o is PSObject))
                        {
                            // Invoke using PowerShell reflection
                            return Braid.InvokeMember(quiet, _member, args);
                        }

                        // copy the list because we're going to mutate it.
                        args = new Vector(args);
                        object obj = null;
                        Type otype = null;

                        if (_staticType != null)
                        {
                            args.Insert(0, _staticType);
                            otype = _staticType;
                        }
                        else if (StaticTypeName != null)
                        {
                            try
                            {
                                _staticType = (Type)Braid.ConvertTo(StaticTypeName, typeof(Type));
                            }
                            catch (Exception e)
                            {
                                while (e is MethodInvocationException)
                                {
                                    e = e.InnerException;
                                }

                                Braid.BraidRuntimeException(
                                        $"Error resolving static reference '{_toString}': {e.Message}", e);
                            }

                            args.Insert(0, _staticType);
                            otype = _staticType;
                        }
                        else if (args.Count > 0)
                        {
                            obj = args[0];
                            if (obj == null && quiet)
                            {
                                return null;
                            }

                            //BUGBUGBUG - figure out how to deal with null here.

                            otype = obj.GetType();
                        }

                        if (obj is Type t && (!(obj is System.Reflection.Emit.TypeBuilder)))
                        {
                            otype = t;
                        }

                        string name = _member;

                        if (otype == null)
                        {
                            if (quiet)
                            {
                                return null;
                            }

                            Braid.BraidRuntimeException(
                                $"member '{_toString}' can't be accessed without specifying the non-null " +
                                $"type or object implementing the member.");
                        }

                        PropertyInfo propertyInfo = null;
                        try
                        {
                            propertyInfo = otype.GetProperty(name, BindingFlags.Public
                                          | BindingFlags.Static | BindingFlags.Instance
                                          | BindingFlags.FlattenHierarchy | BindingFlags.IgnoreCase);
                        }
                        catch (NotSupportedException)
                        {
                            // Ignore it.
                        }

                        if (propertyInfo != null)
                        {
                            try
                            {
                                if (args.Count > 1)
                                {
                                    if (_staticType != null)
                                        propertyInfo.SetValue(null, args[1]);
                                    else
                                        propertyInfo.SetValue(obj, args[1]);

                                    // On set, we return the object instead of the property value so sts can be chained: (obj | .x 1 | .y 2)
                                    return args[0];
                                }
                                else
                                {
                                    if (_staticType != null)
                                        return propertyInfo.GetValue(null);
                                    else
                                        // BUGBUGBUG - this fails with "Object does not match target type." sometimes
                                        // even when the types are correct.
                                        return propertyInfo.GetValue(obj);
                                }
                            }
                            catch (System.Reflection.TargetException te)
                            {
                                if (quiet)
                                    return null;

                                Braid.BraidRuntimeException(
                                    $"Accessing property '{_toString}' on type '^{otype}' failed with message: {te.Message}", te);
                            }
                        }

                        FieldInfo fieldInfo = null;
                        try
                        {
                            fieldInfo = otype.GetField(name, BindingFlags.Public | BindingFlags.Static
                                        | BindingFlags.Instance | BindingFlags.FlattenHierarchy | BindingFlags.IgnoreCase);
                        }
                        catch (NotSupportedException)
                        {
                            // Ignore it.
                        }

                        if (fieldInfo != null)
                        {
                            try
                            {
                                if (args.Count > 1)
                                {
                                    if (_staticType != null)
                                        fieldInfo.SetValue(null, args[1]);
                                    else
                                        fieldInfo.SetValue(obj, args[1]);

                                    // on set, we return the object value so sets can be chained.
                                    return args[0];
                                }
                                else
                                {
                                    if (_staticType != null)
                                        return fieldInfo.GetValue(null);
                                    else
                                        return fieldInfo.GetValue(obj);
                                }
                            }
                            catch (Exception te)
                            {
                                if (quiet)
                                    return null;

                                Braid.BraidRuntimeException(
                                    $"Accessing field '{_toString}' on type ^{otype} failed with message: {te.Message}", te);
                            }
                        }

                        MethodInfo methodInfo = null;
                        try
                        {
                            var margTypes = args.Skip(1).Select(it => it == null ? typeof(object) : it.GetType()).ToArray();
                            var paramMod = args.Skip(1).Select(it => new ParameterModifier()).ToArray();
                            // Try for exact match
                            methodInfo = otype.GetMethod(
                                name,
                                BindingFlags.Public | BindingFlags.Static | BindingFlags.Instance |
                                    BindingFlags.FlattenHierarchy | BindingFlags.IgnoreCase,
                                null,
                                margTypes,
                                paramMod
                            );

                            if (methodInfo == null)
                            {
                                // Slow path - Search through all the methods matching on name and arity.
                                methodInfo = otype.GetMethods(BindingFlags.Public | BindingFlags.Static | BindingFlags.Instance |
                                            BindingFlags.FlattenHierarchy | BindingFlags.IgnoreCase)
                                        .Where(m => m.Name.Equals(name, StringComparison.OrdinalIgnoreCase)
                                            && m.GetParameters().Length == args.Count - 1)
                                        .FirstOrDefault();
                            }
                        }
                        catch (NotSupportedException)
                        {
                            // Ignore it.
                        }

                        if (methodInfo != null)
                        {
                            try
                            {
                                if (_staticType != null)
                                {
                                    return methodInfo.Invoke(null, args.Skip(1).ToArray());
                                }
                                else
                                {
                                    bool hadByRef = false; // handle byref/out parameters

                                    var oargs = new object[args.Count - 1];
                                    Type[] ptype = methodInfo.GetParameters().Select(p => p.ParameterType).ToArray();
                                    for (int i = 0; i < args.Count - 1; i++)
                                    {
                                        var arg = args[i + 1];
                                        if (ptype[i].IsByRef)
                                        {
                                            hadByRef = true;
                                        }

                                        if (ptype[i] == typeof(object[]) && arg is Vector v)
                                        {
                                            oargs[i] = v.ToArray();
                                        }
                                        else if (arg != null && !ptype[i].IsByRef && !ptype[i].IsAssignableFrom(arg.GetType()))
                                        {
                                            // Convert the arg to the target type. At some point, should consider best match not first.

                                            oargs[i] = Braid.ConvertTo(arg, ptype[i]);
                                        }
                                        else
                                        {
                                            oargs[i] = arg;
                                        }
                                    }

                                    // For handling ByRefs, save the args array
                                    // so if you have something like
                                    //      (.trygetvalue {:a 1 :b 2} "b" 'xxx)
                                    // then the result will be stored in the variable 'xxx'
                                    object[] refargs = null;
                                    if (hadByRef)
                                    {
                                        refargs = new object[ptype.Length];
                                        Array.Copy(oargs, refargs, ptype.Length);
                                    }

                                    var result = methodInfo.Invoke(obj, oargs);

                                    if (hadByRef)
                                    {
                                        for (int i = 0; i < ptype.Length; i++)
                                        {
                                            // If this was a ByReg argument and the source value was
                                            // a symbol, save the value returned in the local variable
                                            // corresponding to the symbol.
                                            if (ptype[i].IsByRef && refargs[i] is Symbol sym)
                                            {
                                                Braid.CallStack.SetLocal(sym, oargs[i]);
                                            }
                                        }
                                    }

                                    return result;
                                }
                            }
                            catch (Exception te)
                            {
                                if (quiet)
                                {
                                    return null;
                                }

                                while (te is TargetInvocationException)
                                {
                                    te = te.InnerException;
                                }

                                if (te is BraidUserException)
                                {
                                    throw te;
                                }

                                Braid.BraidRuntimeException(
                                    $"Invoking method '{_toString}' on type '^{otype}' failed with message: {te.Message}", te);
                            }
                        }

                        // See if there is a Braid "method".
                        if (otype != null)
                        {
                            Callable methodBody = BraidTypeBuilder.GetMethodFromMap(otype, _member_symbol);
                            if (methodBody != null)
                            {
                                args[0] = obj;
                                var result = methodBody.Invoke(args);
                                return result;
                            }
                        }

                        // Try accessing the members on the type for this object  e.g. IsClass, etc.
                        if (obj is Type)
                        {
                            propertyInfo = typeof(Type).GetProperty(name, BindingFlags.Public | BindingFlags.Static
                                    | BindingFlags.Instance | BindingFlags.FlattenHierarchy | BindingFlags.IgnoreCase);

                            if (propertyInfo != null)
                            {
                                if (args.Count > 1)
                                {
                                    propertyInfo.SetValue(obj, args[1]);

                                    // BUGBUGBUG on set, should we return the property value or the object so that sets can be chained?
                                    //return args[1];
                                    return args[0];
                                }
                                else
                                {
                                    return propertyInfo.GetValue(obj);
                                }
                            }

                            fieldInfo = typeof(Type).GetField(name,
                                                            BindingFlags.Public
                                                            | BindingFlags.Static
                                                            | BindingFlags.Instance
                                                            | BindingFlags.FlattenHierarchy
                                                            | BindingFlags.IgnoreCase);
                            if (fieldInfo != null)
                            {
                                if (args.Count > 1)
                                {
                                    fieldInfo.SetValue(obj, args[1]);

                                    // BUGBUGBUG on set, should we return the property value or the object
                                    //return args[1];
                                    return args[0];
                                }
                                else
                                {
                                    return fieldInfo.GetValue(obj);
                                }
                            }

                            var margTypes = args.Skip(1).Select(it => it == null ? typeof(object) : it.GetType()).ToArray();
                            var paramMod = args.Skip(1).Select(it => new ParameterModifier()).ToArray();
                            methodInfo = typeof(Type).GetMethod(
                                name,
                                BindingFlags.Public | BindingFlags.Static | BindingFlags.Instance |
                                    BindingFlags.FlattenHierarchy | BindingFlags.IgnoreCase,
                                null,
                                margTypes,
                                paramMod
                            );

                            if (methodInfo == null)
                            {
                                methodInfo = typeof(Type)
                                    .GetMethods(BindingFlags.Public | BindingFlags.Static | BindingFlags.Instance |
                                                BindingFlags.FlattenHierarchy | BindingFlags.IgnoreCase)
                                    .Where(m => {
                                        // BUGBUGBUG Console.WriteLine("method {name} args {args.Count-1} matching {m.Name} {m.GetParameters().Length}");
                                        return m.Name.Equals(name, StringComparison.OrdinalIgnoreCase) && m.GetParameters().Length == args.Count - 1;
                                    })
                                    .FirstOrDefault();
                            }

                            if (methodInfo != null)
                            {
                                var oargs = new object[args.Count - 1];
                                Type[] ptype = methodInfo.GetParameters().Select(p => p.ParameterType).ToArray();
                                for (int i = 0; i < args.Count - 1; i++)
                                {
                                    var arg = args[i + 1];
                                    if (ptype[i] == typeof(object[]) && arg is Vector v)
                                    {
                                        oargs[i] = v.ToArray();
                                    }
                                    else
                                    {
                                        oargs[i] = arg;
                                    }
                                }

                                try
                                {
                                    return methodInfo.Invoke(obj, oargs);
                                }
                                catch (TargetInvocationException tie)
                                {
                                    Exception e = tie;
                                    while (e is TargetInvocationException te)
                                    {
                                        e = te.InnerException;
                                    }

                                    Braid.BraidRuntimeException(
                                        "An exception was thrown invoking method '{name}': {e.Message}", e);
                                }
                            }

                            // See if there is a Braid pseudo-method.
                            if (otype != null)
                            {
                                Callable methodBody = BraidTypeBuilder.GetMethodFromMap(typeof(Type), _member_symbol);
                                if (methodBody != null)
                                {
                                    args[0] = obj;
                                    return methodBody.Invoke(args);
                                }
                            }
                        }

                        if (quiet)
                        {
                            return null;
                        }

                        // Handle member-not-found error. This is essentially the same code as above so things should be refactored.
                        // The goal is to see if a member with the designated name exists even though it didn't match the other
                        // requirements and report that fact.
                        var instanceMembersFound = otype.GetMembers(BindingFlags.Public | BindingFlags.Instance |
                                        BindingFlags.FlattenHierarchy | BindingFlags.IgnoreCase)
                            .Where(m => m.Name.Equals(name, StringComparison.OrdinalIgnoreCase))
                            .ToArray();

                        var staticMembersFound = otype.GetMembers(BindingFlags.Public | BindingFlags.Static |
                            BindingFlags.FlattenHierarchy | BindingFlags.IgnoreCase)
                            .Where(m => m.Name.Equals(name, StringComparison.OrdinalIgnoreCase))
                            .ToArray();

                        string memberList = "";

                        if (instanceMembersFound.Length > 0 || staticMembersFound.Length > 0)
                        {
                            // Report missing member with possible alternate members
                            foreach (var m in instanceMembersFound)
                            {
                                if (memberList.Length > 0)
                                {
                                    memberList += ", ";
                                }
                                memberList += m.ToString();
                            }

                            foreach (var m in staticMembersFound)
                            {
                                if (memberList.Length > 0)
                                {
                                    memberList += ", ";
                                }
                                memberList += "(S) " + m.ToString();
                            }

                            if (_staticType == null)
                            {
                                Braid.BraidRuntimeException(
                                    $"No instance member '.{_member}' with " +
                                    $"arity {args.Count - 1} on '^{otype}' was found; available members: " + memberList,
                                    null,
                                    Braid.CallStack.Caller);
                            }
                            else
                            {
                                Braid.BraidRuntimeException(
                                    $"No static member '.{_member}' with " +
                                    $"arity {args.Count - 1} on '^{otype}' was found; available members: " + memberList,
                                    null,
                                    Braid.CallStack.Caller);
                            }
                        }
                        else
                        {
                            // Report a missing member when there are no alteratives available
                            Braid.BraidRuntimeException(
                                $"No member matching '.{_member}' with arity {args.Count - 1} on '^{otype}' was found.");
                        }

                        throw new InvalidOperationException($"*** This shouldn't happen! Fell through method lookup for name: '{name}' ***");
                    };
                }

                return _function;
            }
        }

        public object Invoke(Vector args)
        {
            return FuncToCall(args);
        }

        public override string ToString() => _toString;
    }

    ///////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// A class representing a literal value in Braid.
    /// </summary>
    public sealed class ValueLiteral : BraidLiteral
    {
        object _value;

        public ValueLiteral(object obj)
        {
            _value = obj;
        }

        public override object Value { get => _value; set { _value = value; } }

        public override string ToString() => _value == null ? "nil" : _value.ToString();
    }

    ///////////////////////////////////////////////////////////////////////////
    // 
    //  #{ element1 element2 element3 ... }
    /// <summary>
    /// Represents a literal set; syntax-wise this looks like: #{ "one" "two" "three" }
    /// </summary>
    public sealed class HashSetLiteral : BraidLiteral, IInvokeableValue
    {
        public s_Expr ValueList { get; set; }

        public HashSetLiteral(s_Expr valueList, int lineno)
        {
            LineNo = lineno;
            ValueList = valueList;
        }

        public override object Value
        {
            get
            {
                var callStack = Braid.CallStack;
                var result = new HashSet<object>(new ObjectComparer());
                s_Expr ptr = ValueList;
                while (ptr != null)
                {
                    var val = ptr.Car;
                    object obj;

                    if (val is s_Expr sexpr && sexpr.IsSplat)
                    {
                        if (sexpr.Cdr is Symbol sym)
                        {
                            obj = callStack.GetValue(sym);
                        }
                        else
                        {
                            obj = Braid.Eval(((s_Expr)sexpr.Cdr).Car);
                        }

                        if (!(obj is string) && obj is IEnumerable ienum)
                        {
                            foreach (var e in ienum)
                            {
                                result.Add(e);
                            }
                        }
                        // don't add a splatted null
                        else if (obj != null)
                        {
                            result.Add(obj);
                        }
                    }
                    else
                    {
                        obj = Braid.Eval(ptr.Car, true, true);
                        result.Add(obj);
                    }

                    ptr = (s_Expr)ptr.Cdr;
                }
                return result;
            }
        }

        public object Invoke(Vector args)
        {
            if (args == null || args.Count == 0)
            {
                return Value;
            }

            if (args.Count > 2 || args[0] == null)
            {
                Braid.BraidRuntimeException("Indexing into a hash set requires takes one (get) or two (set) arguments .");
            }

            var result = (HashSet<object>)Value;
            if (args.Count == 2)
            {
                bool set = Braid.IsTrue(args[1]);
                if (result.Contains(args[0]))
                {
                    if (!set)
                    {
                        result.Remove(args[0]);
                    }
                }
                else
                {
                    if (set)
                    {
                        result.Add(args[0]);
                    }
                }

                return result;
            }

            return result.Contains(args[0]);
        }

        public Func<Vector, object> FuncToCall { get => Invoke; }

    }

    ///////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// Implements aa Vector literal Vector in Braid: [ 1 2 3 4 ]
    /// </summary>
    public sealed class VectorLiteral : BraidLiteral, IInvokeableValue
    {
        public s_Expr ValueList { get; private set; }

        public VectorLiteral(s_Expr valueList, int lineno)
        {
            LineNo = lineno;
            ValueList = valueList;
        }

        public override object Value
        {
            get
            {
                if (ValueList == null)
                {
                    return new Vector();
                }

                Vector result;
                Dictionary<string, NamedParameter> namedParameters;
                Braid.EvaluateArgs(Braid.CallStack, false, true, false, ValueList, FunctionType.Function, out result, out namedParameters);
                return result;
            }
        }

        public string cachedToString = null;
        public override string ToString()
        {
            if (cachedToString != null)
            {
                return cachedToString;
            }

            if (ValueList == null || ValueList.Count == 0)
            {
                return (cachedToString = "[]");
            }

            StringBuilder sb = new StringBuilder();
            sb.Append('[');
            bool first = true;
            s_Expr list = ValueList;
            while (list != null)
            {
                if (Braid._stop)
                {
                    break;
                }

                if (first)
                {
                    first = false;
                }
                else
                {
                    sb.Append(' ');
                }

                object item = list.Car;
                if (item == null)
                {
                    sb.Append("nil");
                }
                else
                {
                    sb.Append(Utils.ToSourceString(item));
                }
                list = (s_Expr)list.Cdr;
            }

            sb.Append(']');
            cachedToString = sb.ToString();
            return cachedToString;
        }

        public object Visit(Callable func, bool visitLambdas)
        {
            Vector result = new Vector();
            Vector parameters = new Vector();
            parameters.Add(null);
            foreach (var e in this.ValueList)
            {
                parameters[0] = e;
                result.Add(func.Invoke(parameters));
            }

            return result;
        }

        public Func<Vector, object> FuncToCall { get => Invoke; }

        public object Invoke(Vector args)
        {
            if (args.Count > 2)
            {
                Braid.BraidRuntimeException($"Vector as a function requires 1 or 2 non-null arguments, {args.Count} were passed.");
            }

            if (args.Count == 0)
            {
                return Value;
            }

            int index = 0;
            try
            {
                if (args[0] == null)
                {
                    index = 0;
                }

                if (args[0] is int iindex)
                {
                    index = iindex;
                }
                else if (args[0] is Vector vect)
                {
                    // handle abc[3]
                    index = Braid.ConvertToHelper<int>(vect[0]);
                }
                else
                {
                    index = Braid.ConvertToHelper<int>(args[0]);
                }
            }
            catch (Exception e)
            {
                Braid.BraidRuntimeException(
                    $"Indexing vector literal, vector index '{args[0]}' was invalid:" + e.Message);
            }

            Vector computedList = (Vector)Value;

            if (index < 0)
            {
                index = computedList.Count + index;
            }

            if (args.Count == 1)
            {
                return computedList[index];
            }

            computedList[index] = args[1];
            return computedList;
        }
    }

    ///////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// Implements a dictionary literal in Braid: { :a 1 :b 2 :c 3 }
    /// </summary>
    public sealed class DictionaryLiteral : BraidLiteral, IInvokeableValue
    {
        public Vector ValueList { get; set; }

        public DictionaryLiteral(IEnumerable valueList, string file, int lineno, string text, int offset)
        {
            File = file;
            LineNo = lineno;
            Text = text;
            Offset = offset;
            Function = "<dictionary literal>";

            if (valueList != null)
            {
                ValueList = new Vector();
                var keys = new Vector();
                bool key = true;
                bool noSplats = true;
                foreach (var val in valueList)
                {
                    // Can't check for duplicate keys if there are splatted values in the list
                    if (val is s_Expr sexpr && sexpr.IsSplat)
                    {
                        noSplats = false;
                    }

                    if (noSplats && key)
                    {
                        if (keys.Contains(val))
                        {
                            throw new BraidCompilerException(text, offset, Braid._current_file, lineno,
                                $"Dictionary literal contains duplicate key '{val}'.");
                        }
                        keys.Add(val);
                    }
                    key = !key;

                    ValueList.Add(val);
                }


            }
        }

        public override object Value
        {
            get
            {
                var callStack = Braid.CallStack;
                var oldCaller = callStack.Caller;
                callStack.Caller = this;
                try
                {
                    var result = new Dictionary<object, object>(new ObjectComparer());

                    if (ValueList == null)
                    {
                        return result;
                    }

                    object keyVal = null;
                    foreach (var e in ValueList)
                    {
                        if (e is s_Expr sexpr && sexpr.IsSplat)
                        {
                            // BUGBUGBUG - @foo should be a dotted pair (splat . foo) not (cons splat (cons val nil))
                            SplatDictionary(result, typeof(object), typeof(object), sexpr.Cdr);
                            continue;
                        }

                        if (keyVal == null)
                        {
                            keyVal = Braid.Eval(e);
                        }
                        else
                        {
                            result[keyVal] = Braid.Eval(e);
                            keyVal = null;
                        }
                    }

                    if (keyVal != null)
                    {
                        Braid.BraidRuntimeException(
                            $"A dictionary literal requires an even of items; dictionary key '{keyVal}' has no associated value.",
                                null, this);
                    }

                    return result;
                }
                finally
                {
                    callStack.Caller = oldCaller;
                }
            }
        }

        public object Invoke(Vector args)
        {
            if (args == null || args.Count == 0)
            {
                return Value;
            }

            if (args.Count > 2 || args[0] == null)
            {
                Braid.BraidRuntimeException(
                    "Indexing into a dictionary requires a single non-null argument which is the key into the dictionary.");
            }

            var result = (IDictionary)Value;
            if (args.Count == 2)
            {
                result[args[0]] = args[1];
                return result;
            }

            return result[args[0]];
        }

        public Func<Vector, object> FuncToCall { get => Invoke; }

        private string cachedString = null;
        public override string ToString()
        {
            if (cachedString != null)
            {
                return cachedString;
            }

            if (ValueList == null)
            {
                return (cachedString = "{}");
            }

            var sb = new StringBuilder();
            sb.Append("{\n");
            Utils.textoffset += "  ";
            bool isKey = true;
            foreach (var item in ValueList)
            {
                if (isKey)
                {
                    sb.Append(Utils.textoffset);
                    sb.Append(Utils.ToSourceString(item));
                    sb.Append(" : ");
                    isKey = false;
                }
                else
                {
                    sb.Append(Utils.ToSourceString(item));
                    sb.Append("\n");
                    isKey = true;
                }
            }

            if (Utils.textoffset.Length >= 2)
            {
                Utils.textoffset = Utils.textoffset.Substring(0, Utils.textoffset.Length - 2);
            }

            sb.Append(Utils.textoffset);
            sb.Append("}");

            cachedString = sb.ToString();
            return cachedString;
        }

        public static void SplatDictionary(IDictionary target, Type t1, Type t2, object objectToSplat)
        {
            objectToSplat = Braid.Eval(objectToSplat);
            if (objectToSplat == null)
            {
                return;
            }

            IDictionary kdict = null;
            var callStack = Braid.CallStack;

            if (objectToSplat is IList lst)
            {
                object dictkey = null;
                foreach (var e in lst)
                {
                    if (e is DictionaryEntry de)
                    {
                        target[de.Key] = de.Value;
                        continue;
                    }

                    if (e is KeyValuePair<object, object> kvp)
                    {
                        target[kvp.Key] = kvp.Value;
                        continue;
                    }

                    if (e is IDictionary ndict)
                    {
                        foreach (DictionaryEntry nde in ndict)
                        {
                            target[nde.Key] = nde.Value;
                        }
                        continue;
                    }

                    if (dictkey == null)
                    {
                        if (t1 != typeof(object))
                        {
                            dictkey = Braid.ConvertTo(e, t1);
                        }
                        else
                        {
                            dictkey = e;
                        }
                    }
                    else
                    {
                        var value = t2 == typeof(object) ? e : Braid.ConvertTo(e, t2);
                        target[dictkey] = value;
                        dictkey = null;
                    }
                }

                if (dictkey != null)
                {
                    Braid.BraidRuntimeException($"When splatting an IList into a dictionary, an even of items is required; dictionary key '{dictkey}' has no associated value.");
                }

                return;
            }

            if (objectToSplat is Symbol sym)
            {
                kdict = Braid.ConvertToHelper<IDictionary>(callStack.GetValue(sym));
            }
            else if (objectToSplat is string vstr)
            {
                kdict = Braid.ConvertToHelper<IDictionary>(callStack.GetValue(Symbol.FromString(vstr)));
            }
            else
            {
                kdict = Braid.ConvertToHelper<IDictionary>(Braid.Eval(objectToSplat));
            }

            //  BUGBUGBUG - add code here to properly merge KeyValuePair and DictionaryEntries. 
            foreach (var dkey in kdict.Keys)
            {
                object dictkey;
                if (t1 != typeof(object))
                {
                    dictkey = Braid.ConvertTo(dkey, t1);
                }
                else
                {
                    dictkey = dkey;
                }

                var value = Braid.ConvertTo(kdict[dkey], t2);

                target[dictkey] = value;
            }
        }
    }

    ////////////////////////////////////////////////////////////////////
    /// <summary>
    /// Represents a literal user function or pattern function in the AST.
    /// i.e. (lambda [x y] (+ x y)) is compiled into a function literal.
    /// It exists because every time this gets executed,
    /// a new Lambda instance must be returned - same code
    /// but with a new environment. That's what this class does.
    /// </summary>
    public sealed class FunctionLiteral : BraidLiteral
    {
        Callable LambdaValue;
        string HelpInfo;

        public FunctionLiteral(Callable lambda) :this(lambda, null)
        {
        }

        public FunctionLiteral(Callable lambda, string helpInfo)
        {
            if (lambda == null)
            {
                Braid.BraidRuntimeException("creating ^FunctionLiteral instance, the argument 'lambda' cannot be null.");
            }

            LambdaValue = lambda;
            HelpInfo = helpInfo;
        }

        public override object Value
        {
            get
            {
                var func = LambdaValue.CloneWithEnv(Braid.CallStack.Clone() as PSStackFrame);

                if (HelpInfo != null)
                {
                    Braid.PutAssoc(func, "helptext", HelpInfo);
                }

                return func;
            }
        }

        public override string ToString()
        {
            return LambdaValue.ToString();
        }
    }

}
