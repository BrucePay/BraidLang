/////////////////////////////////////////////////////////////////////////////
//
// The Braid Programming Language
//
// Copyright (c) 2023 Bruce Payette (see LICENCE file) 
//
////////////////////////////////////////////////////////////////////////////

using System;
using System.Runtime.CompilerServices;
using System.Linq;
using System.Linq.Expressions;
//using System.Numerics;
using System.Collections;
using System.Text;
using System.Text.RegularExpressions;
using System.Collections.ObjectModel;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Management.Automation;
using System.Management.Automation.Internal; // needed for AutomationNull 
using System.Management.Automation.Runspaces;
using System.Threading.Tasks;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;

namespace BraidLang
{

    /////////////////////////////////////////////////////////////////////////////////////////
    ///
    /// Exception classes used by the Braid runtime.
    ///

    /// <summary>
    /// Base class for all braid exceptions.
    /// </summary>
    public class BraidBaseException : Exception
    {
        public BraidBaseException(string Message) : base(Message) { }
        public BraidBaseException(string Message, Exception InnerException) : base(Message, InnerException) { }

        /// <summary>
        /// Format an error message with source context information.
        /// </summary>
        /// <param name="message">The message to annote</param>
        /// <param name="context">The source context object.</param>
        /// <returns></returns>
        public static string Annotate(string message, ISourceContext context = null)
        {

            if (context == null)
            {
                context = Braid.CallStack.Caller;
            }

            if (context == null)
            {
                Braid.WriteConsoleColor(ConsoleColor.Red, $"In BraidRuntimeException.Annotate() : CallStack.Caller was null, message was '{message}'.");
                throw new NullReferenceException($"In BraidRuntimeException.Annotate() : CallStack.Caller was null, message was '{message}'");
            }

            return string.Format("-> at ({0}:{1}) {2}\n{3}", context.File, context.LineNo,
                message, Braid.GetStackTrace());
        }
    }

    /// <summary>
    /// Indicates when there is an unrecoverable compile-time exception.
    /// </summary>
    public class BraidCompilerException : Exception
    {
        public BraidCompilerException(string text, int offset, string file, int lineno, string Message)
                                            : base(BraidCompilerException.Annotate(text, offset, file, lineno, Message)) { }

        public BraidCompilerException(string text, int offset, string file, int lineno, string Message, Exception InnerException)
                                            : base(BraidCompilerException.Annotate(text, offset, file, lineno, Message), InnerException) { }

        /// <summary>
        /// Format an error message with context information; used by the parser
        /// </summary>
        /// <param name="message">The error message to display.</param>
        /// <returns></returns>
        public static string Annotate(string text, int offset, string file, int lineno, string message)
        {
            string msg = "";
            if (text != null)
            {
                msg += Braid.GetSourceLine(text, offset);
            }
            return msg + string.Format("-> at ({0}:{1}) {2}\n{3}", file, lineno, message, Braid.GetStackTrace());
        }
    }

    /// <summary>
    /// Thrown when the parsed text has insufficient close tokens i.e.  ')', '}', ']', '"'
    /// </summary>
    public class IncompleteParseException : BraidBaseException
    {
        public IncompleteParseException(string Message) : base(Message) { }
    }

    /// <summary>
    /// Generic Braid execution exception.
    /// </summary>
    public class BraidUserException : BraidBaseException {
        public BraidUserException(string Message)
        : base(Message) {
        }

        public BraidUserException(string Message, Exception InnerException)
            : base(Message, InnerException)
        {
        }
    }

    /// <summary>
    /// Exception thrown to exit Braid; thrown by the 'quit' built-in function.
    /// </summary>
    public class BraidExitException : System.Exception
    {
        public object ExitValue { get; set; }

        public BraidExitException(object val) : base(BraidBaseException.Annotate($"Exit exception thrown. {val}"))
        {
            ExitValue = val;
        }
    }

    /////////////////////////////////////////////////////////////////////////////////////////
    /// 
    /// Classes used for flow control operations in Braid e.g. 'return' 'break' 'continue' 'recur'

    /// <summary>
    /// Base class for the flow control types
    /// </summary>
    public abstract class BraidFlowControlOperation
    {
    }

    /// <summary>
    /// Returned by the 'braek' function.
    /// </summary>
    public sealed class BraidBreakOperation : BraidFlowControlOperation
    {
        internal bool HasValue;
        object _value;
        internal object BreakResult
        {
            set { _value = value; HasValue = true; }
            get => _value;
        }
    }

    /// <summary>
    /// Returned by the 'continue' function
    /// </summary>
    public sealed class BraidContinueOperation : BraidFlowControlOperation
    {
    }

    /// <summary>
    /// Returned by the Fail (!) pattern in pattern matching.
    /// </summary>
    public sealed class BraidFailOperation : BraidFlowControlOperation
    {
    }

    /// <summary>
    /// The type used to return a value from a braid function.
    /// </summary>
    public sealed class BraidReturnOperation : BraidFlowControlOperation
    {
        public object ReturnValue { get; set; }

        public BraidReturnOperation(object valToReturn)
        {
            ReturnValue = valToReturn;
        }
    }

    /// <summary>
    /// The type used to implement tail recursion
    /// </summary>
    public sealed class BraidRecurOperation : BraidFlowControlOperation
    {
        internal Vector RecurArgs;
        internal Callable Target;

        public BraidRecurOperation(Vector recurArgs)
        {
            RecurArgs = recurArgs;
            // BUGBUGBUG - experiment for recur with continuation passing style
            foreach (object val in recurArgs)
            {
                if (val is UserFunction lam)
                {
                    lam.Environment = Braid.CallStack.Fork();
                }
                else if (val is PatternFunction pm)
                {
                    pm.Environment = Braid.CallStack.Fork();
                }
            }
        }

        public BraidRecurOperation(Callable target, Vector recurArgs)
        {
            Target = target;
            RecurArgs = recurArgs;

            // BUGBUGBUG - experiment for recur with continuation passing style
            foreach (object val in recurArgs)
            {
                if (val is UserFunction lam)
                {
                    lam.Environment = Braid.CallStack.Fork();
                }
                else if (val is PatternFunction pm)
                {
                    pm.Environment = Braid.CallStack.Fork();
                }
            }
        }

        public new string ToString => $"(recur {Braid.Truncate(RecurArgs)})";
    }

    ///////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// Represents a named parameter i.e '-foo' or '-bar: 14'
    /// </summary>
    public sealed class NamedParameter
    {
        public string Name { get; set; }
        public object Expression { get; set; }
        public bool TakesArgument { get; set; }
        public bool DoubleDash { get; set; }

        public NamedParameter(string name, object expression, bool takesValue, bool doubleDash)
        {
            Name = name;
            Expression = expression;
            TakesArgument = takesValue;
            DoubleDash = doubleDash;
        }

        public object Value
        {
            get
            {
                if (TakesArgument)
                {
                    return Braid.Eval(Expression);
                }
                else
                {
                    return true;
                }
            }
        }

        public override string ToString()
        {
            var toString = DoubleDash ? $"--{Name}" : $"-{Name}";
            if (TakesArgument)
            {
                toString += ":";
            }
            return toString;
        }
    }

    ////////////////////////////////////////////////////////////////////
    ///
    /// Code implementing the conparison semantics
 
    /// <summary>
    /// A comparer class that uses the PowerShell comparison
    /// logic suitable for ordered comparisons.
    /// </summary>
    public sealed class PSComparer : IComparer<object>
    {
        int IComparer<object>.Compare(Object x, Object y)
        {
            return LanguagePrimitives.Compare(x, y, true);
        }
    }

    /// <summary>
    /// A comparer class that takes a Braid lambda to do the comparison.
    /// BUGBUGBUG are both PSComparer and BraidComparer needed?
    /// </summary>
    public sealed class BraidComparer : IComparer<object>
    {
        UserFunction Comparer;
        public BraidComparer(UserFunction comparer)
        {
            Comparer = comparer;
        }

        int IComparer<object>.Compare(Object obj1, Object obj2)
        {
            var result = Comparer.Invoke(new Vector { obj1, obj2 });
            if (result is int i)
            {
                return i;
            }

            return Braid.ConvertToHelper<int>(result);
        }
    }

    /// <summary>
    /// General equality object comparer class. Note - this uses value semantics when
    /// comparing enumerables so two vectors with the same elements will compare equal.
    /// </summary>
    public sealed class ObjectComparer : IEqualityComparer<object>
    {
        IInvokeableValue AccessorFunction;

        public ObjectComparer() { }

        public ObjectComparer(IInvokeableValue accessorFunction)
        {
            AccessorFunction = accessorFunction;
        }

        public new bool Equals(object obj1, object obj2)
        {
            if (AccessorFunction != null)
            {
                Vector args = new Vector { obj1 };
                obj1 = AccessorFunction.Invoke(args);

                args[0] = obj2;
                obj2 = AccessorFunction.Invoke(args);
            }

            return Braid.CompareItems(obj1, obj2);
        }

        public int GetHashCode(Object obj)
        {
            // If there is a comparison function, force it's use by returning a constaint hash value
            if (AccessorFunction != null)
            {
                return 0;
            }

            if (obj is string str)
            {
                return str.ToLowerInvariant().GetHashCode();
            }

            if (obj is IEnumerable)
            {
                // for enumerables, force value comparison semantics
                // by returning a constant hash forcing a call to CompareItems.
                return 0;
            }

            return obj.GetHashCode();
        }
    }

    ////////////////////////////////////////////////////////////////////
    /// <summary>
    /// General interface implemented by Braid's sequential collections.
    /// </summary>
    public interface ISeq : IEnumerable<object>, IEnumerable
    {
        object Car { get; }
        object Cdr { get; }
        object Cons(object obj);
        object Visit(Callable func, bool visitLambdas);
        int Count { get; }
    }

    ////////////////////////////////////////////////////////////////////
    /// <summary>
    /// Implemented by objects that have source-code context information.
    /// </summary>
    public interface ISourceContext
    {
        string File { get; set; }
        int LineNo { get; set; }
        string Function { get; set; }
        int Offset { get; set; }
        string Text { get; set; }
    }

    /////////////////////////////////////////////////////////////////////
    ///
    /// Braid primitive types e.g. s_Expr, Vector, and Slice.

    /// <summary>
    /// The core linked-list class in BraidLang.
    /// BUGBUGBUG - implement IComparable for lists.
    /// </summary>
    public sealed class s_Expr : IEquatable<s_Expr>, ISeq, ISourceContext
    {
        public object Car
        {
            get => _car;
            internal set
            {
                _car = value;
                SetQuotes();
            }
        }
        object _car;
        public object Cdr { get => _cdr; internal set { _cdr = value; } }
        object _cdr;

        public object Cons(object obj)
        {

            var sexpr = new s_Expr(obj, this);
            sexpr._count = 1 + Count;
            return sexpr;
        }

        // Records the line where this node was created
        public int LineNo { get; set; }

        // Records the function this was defined in
        public string Function { get; set; }

        // Records the index origin of this token in the source string
        public int Offset { get; set; }

        // The name of the file where this node was created
        public string File { get; set; }

        // The source text out of which this node was built.
        public string Text { get; set; }

        /// <summary>
        /// Gets the source line corresponding to the currret source offset.
        /// </summary>
        /// <returns></returns>
        public string GetSourceLine()
        {
            return Braid.GetSourceLine(Text, Offset);
        }

        // The environment where this s_Expr was created
        public PSStackFrame Environment;

        public TypeLiteral ReturnType;

        public IEnumerable<object> GetEnumerable()
        {
            s_Expr list = this;
            while (list != null)
            {
                if (Braid._stop)
                {
                    break;
                }

                yield return list._car;
                var next = list._cdr as s_Expr;
                if (next == null && list._cdr != null)
                {
                    yield return list._cdr;
                    list = null;
                }
                else
                {
                    list = next;
                }
            }
        }

        /// <summary>
        /// Shallow-clone the list
        /// </summary>
        /// <returns></returns>
        public s_Expr Clone()
        {
            s_Expr result = null, end = null;
            foreach (var e in this)
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

            result._tail = end;
            return result;
        }

        IEnumerator<object> IEnumerable<object>.GetEnumerator()
        {
            return this.GetEnumerable().GetEnumerator();
        }

        IEnumerator IEnumerable.GetEnumerator()
        {
            return (IEnumerator)this.GetEnumerable().GetEnumerator();
        }

        public s_Expr() : this(null, null) { }

        public s_Expr(object car) : this(car, null) { }

        public s_Expr(object car, object cdr)
        {
            this._car = car;

            SetQuotes();

            this._cdr = cdr;
            if (cdr is s_Expr s)
            {
                _tail = s.Tail();
            }

            var caller = Braid.CallStack.Caller;
            if (caller != null)
            {
                this.LineNo = caller.LineNo;
                this.File = caller.File;
                this.Function = caller.Function;
                this.Text = caller.Text;
                this.Offset = caller.Offset;
            }
            else
            {
                this.LineNo = -1;
                this.File = "*unknown*";
                this.Function = "*runtime*";
                this.Text = string.Empty;
                this.Offset = 0;
            }
        }

        private void SetQuotes()
        {
            if (_car is Symbol sym)
            {
                if (sym == Symbol.sym_lambda)
                {
                    _isLambda = true;
                }
                else if (sym == Symbol.sym_quote)
                {
                    _isQuote = true;
                }
                else if (sym == Symbol.sym_splat)
                {
                    _isSplat = true;
                }
                else if (sym == Symbol.sym_unquote)
                {
                    _isUnquote = true;
                }
                else if (sym == Symbol.sym_unquotesplat)
                {
                    _isUnquoteSplat = true;
                }
            }
        }

        /// <summary>
        /// Splice another element onto the end of this list, mutating the list.
        /// If the item to splice is another list or enumerable, then it will be
        /// appended it to the end of the list.
        /// </summary>
        /// <param name="objectToSplice">The object to splice</param>
        /// <returns>This list</returns>
        public s_Expr Splice(object objectToSplice)
        {
            if (objectToSplice != null)
            {
                if (objectToSplice is s_Expr sexpr)
                {
                    this.Tail()._cdr = sexpr;
                    _count += sexpr.Count;
                    _tail = sexpr.Tail();
                }
                else if (objectToSplice is string || objectToSplice is IDictionary)
                {
                    this.Add(objectToSplice);
                    this._count++;
                }
                else if (objectToSplice is IEnumerable ienum)
                {
                    foreach (var v in ienum)
                    {
                        this.Add(v);
                        this._count++;
                    }
                }
                else
                {
                    this.Add(objectToSplice);
                    this._count++;
                }
            }

            return this;
        }

        /// <summary>
        /// Create a list out of an enumerable
        /// </summary>
        /// <param name="input">The source enumerable</param>
        /// <returns>A list composed of elements from the source enumerable.</returns>
        public static s_Expr FromEnumerable(IEnumerable input)
        {
            if (input == null)
            {
                return null;
            }

            s_Expr start = null;
            s_Expr current = null;
            foreach (object elem in input)
            {
                if (start == null)
                {
                    start = current = new s_Expr(elem);
                }
                else
                {
                    current = current.Add(elem);
                    if (Braid._stop)
                    {
                        Braid._stop = false;
                        Braid.BraidRuntimeException("Braid is stopping because cancel was pressed.");
                    }
                }
            }

            return start;
        }

        // Get the last node in this list
        public s_Expr Tail()
        {
            if (this._cdr == null)
            {
                return this;
            }

            if (_tail == null)
            {
                _tail = this;
            }

            // Make sure we are really at the end of the list.
            while (_tail._cdr != null)
            {
                if (_tail._cdr is s_Expr s)
                {
                    _tail = s.Tail();
                }
                else
                {
                    _tail = this;
                    return this;
                }
            }

            return _tail;
        }

        s_Expr _tail = null;

        //
        // Add a new node to the end of this list then return the new node.
        //`
        public s_Expr Add(object obj)
        {
            var nl = new s_Expr(obj);
            this.Tail()._cdr = nl;
            _tail = nl;
            return nl;
        }

        //
        // Return the last node in the list.
        //
        public s_Expr LastNode()
        {
            return Tail();
        }

        bool _isLambda;
        public bool IsLambda { get => _isLambda; }

        bool _isQuote;
        public bool IsQuote { get => _isQuote; }

        bool _isUnquote;
        public bool IsUnquote { get => _isUnquote; }

        bool _isUnquoteSplat;
        public bool IsUnquoteSplat { get => _isUnquoteSplat; }

        bool _isSplat;
        public bool IsSplat {
            get
            {
                return _isSplat;
            }
        }

        // Count the number of elements in the list (this is "slow" since
        // it has to walk the entire list.)
        public int Count
        {
            get
            {
                if (_count == 0)
                {
                    s_Expr list = this;
                    while (list != null)
                    {
                        _count++;
                        list = list._cdr as s_Expr;
                    }
                }
                else
                {
                    // Account for splices
                    var tail = Tail();
                    if (tail._cdr != null)
                    {
                        while (tail._cdr != null)
                        {
                            _count++;
                            tail = tail._cdr as s_Expr;
                        }
                    }
                }

                return _count;
            }
        }
        int _count = 0;

        //
        // Visit every node in the tree and return the ones where the predicate evaluates to true
        //
        public object Visit(Callable visitor, bool visitLambdas)
        {
            s_Expr result = null;
            Vector paramvector = new Vector();
            paramvector.Add(null);

            if (_car is s_Expr car)
            {
                var listenum = s_Expr.FromEnumerable(Braid.GetEnumerableFrom(car.Visit(visitor, visitLambdas)));
                if (listenum != null)
                {
                    if (result == null)
                    {
                        result = listenum;
                    }
                    else
                    {
                        result.Splice(listenum);
                    }
                }
            }
            else
            {
                paramvector[0] = _car;
                if (Braid.IsTrue(visitor.Invoke(paramvector)))
                {
                    if (result == null)
                    {
                        result = new s_Expr(_car);
                    }
                    else
                    {
                        result.Splice(_car);
                    }
                }
            }

            if (_cdr != null)
            {
                paramvector[0] = _cdr;
                if (Cdr is s_Expr cdr)
                {
                    var listenum = s_Expr.FromEnumerable((IEnumerable)cdr.Visit(visitor, visitLambdas));
                    if (listenum != null)
                    {
                        if (result == null)
                        {
                            result = listenum;
                        }
                        else
                        {
                            result.Splice(listenum);
                        }
                    }
                }
                else if (Braid.IsTrue(visitor.Invoke(paramvector)))
                {
                    if (result == null)
                    {
                        if (_cdr is s_Expr sexpr)
                        {
                            result = sexpr;
                        }
                        else
                        {
                            result = new s_Expr(_cdr);
                        }
                    }
                    else
                    {
                        result.Splice(_cdr);
                    }
                }
            }

            return result;
        }

        //
        // The ToString() of a list is the printed representation of
        // the list including parens. In other words, serialization of
        // the list
        //
        public override string ToString()
        {
            return this.ToString(0);
        }

        public string ToString(int depth)
        {
            if (depth > 100)
            {
                Braid.BraidRuntimeException("Processing .toString on a list: recursion depth is too deep (> 100); quitting", null, this);
            }

            StringBuilder sb = new StringBuilder();
            ISeq lst = this;
            bool first = true;
            sb.Append("(");
            while (lst != null)
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

                object car = lst.Car;

                if (car is s_Expr nested)
                {
                    sb.Append(nested.ToString(++depth));
                }
                else
                {
                    sb.Append(Utils.ToSourceString(car));
                }

                if (lst.Cdr == null)
                {
                    break;
                }
                else if (lst.Cdr is s_Expr lstcdr)
                {
                    lst = lstcdr;
                }
                else
                {
                    sb.Append(" . ");
                    sb.Append(Utils.ToSourceString(lst.Cdr));
                    break;
                }
            }

            sb.Append(')');
            return sb.ToString();
        }

        public override bool Equals(object obj)
        {
            if (obj == null) return false;
            if (obj is s_Expr sobj)
            {
                return Equals(sobj);
            }
            else {
                return false;
            }
        }

        public bool Equals(s_Expr list2)
        {
            if (list2 == null)
            {
                return false;
            }

            s_Expr list1 = this;
            while (true)
            {
                if (list1 == null && list2 == null)
                {
                    return true;
                }

                if (list1 == null || list2 == null)
                {
                    return false;
                }

                if (!Braid.CompareItems(list1._car, list2._car))
                {
                    return false;
                }

                if (list1._cdr is s_Expr sexpr1 && list2._cdr is s_Expr sexpr2)
                {
                    list1 = sexpr1;
                    list2 = sexpr2;
                }
                else
                {
                    // Handle dotted pairs
                    return Braid.CompareItems(list1._cdr, list2._cdr);
                }
            }
        }

        public override int GetHashCode()
        {
            int hash = 0;

            if (_car != null)
            {
                hash = _car.GetHashCode();
            }

            if (_cdr != null)
            {
                hash ^= _cdr.GetHashCode();
            }

            if (hash == 0)
            {
                hash = base.GetHashCode();
            }

            return hash;
        }
    }

    //
    // The Braid Vector type implementation e.g. [1 2 3]
    //
    public class Vector : List<object>, IComparable, ISeq
    {
        public Vector() : base()
        {
        }

        public Vector(int size) : base(size)
        {
        }

        public Vector(int size, object value) : base(size)
        {
            for (int i = 0; i < size; i++) {
                this.Add(value);
            }
        }

        public Vector(IEnumerable<object> ienum)
        {
            if (ienum != null)
            {
                this.AddRange(ienum);
            }
        }

        public Vector(IEnumerable ienum)
        {
            if (ienum != null)
            {
                foreach (var item in ienum)
                {
                    this.Add(item);
                }
            }
        }

        // Return the tail of the Vector as a slice.
        public object Cdr
        {
            get
            {
                if (this.Count < 2)
                {
                    return null;
                }

                return new Slice(this, 1, this.Count - 1);
            }
        }


        // Returns the first element in the vector
        public object Car
        {
            get
            {
                if (this.Count > 0)
                {
                    return this[0];
                }
                else
                {
                    return null;
                }
            }
        }

        // Insert a item into this list then return the modified list
        public new Vector Insert(int index, object obj)
        {
            base.Insert(index, obj);
            return this;
        }

        public object Cons(object obj)
        {
            this.Insert(0, obj);
            return this;
        }

        public object Pop()
        {
            if (Count > 0)
            {
                object val = this[0];
                this.RemoveAt(0);
                return val;
            }
            else
            {
                return null;
            }
        }

        public Vector Push(object itemToPush)
        {
            this.Insert(0, itemToPush);
            return this;
        }

        public object Enqueue(object itemToEnque)
        {
            base.Insert(base.Count, itemToEnque);
            return this;
        }

        public object Dequeue()
        {
            if (Count > 0)
            {
                int last = Count - 1;
                object val = this[last];
                this.RemoveAt(last);
                return val;
            }
            else
            {
                return null;
            }
        }

        public bool Equals(Vector otherVect)
        {
            return System.Linq.Enumerable.SequenceEqual(this, otherVect);
        }

        public bool Equals(s_Expr list)
        {
            return System.Linq.Enumerable.SequenceEqual(this, list.GetEnumerable());
        }

        public Vector GetRangeVect(int index)
        {
            var count = this.Count - index;
            Vector newvect = new Vector(count);
            while (count-- > 0)
            {
                newvect.Add(this[index++]);
            }

            return newvect;
        }

        public Vector GetRangeVect(int index, int count)
        {
            Vector newvect = new Vector(count);
            while (count-- > 0)
            {
                newvect.Add(this[index++]);
            }

            return newvect;
        }

        public override string ToString()
        {
            if (this.Count == 0)
            {
                return "[]";
            }

            var sb = new StringBuilder("[\n");
            Utils.textoffset += "  ";
            bool first = true;
            foreach (var obj in this)
            {
                if (first)
                {
                    first = false;
                    sb.Append(Utils.textoffset);
                }
                else
                {
                    sb.Append(",\n" + Utils.textoffset);
                }

                sb.Append(Utils.ToSourceString(obj));
            }

            if (Utils.textoffset.Length >= 2)
            {
                Utils.textoffset = Utils.textoffset.Substring(0, Utils.textoffset.Length - 2);
            }

            sb.Append("\n" + Utils.textoffset + "]");
            return sb.ToString();
        }

        public int CompareTo(object obj)
        {
             if (! (obj is IList icol))
            {
                return -1;
            }

            if (icol.Count < this.Count)
            {
                return -1;
            }

            if (icol.Count > this.Count)
            {
                return 1;
            }

            if (this.Count == 0)
            {
                return 0;
            }

            int result;
            for (int index = 0; index < icol.Count; index++)
            {
                if ((result = LanguagePrimitives.Compare(icol[index], this[index], true)) != 0)
                {
                    return result;
                }
            }
            return 0;
        }

        public void ForEach(Callable callable)
        {
            Vector args = new Vector();
            args.Add(null);
            foreach (object val in this)
            {
                args[0] = val;
                callable.Invoke(args);
            }
        }

        public Vector Map(Callable callable)
        {
            Vector args = new Vector();
            args.Add(null);
            var result = new Vector();
            foreach (object val in this)
            {
                args[0] = val;
                result.Add(callable.Invoke(args));
            }

            return result;
        }

        public object Visit(Callable func, bool visitLambdas)
        {
            Vector result = new Vector();
            Vector parameters = new Vector();
            parameters.Add(null);
            foreach (var e in this)
            {
                parameters[0] = e;
                result.Add(func.Invoke(parameters));
            }
            return result;
        }
    }

    /// <summary>
    /// Class representing a slice of a vector or string. A slice is a "window" into
    /// the underlying Vector. Setting a slice member actually sets the
    /// corresponding member in the Vector. Doing (cdr [1 2 3])
    /// returns a slice (2 3). This is done for performance reasons i.e.
    /// it's much cheaper to create a slice object than it is to copy the
    /// tail of the array.
    /// </summary>
    public sealed class Slice : ISeq, IList, ICollection, IEnumerable
    {
        IList Data;
        int Start;
        int Length;
        bool wasString;

        public Slice(IList data, int start) : this(data, start, data.Count - start)
        {
        }

        public Slice(IList data, int start, int length)
        {
            if (data is Slice s)
            {
                Data = s.Data;
                Start = s.Start + start;
            }
            else
            {
                Data = data;
                Start = start;
            }

            Length = length;

            if (Start + length > Data.Count)
            {
                Braid.BraidRuntimeException($"Start ({start}) + Length ({length}) exceeds the length of the buffer to wrap ({Data.Count - Start})");
            }
        }

        public Slice(IList data)
        {
            if (data is Slice s)
                Data = s.Data;
            else
                Data = data;

            Start = 0;
            Length = data.Count;
        }

        public Slice(IEnumerable data, int start, int length)
        {
            Start = start;
            Length = length;

            if (data is string dstr)
            {
                wasString = true;
                Data = dstr.ToCharArray();
            }
            else
            {
                Data = new Vector(data);
            }

            if (start + length > Data.Count)
            {
                Braid.BraidRuntimeException($"Start ({start}) + Length ({length}) exceeds the length of the underlying buffer ({Data.Count})");
            }
        }

        public Slice(IEnumerable data, int start)
        {
            if (data is string dstr)
            {
                wasString = true;
                Data = dstr.Substring(start).ToCharArray();
                Length = Data.Count;
            }

            Data = new Vector();
            Start = 0;
            foreach (var e in data)
            {
                if (start-- > 0)
                {
                    continue;
                }

                Data.Add(e);
            }
            Length = Data.Count;
        }

        public Slice(IEnumerable data)
        {
            if (data is string dstr)
            {
                wasString = true;
                Data = dstr.ToCharArray();
            }
            else
            {
                Data = new Vector(data);
            }

            Start = 0;
            Length = Data.Count;
        }

        public int PhysicalIndex(int index) => Start + index;

        public object Car
        {
            get
            {
                if (Length == 0)
                {
                    Braid.BraidRuntimeException($"The 'car' method cannot be called on an empty slice.");
                }

                return Data[Start];
            }
        }

        public object Cdr
        {
            get
            {
                if (Length == 1)
                    return null;

                var ns = new Slice(Data, Start + 1, Length - 1);
                ns.wasString = wasString;
                return ns;
            }
        }

        public object Cons(object value)
        {
            return new s_Expr(value, this);
        }

        public object Visit(Callable func, bool nested)
        {
            // BUGBUGBUG - complete this
            return null;
        }

        // object System.Collections.Generic.IList<object>.Item[int index]
        public object this[int index]
        {
            get
            {
                if (index >= Length)
                {
                    Braid.BraidRuntimeException($"Error indexing into a slice: the specified index ({index}) is greater than " +
                                             $"or equal to the length of the slice ({Length}).");
                }

                return Data[index + Start];
            }

            set
            {
                Braid.BraidRuntimeException("Slices are immutable objects and cannot be assigned to.");
            }
        }

        public bool Equals(IList otherVect)
        {
            if (Data.Count != otherVect.Count)
            {
                return false;
            }

            for (int index = 0; index < Data.Count; index++)
            {
                if (!Braid.CompareItems(Data[index], otherVect[index]))
                {
                    return false;
                }
            }

            return true;
        }

        public bool Equals(IEnumerable list)
        {
            IEnumerator e1 = Data.GetEnumerator();
            IEnumerator e2 = list.GetEnumerator();
            while (true)
            {
                bool mn1 = e1.MoveNext();
                bool mn2 = e2.MoveNext();

                if (mn1 != mn2)
                {
                    return false;
                }

                if (mn1 == false)
                {
                    return true;
                }

                if (!Braid.CompareItems(e1.Current, e2.Current))
                {
                    return false;
                }
            }
        }

        public int Add(object elementToAdd)
        {
            Braid.BraidRuntimeException("The 'Add' operation is not supported on slices.");
            return 0;
        }

        public bool Contains(object elementToFind)
        {
            Braid.BraidRuntimeException("The 'Contains' operation is not supported on slices.");
            return Data.Contains(elementToFind);
        }

        public void Clear()
        {
            Braid.BraidRuntimeException("The 'Clear' operation is not supported on slices.");
        }

        public int IndexOf(object objToFind)
        {
            Braid.BraidRuntimeException("The 'IndexOf' operation is not supported on slices.");
            return Data.IndexOf(objToFind);
        }

        public void Insert(int index, object value)
        {
            Braid.BraidRuntimeException("The 'Insert' operation is not supported on slices.");
        }
        public void Remove(object value)
        {
            Braid.BraidRuntimeException("The 'Remove' operation is not supported on slices.");
        }

        public void RemoveAt(int index)
        {
            Braid.BraidRuntimeException("The 'RemoveAt' operation is not supported on slices.");
        }

        public bool IsReadOnly
        {
            get { return true; }
        }

        public bool IsFixedSize
        {
            get { return true; }
        }

        public void CopyTo(Array target, int offset)
        {
            int start = Start;
            int end = start + Length;
            int tend = target.Length;

            while (start < end && offset < tend)
            {
                target.SetValue(Data[start], offset++);
                start++;
            }
        }

        public int Count => Length;

        static object _syncRoot = new object();
        public object SyncRoot => _syncRoot;

        public bool IsSynchronized => false;

        IEnumerator IEnumerable.GetEnumerator() => (IEnumerator)GetEnumerator();

        public IEnumerator<object> GetEnumerator()
        {
            var end = Start + Length;
            for (int i = Start; i < end; i++)
            {
                yield return Data[i];
            }
        }

        public override string ToString()
        {
            StringBuilder sb = new StringBuilder();

            var end = Start + Length;

            if (wasString)
            {
                for (int i = Start; i < end; i++)
                {
                    sb.Append(Data[i]);
                }
            }
            else
            {
                sb.Append("[");
                for (int i = Start; i < end; i++)
                {
                    if (sb.Length > 1)
                    {
                        sb.Append(" ");
                    }

                    sb.Append(Data[i] == null ? "null" : Data[i].ToString());
                }

                sb.Append("]");
            }

            return sb.ToString();
        }
    }

    ///////////////////////////////////////////////////////////////////////////
    ///
    /// Braid "invoceable" types

    /// <summary>
    /// Function attribute that specifies how arguments are processed before
    /// dispatching the function.
    /// </summary>
    public enum FunctionType
    {
        Function = 0,       // Args are evaluated
        SpecialForm = 1,    // Args are not evaluated
        Macro = 2,          // Args are not evaluated
    }

    /// <summary>
    /// Interface implemented by syntactic elements that can be invoked like
    /// functions, regular expressions, etc.
    /// </summary>
    public interface IInvokeableValue
    {
        Func<Vector, object> FuncToCall { get; }

        object Invoke(Vector args);
    }

    /// <summary>
    /// The base class for "callable" types in BraidLang.
    /// </summary>
    public class Callable : IInvokeableValue, ISourceContext
    {
        public PSStackFrame Environment { get; set; }

        public int LineNo { get; set; }
        public string File { get; set; }
        public string Function { get; set; }
        public int Offset { get; set; }
        public string Text { get; set; } = string.Empty;

        public string Name { get; set; }
        public Symbol NameSymbol { get; set; }
        public FunctionType FType = FunctionType.Function;

        public Callable(string name)
        {
            NameSymbol = Symbol.FromString(name);
            Name = name;
        }

        public Callable(string name, Func<Vector, object> func)
        {
            Name = name;
            NameSymbol = Symbol.FromString(name);
            FuncToCall = func;
        }

        public virtual Callable CloneWithEnv(PSStackFrame environment)
        {
            Braid.BraidRuntimeException($"{this.GetType()} does not implement the CloneWithEnv() method.");
            return null;
        }

        public override string ToString() => Name;

        public virtual object Invoke(Vector args) => Invoke(args, null);

        public virtual object Invoke(Vector args, Dictionary<string, NamedParameter> namedParameters)
        {
            if (args == null)
            {
                args = new Vector();
            }

            var callstack = Braid.CallStack;
            var oldnp = callstack.NamedParameters;

            try
            {
                object retval;
                callstack.NamedParameters = namedParameters;

                if (Braid.Debugger != 0)
                {
                    if ((Braid.Debugger & DebugFlags.Trace) != 0 && (Braid.Debugger & DebugFlags.TraceException) == 0)
                    {
                        var argstr = string.Join(" ", args.ToArray());
                        Console.WriteLine("SPFN:  {0} ({1} {2}) -->",
                            Braid.spaces(Braid._evalDepth + 2), Name, argstr);
                    }

                    retval = FuncToCall.Invoke(args);

                    if ((Braid.Debugger & DebugFlags.Trace) != 0 && (Braid.Debugger & DebugFlags.TraceException) == 0)
                    {
                        var argstr = string.Join(" ", args.ToArray());
                        Console.WriteLine("SPFN:  {0} ({1} {2}) <-- {3}",
                            Braid.spaces(Braid._evalDepth + 2), Name, argstr, Braid.Truncate(retval));
                    }
                }
                else
                {
                    retval = FuncToCall.Invoke(args);
                }

                return retval;
            }
            finally
            {
                callstack.NamedParameters = oldnp;
            }
        }

        public Func<Vector, object> FuncToCall { get; internal set; }
    }

    /// <summary>
    /// Class representing a callable function.
    /// </summary>
    public sealed class Function : Callable, IEquatable<Function>
    {
        public Function(string name, Func<Vector, object> funcToCall) : base(name)
        {
            var caller = Braid.CallStack.Caller;
            if (caller != null && caller.File != "*runtime")
            {
                this.File = caller.File;
            }
            else
            {
                this.File = Braid._current_file;
            }

            FuncToCall = funcToCall;
        }

        public bool Equals(Function sf) => sf.FuncToCall == FuncToCall;

        public override bool Equals(object obj) => obj is Function sf && sf.FuncToCall == FuncToCall;

        public override int GetHashCode() => FuncToCall.GetHashCode();

        public override string ToString() => Name;

        public override object Invoke(Vector args, Dictionary<string, NamedParameter> namedParameters)
        {
            //BUGBUGBUGBUG - this should do something with the named parameters.
            if (args == null)
            {
                args = new Vector();
            }

            PSStackFrame callstack = Braid.CallStack;
            Dictionary<string, NamedParameter> oldnp = callstack.NamedParameters;
            callstack.NamedParameters = namedParameters;

            try
            {
                object result = FuncToCall.Invoke(args);

                if (Braid.Debugger != 0)
                {
                    if ((Braid.Debugger & DebugFlags.Trace) != 0 && (Braid.Debugger & DebugFlags.TraceException) == 0)
                    {
                        var argstr = string.Join(" ", args.ToArray());
                        Console.WriteLine("FUNC:  {0} ({1} {2}) --> {3}",
                            Braid.spaces(Braid._evalDepth + 2), Name, argstr, Braid.Truncate(result));
                    }
                }

                return result;
            }
            finally
            {
                callstack.NamedParameters = oldnp;
            }
        }
    }

    /// <summary>
    /// Class representing a Braid macro form.
    /// </summary>
    public sealed class Macro : Callable, IEquatable<Macro>
    {
        public Macro(string name, Func<Vector, object> funcToCall) : base(name)
        {
            FuncToCall = funcToCall;
            FType = FunctionType.Macro;
        }

        public bool Equals(Macro macro) => macro.FuncToCall == FuncToCall;

        public override bool Equals(object obj) => obj is Macro macro && macro.FuncToCall == FuncToCall;

        public override int GetHashCode() => FuncToCall.GetHashCode();
    }

    /// <summary>
    /// Represents a bound user function.
    /// </summary>
    public sealed class UserFunction : Callable
    {
        public FunctionType FunctionType { get; set; }
        public Vector Arguments { get; set; }
        public s_Expr Body { get; set; }
        public TypeLiteral ReturnType { get; set; }
        public Dictionary<string, KeywordLiteral> Keywords { get; set; }

        public UserFunction(
            FunctionType functionType,
            string name,
            Vector funArgs,
            Dictionary<string, KeywordLiteral> kwargs,
            s_Expr body,
            TypeLiteral returnType) : base(name)
        {
            if (body != null)
            {
                LineNo = body.LineNo;
                File = body.File;
                Body = body;
            }

            Environment = Braid.CallStack;
            Arguments = funArgs;
            Keywords = kwargs;
            ReturnType = returnType;
            FunctionType = functionType;
            FuncToCall = (Vector args) => this.Invoke(args);
        }

        // Minimal constructor so the fields can be incrementally filled in later.
        public UserFunction(string name) : base(name)
        {
            this.FuncToCall = (Vector args) => this.Invoke(args);
        }

        public override Callable CloneWithEnv(PSStackFrame newEnv)
        {
            var newUserFunction = new UserFunction(this.FunctionType, this.Name, this.Arguments, this.Keywords, this.Body, this.ReturnType);
            newUserFunction.LineNo = this.LineNo;
            newUserFunction.File = this.File;
            newUserFunction.Text = this.Text;
            newUserFunction.Offset = this.Offset;
            newUserFunction.Environment = newEnv;
            return newUserFunction;
        }

        public override object Invoke(Vector evaluatedArgs, Dictionary<string, NamedParameter> namedParameters)
        {
            // Bind the stack at runtime.
            PSStackFrame env = Environment;

            if (Braid._callStack == null)
            {
                if (env == null)
                {
                    Braid.BraidRuntimeException($"Undefined environment for lambda {Name}.");
                }

                Braid._callStackStack = new Stack<PSStackFrame>();
                Braid._callStack = Environment;
                Braid._callStackStack.Push(Braid._callStack);
            }
            else
            {
                // Bind the stack at runtime.
                if (env == null)
                {
                    Environment = env = Braid._callStack;
                }
            }

            env = Braid.PushCallStack(new PSStackFrame(File, Name, this, env));

            try
            {
                while (true)
                {
                    object funcResult = Braid.InvokeUserFunction(
                            Name,
                            evaluatedArgs,
                            namedParameters,
                            Arguments,
                            Keywords,
                            Body,
                            env,
                            ReturnType);

                    if (funcResult is BraidFlowControlOperation)
                    {
                        if (funcResult is BraidRecurOperation recur)
                        {
                            if (Braid._stop)
                            {
                                return null;
                            }

                            if (recur.Target == null || recur.Target == this)
                            {
                                if (Arguments.Count != recur.RecurArgs.Count)
                                {
                                    Braid.BraidRuntimeException($"Function '{Name}': incorrect number of arguments were passed to the 'recur' function."
                                        + " Calls to 'recur' must pass the same number of arguments as defined in the containing function. "
                                        + $"{recur.RecurArgs.Count} arguments were passed but {Arguments.Count} were expected.");
                                }

                                evaluatedArgs = recur.RecurArgs;
                            }
                            else
                            {
                                return recur;
                            }
                        }
                        else if (funcResult is BraidLang.BraidReturnOperation retop)
                        {
                            return retop.ReturnValue;
                        }
                        else
                        {
                            // BUGBUGBUG - these would be break and continue. Should this be an error?
                            return funcResult;
                        }
                    }
                    else
                    {
                        return funcResult;
                    }
                }
            }
            finally
            {
                Braid.PopCallStack();
            }
        }

        public override object Invoke(Vector evaluatedArgs)
        {
            return Invoke(evaluatedArgs, null);
        }

        /// <summary>
        /// Returns a string representation of the function's signature.
        /// </summary>
        /// <returns></returns>
        public string Signature
        {
            get
            {
                StringBuilder sb = new StringBuilder();
                if (ReturnType != null)
                {
                    sb.Append($"({Name} {ReturnType} [");
                }
                else
                {
                    sb.Append($"({Name} [");
                }

                if (Arguments != null)
                {
                    sb.Append(string.Join(" ", Arguments.Select(n => Utils.ToSourceString(n))));
                }

                sb.Append("])");
                return sb.ToString();
            }
        }

        public override string ToString()
        {
            StringBuilder sb = new StringBuilder();

            string prefix = string.Equals(Name, "lambda", StringComparison.OrdinalIgnoreCase) ? "(" : "(defn ";

            if (ReturnType != null)
            {
                sb.Append($"{prefix}{Name} {ReturnType} [");
            }
            else
            {
                sb.Append($"{prefix}{Name} [");
            }

            if (Arguments != null)
            {
                sb.Append(string.Join(" ", Arguments.Select(n => n.ToString())));
            }

            sb.Append("] ");
            if (Body != null)
            {
                sb.Append(string.Join(" ", Body.Where(n => n != null).Select(n => n.ToString())));
            }

            sb.Append(')');
            return sb.ToString();
        }
    }

    /////////////////////////////////////////////////////////////////////
    ///
    /// Enumerator/enumerable types used by Braid.

    /// <summary>
    ///  Class representing an iterable function. Is returned by
    /// 'the iterator'/'unfold' function.
    /// </summary>
    public sealed class BraidEnumerable : IEnumerable<object>, IEnumerable
    {
        object _function;
        object _initial;
        bool _hadInitial;
        object _final;
        bool _hadFinal;
        PSStackFrame callStack = Braid.CallStack;

        public BraidEnumerable(object function, object initialVal)
        {
            if (function == null)
            {
                Braid.BraidRuntimeException("When constructing an iterator, the function argument must be a non-null lambda.");
            }

            _function = Braid.GetFunc(callStack, function);
            _initial = initialVal;
            _hadInitial = true;
        }

        public BraidEnumerable(object function, object initialVal, object finalVal)
        {
            if (function == null)
            {
                Braid.BraidRuntimeException("When constructing an iterator, the function argument must be a non-null lambda.");
            }

            _function = Braid.GetFunc(callStack, function);
            _initial = initialVal;
            _hadInitial = true;
            _final = finalVal;
            _hadFinal = true;
        }

        public BraidEnumerable(object function)
        {
            if (function == null)
            {
                Braid.BraidRuntimeException("When constructing an iterator, the function argument must be a non-null lambda.");
            }

            _function = Braid.GetFunc(callStack, function);
        }

        IEnumerator IEnumerable.GetEnumerator() => (IEnumerator)GetEnumerator();

        public IEnumerator<object> GetEnumerator()
        {
            if (_hadFinal)
                return new BraidIteratorEnumerator(_function, _initial, _final);
            if (_hadInitial)
                return new BraidIteratorEnumerator(_function, _initial);
            return new BraidIteratorEnumerator(_function);
        }
    }

    /// <summary>
    /// Class representing an iterable function. Is returned by the
    /// 'iterator'/'unfold' built-in functions.
    /// </summary>
    public sealed class BraidIteratorEnumerator : IEnumerator<object>, IEnumerator, IDisposable
    {
        object _current;
        object _initial;
        object _final;
        bool first = true;
        IInvokeableValue fnExpr;
        Vector argexpr;
        bool hasUpperBound;
        bool hasInitial;

        public BraidIteratorEnumerator(object function, object initialValue)
        {
            _current = _initial = initialValue;
            fnExpr = Braid.GetFunc(Braid.CallStack, function) as IInvokeableValue;
            hasInitial = true;
            argexpr = new Vector { null };
            if (fnExpr == null)
            {
                Braid.BraidRuntimeException($"iterator requires a function, not '{function}'");
            }
        }

        public BraidIteratorEnumerator(object function, object initialValue, object finalValue)
        {
            _current = _initial = initialValue;
            _final = finalValue;
            hasInitial = true;
            argexpr = new Vector { null };
            hasUpperBound = true;
            fnExpr = Braid.GetFunc(Braid.CallStack, function) as IInvokeableValue;
            if (fnExpr == null)
            {
                Braid.BraidRuntimeException($"iterator requires a function, not '{function}'");
            }
        }

        public BraidIteratorEnumerator(object function)
        {
            fnExpr = Braid.GetFunc(Braid.CallStack, function) as IInvokeableValue;
            if (fnExpr == null)
            {
                Braid.BraidRuntimeException($"iterator requires a function, not '{function}'");
            }
            argexpr = new Vector();
        }

        public object Current { get => _current; }

        public bool MoveNext()
        {
            if (Braid._stop)
            {
                return false;
            }

            if (!hasInitial)
            {
                _current = fnExpr.Invoke(argexpr);
                if (_current == null)
                {
                    return false;
                }

                return true;
            }

            if (first)
            {
                first = false;
                return true;
            }

            argexpr[0] = _current;
            var nextVal = fnExpr.Invoke(argexpr);
            if (hasUpperBound && LanguagePrimitives.Compare(_current, _final) >= 0)
            {
                return false;
            }
            _current = nextVal;
            return true;
        }

        public void Reset()
        {
            _current = _initial;
        }

        void IDisposable.Dispose()
        {
            // required but unused
        }
    }

    /// <summary>
    /// BUGBUGBUG
    /// </summary>
    public sealed class BraidMapIterator : IEnumerable
    {
        object _function;
        IEnumerable _collection;

        public BraidMapIterator(object function, IEnumerable collection)
        {
            if (function == null)
            {
                Braid.BraidRuntimeException("When constructing an iterator, the function argument must not be null.");
            }

            _function = function;
            _collection = collection;
        }

        IEnumerator IEnumerable.GetEnumerator()
        {
            return (IEnumerator)GetEnumerator();
        }

        public BraidMapEnumerator GetEnumerator()
        {
            return new BraidMapEnumerator(_function, _collection);
        }
    }

    /// <summary>
    /// Enumerator used by lazy-map
    /// </summary>
    public sealed class BraidMapEnumerator : IEnumerator
    {
        IEnumerator _collection;
        object _function;
        object _current;
        Vector _argvec;
        bool _hadBreak;

        public BraidMapEnumerator(object function, IEnumerable collection)
        {
            _collection = collection.GetEnumerator();
            _function = function;
            _argvec = new Vector { null };
        }

        public object Current { get => _current; }

        public bool MoveNext()
        {
            if (_hadBreak)
            {
                return false;
            }

            if (Braid._stop)
            {
                return false;
            }

            if (_collection.MoveNext())
            {
                PSStackFrame environment = null;
                if (_function is s_Expr sexpr)
                {
                    environment = sexpr.Environment;
                }

                try
                {
                    if (environment != null)
                    {
                        Braid.PushCallStack(environment);
                    }

                    _argvec[0] = _collection.Current;
                    object result = null;
                    if (_function is IInvokeableValue invokeable)
                    {
                        result = invokeable.Invoke(_argvec);
                    }
                    else if (_function is Func<Vector, object> func)
                    {
                        result = func.Invoke(_argvec);
                    }
                    else
                    {
                        // BUGBUGBUG - this should go away and everything should be a Callable...
                        result = Braid.Eval(new s_Expr(_function, new s_Expr(_collection.Current)));
                    }

                    if (result is BraidBreakOperation breakOp)
                    {
                        if (breakOp.HasValue)
                        {
                            _current = breakOp.BreakResult;
                            _hadBreak = true;
                        }
                        else
                        {
                            return false;
                        }
                    }
                    else
                    {
                        _current = result;
                    }

                    return true;
                }
                finally
                {
                    if (environment != null)
                    {
                        Braid.PopCallStack();
                    }
                }
            }
            else
            {
                return false;
            }
        }

        public void Reset()
        {
            _collection.Reset();
        }
    }

    /// <summary>
    /// Enumerator used by lazy-filter
    /// </summary>
    public sealed class BraidFilterIterator : IEnumerable
    {

        IInvokeableValue _function;
        IEnumerable _collection;
        bool _not;

        public BraidFilterIterator(IInvokeableValue function, bool not, IEnumerable collection)
        {
            if (function == null)
            {
                Braid.BraidRuntimeException("When constructing an filter iterator, the function argument must be non-null.");
            }

            _not = not;
            _function = function;
            _collection = collection;
        }

        IEnumerator IEnumerable.GetEnumerator()
        {
            return (IEnumerator)GetEnumerator();
        }

        public BraidFilterEnumerator GetEnumerator()
        {
            return new BraidFilterEnumerator(_function, _not, _collection);
        }
    }

    /// <summary>
    /// Used by the 'lazy-filter' built-in function
    /// </summary>
    public sealed class BraidFilterEnumerator : IEnumerator
    {
        IEnumerator _collection;
        IInvokeableValue _function;
        object _current;
        bool _not;
        bool _gotBreak;
        Vector argvec = new Vector { null };

        public BraidFilterEnumerator(IInvokeableValue function, bool not, IEnumerable collection)
        {
            _collection = collection.GetEnumerator();
            _function = function;
            _not = not;
        }

        public object Current { get => _current; }

        public bool MoveNext()
        {
            if (_gotBreak)
            {
                return false;
            }

            while (_collection.MoveNext())
            {
                // Loop until a match value is found
                _current = _collection.Current;
                argvec[0] = _current;
                object funcResult = _function.Invoke(argvec);
                if (funcResult is BraidBreakOperation breakOp)
                {
                    if (breakOp.HasValue)
                    {
                        _current = breakOp.BreakResult;
                    }
                    _gotBreak = true;
                    return true;
                }
                else if (funcResult is BraidContinueOperation)
                {
                    continue;
                }

                if (Braid.IsTrue(funcResult) != _not)
                {
                    return true;
                }
            }

            return false;
        }

        public void Reset()
        {
            _collection.Reset();
        }
    }

    /// <summary>
    /// Implementation of the object returned by the 'range' function.
    /// </summary>
    public sealed class RangeList : IList<object>, IList, ISeq, IEquatable<RangeList>
    {
        int Upper;
        int Lower;
        int Increment;

        public bool Equals(RangeList rl)
        {
            return rl.Upper == Upper && rl.Lower == Lower && rl.Increment == Increment;
        }

        public override bool Equals(object obj)
        {
            return (obj is RangeList rl && rl.Equals(this));
        }

        public override int GetHashCode()
        {
            return base.GetHashCode();
        }

        public int Count
        {
            get
            {
                return (Upper - Lower) / Increment + 1;
            }
        }

        public bool IsReadOnly { get { return true; } }

        bool IList.IsFixedSize { get { return true; } }

        public void Add(object obj)
        {
            Braid.BraidRuntimeException("cannot add object '{object}' to a RangeList (range n) object.");
        }

        public object Car { get { return Lower; } }

        public object Cdr
        {
            get
            {
                if (Lower == Upper)
                {
                    return null;
                }

                return new RangeList(Lower + Increment, Upper, Increment);
            }
        }

        public object Cons(object obj)
        {
            Braid.BraidRuntimeException("cannot cons object '{object}' onto a RangeList (cons m (range n)) object.");
            return null;
        }

        int IList.Add(object obj)
        {
            Braid.BraidRuntimeException("cannot add object '{object}' to a RangeList (range n) object.");
            return -1;
        }

        public void Clear()
        {
            Braid.BraidRuntimeException("Clear() is not supported on RangeList objects.");
        }

        public bool Contains(object obj)
        {
            if (obj is int valToCheck)
            {
                if (valToCheck >= Lower && valToCheck <= Upper && valToCheck % Increment == 0)
                {
                    return true;
                }
            }
            else if (obj is Char charToCheck)
            {
                valToCheck = (int)charToCheck;
                if (valToCheck >= Lower && valToCheck <= Upper && valToCheck % Increment == 0)
                {
                    return true;
                }
            }

            return false;
        }

        public void CopyTo(object[] arr, int start)
        {
            int index = 0;
            for (int i = Lower + (start * Increment); index < arr.Length; i += Increment)
            {
                arr[index++] = i;

                if (i == Upper)
                {
                    break;
                }
            }
        }

        void ICollection.CopyTo(Array arr, int count)
        {
            throw new InvalidOperationException("'CopyTo' cannot be used on an object of type 'RangeList'.");
        }

        object ICollection.SyncRoot { get { return this; } }

        bool ICollection.IsSynchronized { get { return false; } }

        public int IndexOf(object obj)
        {
            throw new InvalidOperationException("'IndexOf' cannot be used on an object of type 'RangeList'.");
        }

        public void Insert(int index, object obj)
        {
            throw new InvalidOperationException("'Insert' cannot be used on an object of type 'RangeList'.");
        }

        public bool Remove(object obj)
        {
            throw new InvalidOperationException("'Remove' cannot be used on an object of type 'RangeList'.");
        }

        void IList.Remove(object obj)
        {
            Braid.BraidRuntimeException("'Remove' cannot be used on an object of type 'RangeList'.");
        }

        public void RemoveAt(int index)
        {
            Braid.BraidRuntimeException("unable to remove object at index '{index}': RangeList does not support 'RemoveAt'.");
        }

        public void ForEach(Callable callable)
        {
            Vector args = new Vector();
            args.Add(null);
            foreach (object val in this)
            {
                args[0] = val;
                callable.Invoke(args);
            }
        }

        public Vector Map(Callable callable)
        {
            Vector args = new Vector();
            args.Add(null);
            var result = new Vector();
            foreach (object val in this)
            {
                args[0] = val;
                result.Add(callable.Invoke(args));
            }

            return result;
        }

        IEnumerator IEnumerable.GetEnumerator()
        {
            return (IEnumerator)GetEnumerator();
        }

        public IEnumerator<object> GetEnumerator()
        {
            return new RangeListEnumerator(Lower, Upper, Increment);
        }

        public object this[int index]
        {
            get
            {
                return index * Increment + Lower;
            }

            set
            {
                Braid.BraidRuntimeException("You cannot change the elements of a 'RangeList'.");
            }
        }

        public RangeList(int lower, int upper, int increment = 1)
        {
            if (increment == 0)
            {
                Braid.BraidRuntimeException("Constructing a RangeList object: the increment argument cannot be 0.");
            }

            Upper = upper;
            Lower = lower;
            if (lower > upper)
            {
                Increment = increment > 0 ? -increment : increment;
            }
            else
            {
                Increment = increment < 0 ? -increment : increment;
            }
        }

        public object Visit(Callable func, bool visitLambdas)
        {
            Vector parameters = new Vector();
            parameters.Add(this);
            return func.Invoke(parameters);
        }

        public override string ToString()
        {
            return $"(Range :low {Lower} :hi {Upper} :incr {Increment})";
        }
    }

    /// <summary>
    /// Retruned by the 'range' function.
    /// </summary>
    public sealed class RangeListEnumerator : IEnumerator<object>
    {
        int Upper;
        int Lower;
        int Increment;
        int _current;
        bool first = true;

        public RangeListEnumerator(int lower, int upper, int increment)
        {
            Upper = upper;
            _current = Lower = lower;
            Increment = increment;
        }

        public bool MoveNext()
        {
            if ((Increment > 0 && (_current + Increment) <= Upper) || (Increment < 0 && (_current + Increment) >= Upper))
            {
                if (first)
                {
                    first = false;
                }
                else
                {
                    _current += Increment;
                }
                return true;
            }
            else
            {
                if (first)
                {
                    first = false;
                    return true;
                }

                return false;
            }
        }

        public void Dispose()
        {

        }

        public void Reset()
        {
            _current = Lower;
        }

        public object Current { get { return _current; } }
    }

    ///////////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// Debug mode flags
    /// </summary>
    public enum DebugFlags
    {
        Trace = 1,
        TraceException = 2,
        BreakPoint = 4,
    };

    ///////////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// The Braid interpreter public interfaces
    /// </summary>
    public static partial class Braid
    {
        // The PowerShell host object - should be set by the loader script 'loadbraid.ps1'.
        public static System.Management.Automation.Host.PSHost Host { get; set; }

        /// <summary>
        /// Helper function for generating annotated Braid errors
        /// </summary>
        /// <param name="code"></param>
        /// <param name="message">The error message</param>
        /// <param name="innerException">
        /// The inner exception from the original exception if there was one. Can be null.
        /// </param>
        public static void BraidRuntimeException(string message, Exception innerException = null, ISourceContext code = null)
        {
            string msg = string.Empty;
            if (code != null)
            {
                msg += GetSourceLine(code.Text, code.Offset);
            }
            else if (CallStack.Caller != null)
            {
                var cntxt = CallStack.Caller;
                msg += GetSourceLine(cntxt.Text, cntxt.Offset);
            }

            msg += BraidBaseException.Annotate(message, code);
            throw new BraidUserException(msg, innerException);
        }

        /// <summary>
        /// The directory where the Braid runtime is located.
        /// </summary>
        public static string BraidHome = Path.GetDirectoryName(typeof(Braid).Assembly.Location);

        /// <summary>
        /// Called from PowerShell to start the interpreter.
        /// </summary>
        public static object StartBraid()
        {
            ExitBraid = false;
            while (!ExitBraid)
            {
                try
                {
                    CallStack.IsInteractive = true;
                    var cmdInfo = GetPowershellCommand(Symbol.FromString("Braidrepl"));
                    var result = InvokePowerShellCommand(new Vector(), new Dictionary<string, NamedParameter>(), cmdInfo, null, false);
                    return result;
                }
                catch (Exception e)
                {
                    if (e is TargetInvocationException tie)
                    {
                        Exception inner = tie.InnerException;
                        while (inner is TargetInvocationException)
                        {
                            inner = inner.InnerException;
                        }

                        e = inner;
                    }

                    if (e is BraidExitException psee)
                    {
                        ExitBraid = true;
                        return psee.ExitValue;
                    }
                    else
                    {
                        Braid.WriteConsoleColor(ConsoleColor.Red, $"Caught fatal exception: ({e.GetType()})");
                        Braid.WriteConsoleColor(ConsoleColor.Red, $"MSG: {e.Message.Trim()}.");
                        if (e.InnerException != null)
                        {
                            Braid.WriteConsoleColor(ConsoleColor.Red, $"Inner Exception: {e.InnerException.Message}");
                        }

                        Braid.WriteConsoleColor(ConsoleColor.Red, $"Restarting REPL...");
                    }
                }
            }

            return null;
        }

        ///==============================================================================================================
        /// <summary>
        /// Boolean that tells the Braid interpreter to exit.
        /// </summary>
        public static bool ExitBraid { get; set; }

        /// <summary>
        /// Format the source line containing the specified offset.
        /// </summary>
        /// <param name="text">The source text</param>
        /// <param name="offset">Offset of the source text being processed.</param>
        /// <returns>The source line corresponding to the offset.</returns>
        public static string GetSourceLine(string text, int offset)
        {
            var sb = new StringBuilder(">>> ");

            if (string.IsNullOrEmpty(text))
            {
                return string.Empty;
            }

            if (offset < 0)
            {
                offset = 0;
            }

            if (offset >= text.Length)
            {
                offset = text.Length - 1;
            }

            int start = offset;
            if (start > 0 && text[start] == '\n')
                start--;
            while (start > 0 && text[start] != '\n')
                start--;
            if (text[start] == '\n')
                start++;
            int end = offset;
            while (end < text.Length && text[end] != '\n')
                end++;
            sb.Append(text.Substring(start, end - start));
            sb.Append("\n>>> ");
            for (int i = start; i < offset - 1; i++)
            {
                sb.Append(' ');
            }
            sb.Append("^\n");
            return sb.ToString();
        }

        //
        // Function that replaces the sequence ${expr} with the string value of the expression inside
        // If expr is enclosed in parens e.g. "Hello ${(get-name nam123)}, how are you?" it will
        // be invoked as a Braid function.
        //
        public static string ExpandString(string str)
        {
            List<(int, int)> matches = new List<(int, int)>();
            int start = 0;
            while ((start = str.IndexOf("${", start)) != -1)
            {
                start += 2;
                var end = str.IndexOf("}", start);
                if (end == -1)
                {
                    BraidRuntimeException($"Error: unclosed expansion in string: '{str}'");
                }

                // Add the tuple identifying the start and range of the expression
                matches.Add((start, end - start));
                start = end;
            }

            for (var index = matches.Count - 1; index >= 0; index--)
            {
                var m = matches[index];
                var expr = str.Substring(m.Item1, m.Item2);

                string resultStr;
                object resultObj;
                s_Expr parsedExpr = null;
                try
                {
                    parsedExpr = Parse(expr);
                }
                catch (Exception e)
                {
                    BraidRuntimeException(
                        $"Parse error while expanding fragment '{expr}' in string '{str}",
                        e);
                }

                if (parsedExpr == null)
                {
                    // BUGBUGBUGBUG - should an empty expansion be an error? Right now it evals to "".
                    resultObj = null;
                }
                else if (parsedExpr.Car is s_Expr pse)
                {
                    resultObj = Eval(pse);
                }
                else
                {
                    resultObj = GetValue(parsedExpr.Car?.ToString());
                }

                if (resultObj == null)
                {
                    resultStr = string.Empty;
                }
                else if (resultObj is IDictionary dict)
                {
                    resultStr = Utils.ToStringDict(dict);
                }
                else if (resultObj is HashSet<object> hashset)
                {
                    resultStr = Utils.ToStringHashSet(hashset);
                }
                else
                {
                    resultStr = resultObj.ToString();
                }

                str = str.Substring(0, m.Item1 - 2) +
                        resultStr +
                        str.Substring(m.Item1 + m.Item2 + 1, str.Length - m.Item1 - m.Item2 - 1);
            }

            return str;
        }

        ////////////////////////////////////////////////////////////////////////////////////////
        /// <summary>
        /// Create a delegate of the specified type out of an s-expression.
        /// </summary>
        public static Delegate CreateDelegate(Type delegateType, Callable funcToRun)
        {
            if (delegateType == null)
            {
                Braid.BraidRuntimeException($"CreateDelegate: the type of delegate to create cannot be null.");
            }

            if (funcToRun == null)
            {
                Braid.BraidRuntimeException($"CreateDelegate: the handler for delegate type ^{delegateType} cannot be null.");
            }

            if (funcToRun.Environment == null)
            {
                funcToRun.Environment = new PSStackFrame(funcToRun.File, funcToRun.Name, funcToRun, CallStack);
            }

            // Optimize a couple of common event handler types.
            if (delegateType == typeof(EventHandler))
            {
                Vector args = new Vector { null, null };
                return (EventHandler)((o, e) => { args[0] = o; args[1] = e; funcToRun.Invoke(args, null); });
            }

            if (delegateType == typeof(AsyncCallback))
            {
                Vector args = new Vector { null };
                return (AsyncCallback)(ar => { args[0] = ar; funcToRun.Invoke(args, null); });
            }

            MethodInfo invokeMethod = delegateType.GetMethod("Invoke");
            ParameterInfo[] parameters = invokeMethod.GetParameters();
            if (invokeMethod.ContainsGenericParameters)
            {
                BraidRuntimeException($"CreateDelegate: Can't convert a lambda to an open generic lambda: {delegateType}");
            }

            // Generate an event handler of the appropriate type.
            var parameterExprs = new List<ParameterExpression>();
            foreach (var parameter in parameters)
            {
                parameterExprs.Add(Expression.Parameter(parameter.ParameterType));
            }

            bool returnsSomething = !invokeMethod.ReturnType.Equals(typeof(void));

            var helper = typeof(BraidLang.Braid).GetMethod("delegateHelper");

            Expression call = Expression.Call(
                helper,
                Expression.Constant(funcToRun),
                Expression.NewArrayInit(
                    typeof(object),
                    // parameterExprs.Select(p => p.Cast(typeof(object)))
                    parameterExprs.Select(p => Expression.Convert(p, typeof(object)))
                )
            );

            if (returnsSomething)
            {
                call = Expression.Call(
                    typeof(BraidLang.Braid).GetMethod("ConvertToHelper").MakeGenericMethod(invokeMethod.ReturnType),
                    call
                );
            }

            return Expression.Lambda(delegateType, call, parameterExprs).Compile();
        }

        ////////////////////////////////////////////////////////////////////////////////////////////
        /// <summary>
        /// Helper routine used to dispatch a BraidLang delegate. This is not referenced directly,
        /// it is only used through reflection.
        /// </summary>
        /// <param name="func"></param>
        /// <param name="environment"></param>
        /// <param name="args"></param>
        /// <returns></returns>
        public static object delegateHelper(Callable func, object[] args)
        {
            Vector argVect = new Vector(args);

            try
            {
                return func.Invoke(argVect);
            }
            catch (Exception e)
            {
                BraidRuntimeException($"Delegate invocation error with args [{args}]: {e.Message}", e, func);
            }

            return null;
        }

        /////////////////////////////////////////////////////////////////////////////
        /// <summary>
        /// Helper routine for converting the result returned by delegate execution. 
        /// </summary>
        /// <typeparam name="T"></typeparam>
        /// <param name="value"></param>
        /// <returns></returns>
        public static T ConvertToHelper<T>(object value)
        {
            if (value is T tval)
            {
                return tval;
            }

            if (typeof(T) == typeof(Regex))
            {
                // Special-case regex so it gets created with the right options.
                if (value is s_Expr sexpr && sexpr.IsQuote)
                {
                    value = sexpr.Cdr;
                }

                string strval = value == null ? string.Empty : value.ToString();
                var regex = new Regex(strval, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
                return (T)Convert.ChangeType(regex, typeof(T));
            }
            else if (typeof(T) == typeof(Type) && value is string svalue)
            {
                Type btype = CallStack.LookUpType(svalue);
                if (btype != null)
                {
                    return LanguagePrimitives.ConvertTo<T>(btype);
                    // BUGBUGBUG - why doesn't this work return (T)Convert.ChangeType(btype, typeof(T));
                }

                return LanguagePrimitives.ConvertTo<T>(svalue);
            }
            else
            {
                return LanguagePrimitives.ConvertTo<T>(value);
            }
        }

        public static object ConvertTo(object value, Type targetType)
        {
            if (value != null && targetType.IsAssignableFrom(value.GetType()))
            {
                return value;
            }

            if (targetType == typeof(Regex))
            {
                // Special-case regex so it gets created with the right options.
                if (value is s_Expr sexpr && sexpr.IsQuote)
                {
                    value = sexpr.Cdr;
                }

                string strval = value == null ? string.Empty : value.ToString();
                var regex = new Regex(strval, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
                return regex;
            }
            else if ((targetType == typeof(string) || targetType.IsEnum) && value is KeywordLiteral klit)
            {
                value = klit.BaseName;
            }

            if (targetType == typeof(Type) && value is string svalue)
            {
                Type result = CallStack.LookUpType(svalue);
                if (result != null)
                {
                    return result;
                }
            }

            if (typeof(MulticastDelegate).IsAssignableFrom(targetType) && value is Callable func)
            {
                return CreateDelegate(targetType, func);
            }

            // Fallback to the PowerShell conversion routines.
            return LanguagePrimitives.ConvertTo(value, targetType);
        }

        public static bool TryConvertTo(object value, Type targetType, out object result)
        {
            // Treat as null (no) cast
            if (targetType == null)
            {
                result = value;
                return true;
            }

            if (value != null && targetType.IsAssignableFrom(value.GetType()))
            {
                result = value;
                return true;
            }

            if (targetType == typeof(Regex))
            {
                // Special-case regex so it gets created with the right options.
                if (value is s_Expr sexpr && sexpr.IsQuote)
                {
                    value = sexpr.Cdr;
                }

                string strval = value == null ? string.Empty : value.ToString();
                result = new Regex(strval, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
                return true;
            }

            if (targetType == typeof(bool))
            {
                result = BoxBool(IsTrue(value));
                return true;
            }

            if (targetType == typeof(Type) && value is string svalue)
            {
                result = CallStack.LookUpType(svalue);
                if (result != null)
                {
                    return true;
                }

                return LanguagePrimitives.TryConvertTo(value, targetType, out result);
            }

            return LanguagePrimitives.TryConvertTo(value, targetType, out result);
        }

        ////////////////////////////////////////////////////////////////////////////////////////

        /// <summary>
        /// Utility that gets an enumerable of object from any object including
        /// lists and non-enumerable scalars.
        /// </summary>
        /// <param name="obj"></param>
        /// <returns></returns>
        public static IEnumerable<object> GetEnumerableFrom(object obj)
        {
            // For null, return an empty vector
            if (obj == null)
            {
                return new Vector();
            }

            // If it's a PSObject, core it.
            if (obj is PSObject pso && !(pso.BaseObject is PSCustomObject))
            {
                obj = pso.BaseObject;
            }

            switch (obj)
            {
                // If it's IEnumerable<object>, just return it.               
                case IEnumerable<object> iobj:
                    return iobj;

                // If it's enumerable but not enumerable<object>, copy it into a vector
                // then return the enumerable from that.
                // BUGBUGBUG - this is ugly and slow - there must be a better way...
                case IEnumerable ienumexpr:
                    return new Vector(ienumexpr);

                case VectorLiteral vlit:
                    if (vlit.ValueList == null)
                        return new Vector();
                    return vlit.ValueList;

                // finally assume it's a scalar so wrap it a list and return it.
                default:
                    return new Vector { obj };
            }
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="obj"></param>
        /// <returns></returns>
        public static IEnumerable GetNonGenericEnumerableFrom(object obj)
        {
            // For null, return an empty list
            if (obj == null)
            {
                return new Vector();
            }

            // If it's a PSObject, core it.
            if (obj is PSObject pso && !(pso.BaseObject is PSCustomObject))
            {
                obj = pso.BaseObject;
            }

            switch (obj)
            {
                case Symbol sym:
                    return new Vector { sym };

                case IEnumerable iobj:
                    return iobj;

                case IEnumerator ienum:
                    // BUGBUGBUG - there should be a better way to do this.
                    var list = new Vector();
                    while (ienum.MoveNext())
                    {
                        if (_stop)
                        {
                            break;
                        }

                        list.Add(ienum.Current);
                    }

                    return list;

                default:
                    return new Vector { obj };
            }
        }

        /// <summary>
        /// Compare two items with truthy semantics. It tries a lot of things first then
        /// falls back to PowerShells comparisons.
        /// </summary>
        /// <param name="item1"></param>
        /// <param name="item2"></param>
        /// <returns></returns>
        public static bool CompareItems(object item1, object item2)
        {
            if (item1 == null)
            {
                return item2 == null;
            }

            if (item2 == null)
            {
                return item1 == null;
            }

            if (item1 is int intitem1 && item2 is int intitem2)
            {
                return intitem1 == intitem2;
            }

            if (item1 is string sitem1 && string.Equals(sitem1, item2.ToString(), StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }

            if (item1 is char c1 && item2 is char c2)
            {
                return char.ToLowerInvariant(c1) == char.ToLowerInvariant(c2);
            }

            if (item1 is BigInteger btem1 && item2 is BigInteger btem2)
            {
                return btem1 == btem2;
            }

            if (item1 is IDictionary<object, object> dict1 && item2 is IDictionary<object, object> dict2)
            {
                if (dict1.Count != dict2.Count)
                {
                    return false;
                }

                // Now compare the values
                foreach (var k in dict1.Keys)
                {
                    object val;
                    if (dict2.TryGetValue(k, out val))
                    {
                        if (!CompareItems(dict1[k], val))
                        {
                            return false;
                        }
                    }
                    else
                    {
                        return false;
                    }
                }

                return true;
            }

            if (item1 is IEnumerable<object> enum1 && item2 is IEnumerable<object> enum2)
            {
                return enum1.SequenceEqual(enum2, new ObjectComparer());
            }

            if (item1 is IEnumerable ie1 && item2 is IEnumerable ie2)
            {
                var ia1 = ie1.GetEnumerator();
                foreach (var o1 in ie2)
                {
                    if (!ia1.MoveNext())
                    {
                        return false;
                    }
                    if (!CompareItems(ia1.Current, o1))
                    {
                        return false;
                    }
                }

                // If both enumerators are exhausted, then return true otherwise false.
                return !ia1.MoveNext();
            }

            if ((item1 is IEnumerable && !(item2 is IEnumerable)) ||
               (!(item1 is IEnumerable) && item2 is IEnumerable))
            {
                // if one item is enumerable and the other is not, then false.
                return false;
            }

            if ((item1 is BraidTypeBase lt1 && item2 is BraidTypeBase lt2))
            {
                return lt1.Equals(lt2);
            }

            if (item1 is Symbol symitem1 && item2 is Symbol symitem2)
            {
                return symitem1.SymId == symitem2.SymId;
            }

            if (item1 is KeywordLiteral kw1 && item2 is KeywordLiteral kw2)
            {
                return kw1.KeywordId == kw2.KeywordId;
            }

            return LanguagePrimitives.Equals(item1, item2, true);
        }

        /// <summary>
        /// Sanitize an argument object. Used by InvokeMember and the 'new'
        /// function to fix up members before passing them along.
        /// </summary>
        /// <param name="arg">The argument to fix up.</param>
        /// <returns>The fixed object.</returns>
        static object FixupArg(object arg)
        {
            switch (arg)
            {
                case PSObject pso:
                    arg = (pso.BaseObject is PSCustomObject) ? pso : pso.BaseObject;
                    break;

                case Symbol symarg:
                    arg = symarg.Value;
                    break;

                case BraidLiteral pslit:
                    arg = pslit.Value;
                    break;
            }

            return arg;
        }

        ////////////////////////////////////////////////////////////////////////////////
        /// <summary>
        /// Routine to dynamically access a property. field or method on an object.
        /// This is used by the '.' function e.g. (. "hello" 1 2). This method relies on the
        /// PSObject interface to access members so extended members will be visible.
        /// (Also see the MemberLteral class.)
        /// </summary>
        /// <param name="quiet">When true, no error will be raised if the property doesn't exist, just returns null</param>
        /// <param name="memberName">The name of the member to invoke.</param>
        /// <param name="args">The arguments to pass to the invoked member.</param>
        /// <returns>The result of the method invocation</returns>
        public static object InvokeMember(bool quiet, string memberName, Vector args)
        {
            if (args.Count < 1)
            {
                BraidRuntimeException($"Missing argument object while accessing member '.{memberName}'.");
            }

            object obj = args[0];

            if (obj == null)
            {
                if (quiet)
                {
                    return null;
                }

                BraidRuntimeException($"Can't access member '.{memberName}' on a null object.");
            }

            if (obj is PSObject pso && !(pso.BaseObject is PSCustomObject))
            {
                obj = pso.BaseObject;
            }

            // Sanitize the arguments...
            for (var i = 1; i < args.Count; i++)
            {
                args[i] = FixupArg(args[i]);
            }

            try
            {
                // Static invocations use reflection
                if (obj is Type tobj)
                {
                    MemberInfo[] members = tobj.GetMember(memberName,
                        BindingFlags.Static | BindingFlags.Public | BindingFlags.IgnoreCase);

                    if (members.Length > 0)
                    {
                        MemberInfo member = members[0];

                        if (member != null)
                        {
                            if (member is PropertyInfo prop)
                            {
                                if (args.Count < 2)
                                {
                                    return prop.GetValue(null);
                                }
                                else
                                {
                                    prop.SetValue(null, args[1]);
                                    return null;
                                }
                            }
                            else if (member is FieldInfo field)
                            {
                                if (args.Count < 2)
                                {
                                    return field.GetValue(null);
                                }
                                else
                                {
                                    field.SetValue(null, args[1]);
                                    return null;
                                }
                            }
                            else if (members.Length > 0)
                            {
                                object[] argArray = new object[args.Count - 1];
                                int index = members.Length - 1;
                                args.CopyTo(1, argArray, 0, args.Count - 1);
                                while (index >= 0)
                                {
                                    if (members[index--] is MethodInfo method)
                                    {
                                        var parameters = method.GetParameters();
                                        int numParameters = parameters.Length;
                                        try
                                        {
                                            if (argArray.Length == numParameters)
                                            {
                                                var method_result = method.Invoke(null, argArray);
                                                return method_result;
                                            }
                                        }
                                        catch (System.Reflection.TargetParameterCountException)
                                        {
                                            // Ignore this and try again...
                                        }
                                        catch (System.NotSupportedException)
                                        {
                                            // Ignore this and try again...
                                        }
                                        catch (System.ArgumentException)
                                        {
                                            // Ignore this and try again...
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            catch (MissingMemberException mme)
            {
                if (quiet)
                {
                    return null;
                }

                if (args[0] is PSObject psobject)
                {
                    object bo = psobject.BaseObject;
                    BraidRuntimeException(
                        $"Static member '.{memberName}' cannot be found on type '^{bo.GetType()}' (^PSObject)", mme);
                }
                else
                {
                    BraidRuntimeException(
                        $"Static member '.{memberName}' cannot be found on type '{obj}'", mme);
                }

                // Otherwise ignore this exception and fall through
            }

            // Try for instance methods next...
            PSObject psobj = PSObject.AsPSObject(args[0]);

            var mi = psobj.Members[memberName];

            if (mi == null)
            {
                if (quiet)
                {
                    return null;
                }

                if (args[0] is PSObject)
                {
                    object bo = psobj.BaseObject;
                    BraidRuntimeException(
                        $"member '.{memberName}' cannot be found on an object '{Braid.Truncate(args[0])}' of type '^{bo.GetType()}' (^PSObject).");

                }
                else
                {
                    BraidRuntimeException(
                        $"member '.{memberName}' cannot be found on an object '{Braid.Truncate(args[0])}' of type '^{args[0].GetType()}'.");

                }
            }

            object result = null;
            try
            {
                if (mi is PSMethod psmethod)
                {
                    switch (args.Count - 1)
                    {
                        case 0:
                            result = psmethod.Invoke();
                            break;
                        case 1:
                            result = psmethod.Invoke(args[1]);
                            break;
                        case 2:
                            result = psmethod.Invoke(args[1], args[2]);
                            break;
                        case 3:
                            result = psmethod.Invoke(args[1], args[2], args[3]);
                            break;
                        case 4:
                            result = psmethod.Invoke(args[1], args[2], args[3], args[4]);
                            break;
                        case 5:
                            result = psmethod.Invoke(args[1], args[2], args[3], args[4], args[5]);
                            break;
                        case 6:
                            result = psmethod.Invoke(args[1], args[2], args[3], args[4], args[5], args[6]);
                            break;
                        case 7:
                            result = psmethod.Invoke(args[1], args[2], args[3], args[4], args[5], args[6], args[7]);
                            break;
                        default:
                            Braid.BraidRuntimeException(
                                $"Too many arguments when attempting to invoke method '.{memberName}'; only 7 are supported not {args.Count}");
                            break;
                    }
                }
                else
                {
                    if (args.Count > 1)
                    {
                        // Set a property or field
                        result = mi.Value = args[1];
                    }
                    else
                    {
                        // retrieve a property or field
                        result = mi.Value;
                    }
                }
            }
            catch (Exception e)
            {
                if (quiet)
                {
                    return null;
                }

                BraidRuntimeException(
                    $"Error processing member '.{memberName}' on an object '{Braid.Truncate(args[0])}' of type ^{args[0].GetType()}; {e.Message}", e);
            }

            if (result is PSObject psoResult && !(psoResult.BaseObject is PSCustomObject))
            {
                return psoResult.BaseObject;
            }
            else
            {
                return result;
            }
        }

        /// <summary>
        /// Utility to safely truncate and format a string as a single line so it will
        /// fit on the screen
        /// </summary>
        /// <param name="obj">The object to render.</param>
        /// <returns>The rendered object.</returns>
        public static string Truncate(object obj)
        {
            if (obj == null)
            {
                return string.Empty;
            }
            int x = Console.CursorLeft;
            int width = Console.WindowWidth - x;
            if (width < 40)
            {
                width = 40;
            }

            string str = obj.ToString();
            str = Regex.Replace(str, "[ \t\n\\r]+", " ").Trim();

            if (str.Length < width)
            {
                return str;
            }
            else
            {
                return str.Substring(0, width - 3) + "...";
            }
        }

        ////////////////////////////////////////////////////////////////////////////////
        /// <summary>
        /// Implements then truthiness semantics. Explicitly does not return BoxedTrue/BoxedFalse.
        /// </summary>
        /// <param name="obj">The object to test</param>
        /// <returns>true if the object is determined to meet the criteria for truth.</returns>
        public static bool IsTrue(object obj)
        {
            if (obj == null)
            {
                return false;
            }

            if (obj is PSObject psobj && !(obj is PSCustomObject))
            {
                obj = psobj.BaseObject;
            }

            switch (obj)
            {
                case bool bobj:
                    return bobj;

                case String ostr:
                    return ostr.Length != 0;

                case int iobj:
                    return iobj != 0;

                case long lobj:
                    return lobj != 0;

                case double dobj:
                    return dobj != 0;

                case BigInteger bigobj:
                    return bigobj != 0;

                case char chr:
                    return chr != 0;

                case IList ilobj:
                    return ilobj.Count != 0;

                case float fobj:
                    return fobj != 0;

                case Decimal deobj:
                    return deobj != 0;

                default:
                    return obj != AutomationNull.Value;
            }
        }

        ////////////////////////////////////////////////////////
        //
        // Initialize the variable and built-in function tables
        //

        public static object BoxedTrue = true;
        public static object BoxedFalse = false;

        public static object BoxBool(bool val)
        {
            if (val)
                return BoxedTrue;
            return BoxedFalse;
        }

        const int _num_boxed_ints = 1000;
        static object[] _boxed_ints = null;
        public static object BoxInt(int val)
        {
            if (_boxed_ints == null)
            {
                _boxed_ints = new object[_num_boxed_ints];
                for (int i = 0; i < _num_boxed_ints; i++)
                {
                    _boxed_ints[i] = i;
                }
            }

            if (val >= 0 && val < _num_boxed_ints)
                return _boxed_ints[val];
            return val;
        }

        // Pointers to various Braid functions.
        public static Func<Vector, object> pipe_function = null;
        public static Func<Vector, object> recur_function = null;
        public static Func<Vector, object> recur_to_function = null;

        //BUGBUGBUG - allows multiple assignment in let/def and function arguments but need to add more error handling.
        /// <summary>
        /// BUGBUGBUG - should also unify this code with the pattern code that does multiple assignments.
        /// </summary>
        /// <param name="callStack">The call stack to use when binding</param>
        /// <param name="namesym">The compound symbol being assigned</param>
        /// <param name="value">The value(s) to bind</param>
        /// <param name="scopeType">The scope at which the binding should table place</param>
        /// <returns></returns>
        public static bool MultipleAssignment(PSStackFrame callStack, Symbol namesym, object value, ScopeType scopeType, bool quiet = false)
        {
            bool bindRestToLast = true;
            if (namesym.CompoundSymbol)
            {
                bindRestToLast = namesym._bindRestToLast;
                List<Symbol> elements = namesym.ComponentSymbols;

                return BindMultiple(callStack, value, scopeType, elements, bindRestToLast, quiet);
            }
            else
            {
                return false;
            }
        }

        internal static bool BindMultiple(PSStackFrame callStack, object value, ScopeType scopeType, List<Symbol> vars, bool bindRestToLast, bool quiet = false)
        {
            Symbol varsym;
            void setFn(Symbol symToSet, object valToSet)
            {
                switch (scopeType)
                {
                    case ScopeType.Lexical:
                        callStack.Set(symToSet, valToSet);
                        break;
                    case ScopeType.Local:
                        callStack.SetLocal(symToSet, valToSet);
                        break;
                    case ScopeType.Global:
                        _globalScope.Set(symToSet, valToSet);
                        break;
                }
            }

            int varIndex = 0;
            switch (value)
            {
                case IEnumerable ienum:

                    ISeq values;
                    if (ienum is ISeq lst)
                    {
                        values = lst;
                    }
                    else
                    {
                        values = s_Expr.FromEnumerable(ienum);
                    }

                    while (varIndex < vars.Count)
                    {
                        varsym = vars[varIndex];

                        // bind remaining values to the last element.
                        if (varIndex == vars.Count - 1)
                        {
                            if (values != null && values.Cdr == null)
                            {
                                if (bindRestToLast)
                                    setFn(varsym, values);
                                else
                                    setFn(varsym, values.Car);
                            }
                            else
                            {
                                if (!bindRestToLast)
                                {
                                    return false;
                                }
                                else
                                {
                                    setFn(varsym, values);
                                }
                            }
                        }
                        else if (values != null)
                        {
                            setFn(varsym, values.Car);
                        }
                        else
                        {
                            return false;
                            // setFn(varsym, null);
                        }

                        varIndex++;
                        if (values != null)
                        {
                            // If values.cdr is a pointer, just assign it to values
                            if (values.Cdr is ISeq seq)
                            {
                                values = seq;
                            }
                            else
                            {
                                // Otherwise, wrap it in a list node and assign that node to values.

                                values = values.Cdr == null ? null : new s_Expr(values.Cdr);
                            }
                        }
                    }

                    return true;

                case System.Runtime.CompilerServices.ITuple tuple:
                    int num = tuple.Length;
                    int index = 0;
                    while (varIndex < vars.Count)
                    {
                        varsym = vars[varIndex++];

                        // bind remaining values to the last element.
                        if (index < num)
                        {
                            setFn(varsym, tuple[index]);
                        }
                        else
                        {
                            return false;
                        }

                        index++;
                    }

                    if (index < num)
                    {
                        return false;
                    }

                    return true;

                case KeyValuePair<object, object> pair:
                    if (vars.Count() != 2)
                    {
                        if (quiet)
                            return false;
                        BraidRuntimeException("multiple assignment of a Key/Value pair requires 2 target variables.");
                    }

                    varsym = vars[varIndex++];
                    setFn(varsym, pair.Key);
                    varsym = vars[varIndex++];
                    setFn(varsym, pair.Value);
                    return true;

                case DictionaryEntry pair:
                    if (vars.Count() != 2)
                    {
                        if (quiet)
                            return false;
                        BraidRuntimeException("multiple assignment of a Key/Value pair requires 2 target variables.");
                    }

                    varsym = vars[varIndex++];
                    setFn(varsym, pair.Key);
                    varsym = vars[varIndex++];
                    setFn(varsym, pair.Value);
                    return true;

                case null:
                    return false;

                default:
                    if (quiet)
                        return false;
                    BraidRuntimeException(
                        $"multiple assignment can only be used with lists, vectors, dictionaries and tuples; not '{value}' (^{value.GetType()}).");
                    return false;
            }
        }

        /// <summary>
        /// Table for creating end-user associations e.g.
        ///     (Set-Assoc + "mykey" "foo") ; associate a key 'mykey' with value "foo" to the + function 
        // /    (Get-Assoc + "mykey")       ; Retrieve the value of the associated key
        /// </summary>
        private static ConditionalWeakTable<object, ConcurrentDictionary<string, object>> associationTable =
            new ConditionalWeakTable<object, ConcurrentDictionary<string, object>>();

        /// <summary>
        /// Gets the values associated with the "key" object
        /// </summary>
        /// <param name="key">The object that has the associated values</param>
        /// <param name="attr">The member of the association to return.</param>
        /// <returns>The associated value.</returns>
        public static object GetAssoc(object key, string attr)
        {
            ConcurrentDictionary<string, object> result;
            if (associationTable.TryGetValue(key, out result))
            {
                if (result != null)
                {
                    object attrval;
                    if (result.TryGetValue(attr, out attrval))
                    {
                        return attrval;
                    }
                }
            }
            return null;
        }

        /// <summary>
        /// Get the dictionary of associated values for the "key" object
        /// </summary>
        /// <param name="key">The object that has the associated values</param>
        /// <returns>The dictionary of associated values.</returns>
        public static object GetAssoc(object key)
        {
            ConcurrentDictionary<string, object> result;
            if (associationTable.TryGetValue(key, out result))
            {
                return result;
            }
            return null;
        }

        /// <summary>
        /// Associate a named value with an object
        /// </summary>
        /// <param name="key">The object containing the association table</param>
        /// <param name="attr">The name of the associated value</param>
        /// <param name="value">The value to associate with the name</param>
        public static void PutAssoc(object key, string attr, object value)
        {
            var properties = associationTable.GetValue(key,
                (keyval) => new ConcurrentDictionary<string, object>(StringComparer.OrdinalIgnoreCase));
            properties[attr] = value;
        }

        /// <summary>
        /// Utility to write a message to the console in color.
        /// </summary>
        /// <param name="forecolor"></param>
        /// <param name="str"></param>
        public static void WriteConsoleColor(ConsoleColor forecolor, string str)
        {
            ConsoleColor oldColor = Console.ForegroundColor;
            Console.ForegroundColor = forecolor;
            try
            {
                Console.WriteLine(str);
            }
            finally
            {
                Console.ForegroundColor = oldColor;
            }
        }

        /// <summary>
        /// Takes an operator and an object and returns a curried function.
        /// </summary>
        /// <param name="call">The function to curry</param>
        /// <param name="arg">The second argument to the function</param>
        /// <returns></returns>
        public static Callable curryFunction(object funcToCall, object arg)
        {
            s_Expr body;
            Vector __it_vector;
            string name = null;
            FunctionType ftype;
            string funcname;
            Symbol and_rest = Symbol.FromString("&_rest");
            Symbol rest = Symbol.FromString("_rest");

            object resolvedFn = GetFunc(CallStack, funcToCall, out ftype, out funcname);

            if (resolvedFn is UserFunction callable)
            {
                body = new s_Expr(resolvedFn);
                __it_vector = new Vector();

                if (callable.Arguments.Count - 1 > 0)
                {
                    __it_vector.Add(new VarElement(Symbol.sym_it));
                    if (callable.Arguments.Count - 1 > 1)
                    {
                        __it_vector.Add(new VarElement(and_rest));
                        body
                            .Add(Symbol.sym_it)
                                .Add(new s_Expr(Symbol.sym_splat, rest))
                                    .Add(arg);
                    }
                    else
                    {
                        body.Add(Symbol.sym_it).Add(arg);
                    }
                }
                else
                {
                    body.Add(arg);
                }

                name = callable.Name;
            }
            else if (resolvedFn is PatternFunction pat)
            {
                __it_vector = new Vector { new VarElement(Symbol.sym_it), new VarElement(and_rest) };
                body = new s_Expr(resolvedFn);
                body.Add(Symbol.sym_it).Add(arg).Add(new s_Expr(Symbol.sym_splat, rest));

                name = pat.Name;
            }
            else
            {
                __it_vector = new Vector();
                body = new s_Expr(resolvedFn);
                __it_vector.Add(Symbol.sym_it);
                body
                    .Add(Symbol.sym_it)
                    .Add(arg);
                name = resolvedFn.ToString();
            }

            // Construct the body list
            body = new s_Expr(body);

            var lambda = new UserFunction(FunctionType.Function, $"lambda", __it_vector,
                            null, body, null);

            return lambda;
        }

        /// <summary>
        /// Check the parameter types of a method against a list of types.
        /// </summary>
        /// <param name="mi"></param>
        /// <param name="typesToCheck"></param>
        /// <returns></returns>
        static bool CheckParameters(MethodInfo mi, Type[] typesToCheck)
        {
            var parameters = mi.GetParameters();

            if (typesToCheck == null)
            {
                return parameters.Length == 0;
            }

            if (parameters.Length != typesToCheck.Length)
            {
                return false;
            }

            for (int index = 0; index < parameters.Length; index++)
            {
                if (parameters[index].ParameterType != typesToCheck[index])
                {
                    return false;
                }
            }

            return true;
        }

        /// <summary>
        /// Utility to turn a Braid Callable expression into an async Task
        /// </summary>
        /// <param name="expression"></param>
        /// <param name="argument"></param>
        /// <returns></returns>
        static Task<object> ExpressionToTask(Callable expression, object argument)
        {
            // Make a copy of the current variable settings
            var callstack = CallStack.GetSnapshot();

            var argvec = new Vector { argument };

            Func<object> func = () =>
            {
                if (_callStackStack == null)
                {
                    _callStackStack = new Stack<PSStackFrame>();
                }

                _callStack = callstack;

                try
                {
                    return expression.Invoke(argvec);
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

            return System.Threading.Tasks.Task<object>.Factory.StartNew(func);
        }

        //////////////////////////////////////////////////////////////////////////
        /// <summary>
        /// Method that uses PowerShell to resolve paths.
        /// </summary>
        /// <param name="fileToRead"></param>
        /// <returns></returns>
        public static string ResolvePath(string fileToRead)
        {
            /*BUGBUGBUGBUG this might be a better way to get this information by doing... */
            /* . (. (. executionContext 'SessionState) 'path) 'GetResolvedPSPathFromPSPath "~") */
            Collection<PSObject> resolvedPathPs = null;
            Runspace allocatedRS = null;
            PowerShell pl = null;

            try
            {
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

                resolvedPathPs = pl
                    .AddCommand("Resolve-Path")
                    .AddParameter("path", fileToRead)
                    .Invoke();
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

            if (resolvedPathPs.Count == 0)
            {
                BraidRuntimeException(
                    $"path value '{fileToRead}' did not resolve to a valid file name.");
            }

            return ((PathInfo)(resolvedPathPs[0].BaseObject)).Path;
        }

        /// <summary>
        /// Get the value of a braid variable. Used by "loadbraid.ps1".
        /// </summary>
        /// <param name="nameObj">The name of the variable to retrieve</param>
        /// <param name="NoErrorIfNotExist"></param>
        /// <returns></returns>
        public static object GetValue(object nameObj, bool NoErrorIfNotExist)
        {
            if (nameObj == null)
            {
                BraidRuntimeException("The name argument to GetValue() cannot be null.");
            }

            Symbol varsym = nameObj as Symbol;
            if (varsym == null)
            {
                varsym = Symbol.FromString(nameObj.ToString());
                if (varsym == null)
                {
                    BraidRuntimeException("GetValue(): requires a non-empty symbol or string to retrieve.");
                }
            }

            var v = CallStack.GetVariable(varsym);
            if (v != null)
            {
                return v.Value;
            }

            var pwshcmd = GetPowershellCommand(varsym, true);
            if (pwshcmd != null)
            {
                return pwshcmd;
            }

            if (NoErrorIfNotExist)
            {
                return null;
            }

            BraidRuntimeException($"GetValue(): unbound symbol '{varsym}'.");

            return null;
        }

        public static object GetValue(object nameObj)
        {
            return GetValue(nameObj, true);
        }

        public static object SetVariable(Symbol varsym, object valueToSet)
        {
            if (varsym == null)
            {
                BraidRuntimeException("The name of the variable to set cannot be null");
            }

            return CallStack.Set(varsym, valueToSet);
        }

        [ThreadStatic]
        public static PSStackFrame _callStack = new PSStackFrame("repl", "global", 0);

        [ThreadStatic]
        public static Stack<PSStackFrame> _callStackStack = new Stack<PSStackFrame>();

        public static Stack<PSStackFrame> CallStackStack { get => _callStackStack; }

        [ThreadStatic]
        public static PSStackFrame _globalScope = _callStack;

        /// <summary>
        /// The active stack frame.
        /// </summary>
        public static PSStackFrame CallStack
        {
            get { return _callStack; }
            set
            {
                BraidRuntimeException("CallStack can't be set. Use Push");
            }
        }

        /// <summary>
        /// Push a new stackframe onto the stack
        /// </summary>
        /// <param name="newFrame">The frame to push</param>
        /// <returns>The frame that was pushed.</returns>
        public static PSStackFrame PushCallStack(PSStackFrame newFrame)
        {
            if (newFrame.Caller == null)
            {
                throw new InvalidOperationException("Pushing Bad stackframe.");
            }

            _callStackStack.Push(_callStack);
            _callStack = newFrame;
            //BUGBUGBUG Console.WriteLine($"Pushing depth {_callStackStack.Count} TID {System.Threading.Thread.CurrentThread.ManagedThreadId}: {_callStack.File}:{_callStack?.Caller.LineNo}");

            return newFrame;
        }

        /// <summary>
        /// Pop the current stack frame.
        /// </summary>
        /// <returns></returns>
        public static PSStackFrame PopCallStack()
        {
            //string offset = Enumerable.Range(0, _callStackStack.Count * 4).Select(s => " ").Aggregate((x, y) => (string.Concat(x, y)));
            //string vars = string.Join(",", _callStack.Vars.Keys);
            //Console.WriteLine($"{offset}Popping CallStack function:{_callStack.Function} depth {_callStackStack.Count } keys: {vars}");

            if (_callStackStack.Count == 0)
            {
                // BUGBUGBUG Console.WriteLine($"Warning: Stack underflow in function {_current_function} at {_current_file}:{_lineno}");
                BraidRuntimeException($"Stack underflow in function '{_callStack.Function}' at '{_callStack.File}':{_callStack?.Caller.LineNo}");
                return null;
            }
            // BUGBUGBUG Console.WriteLine($"Popping depth {_callStackStack.Count} TID {System.Threading.Thread.CurrentThread.ManagedThreadId}: {_callStack.File}':{_callStack?.Caller.LineNo}");

            return (_callStack = _callStackStack.Pop());
        }

        /// <summary>
        /// Utility to do dynamic (activation stack) lookup rather than
        /// doing a strictly local lookup. This function returns variables
        /// not values. It's mostly intended for debugging.
        /// </summary>
        /// <param name="sym">The symbol corresponding to the name to look up</param>
        /// <returns>The BraidVariable object if found or nil otherwise.</returns>
        public static object GetDynamic(Symbol sym)
        {
            BraidVariable obj;

            foreach (var sf in _callStackStack)
            {
                // Only look in the local vars
                if (sf.Vars.TryGetValue(sym, out obj))
                {
                    return obj;
                }
            }

            return null;
        }

        /////////////////////////////////////////////////////////////////////////////////
        /// <summary>
        /// BUGBUGBUGBUG
        /// </summary>
        /// <param name="detailed"></param>
        /// <param name="filter"></param>
        public static void PrintCallStack(bool detailed, Regex filter)
        {
            // Print the stacked frames in reverse so the most recent frame comes
            // at the bottom of the printed text (since terminals scroll up).
            int count = 0;
            foreach (var sf in _callStackStack.Reverse().Skip(1))
            {
                WriteConsoleColor(ConsoleColor.Green, $"[ {count++} ]====================================================================");
                sf.PrintStackFrame(detailed, filter);
                Console.WriteLine();
            }

            // Finally print the current frame
            WriteConsoleColor(ConsoleColor.Green, $"[ {count++} ]====================================================================");
            CallStack.PrintStackFrame(detailed, filter);
            Console.WriteLine();
        }

        /////////////////////////////////////////////////////////////////////////////////
        /// <summary>
        /// Gets the current Braid stacktrace as a string suitable for printing.
        /// </summary>
        /// <returns>the stack trace</returns>
        public static string GetStackTrace()
        {
            StringBuilder sb = new StringBuilder();
            bool show = true;
            string oldmsg = String.Empty;
            if (_callStackStack == null)
            {
                if (_callStack == null)
                {
                    BraidRuntimeException("_callStack and _callStackStack are both null - Panic!");
                }

                return _callStack.GetContextMessage();
            }

            /* BUGBUGBUGBUG - don't add the current scope to the string? */
            sb.Append(_callStack.GetContextMessage());
            sb.Append("\n");

            foreach (var sf in _callStackStack)
            {
                var smsg = sf.GetContextMessage();
                if (smsg != oldmsg)
                {
                    show = true;
                    sb.Append(smsg);
                    oldmsg = smsg;
                    sb.Append("\n");
                }
                else if (show)
                {
                    // Add ellipses for repeated frames...
                    sb.Append(smsg);
                    sb.Append("\n      :\n      :\n");
                    show = false;
                }
            }
            return sb.ToString();
        }

        public static PSStackFrame GlobalScope
        {
            get { return _globalScope; }
        }

        /// <summary>
        /// Function to discover and identify functions and their types.
        /// </summary>
        /// <param name="callStack">The call stack to search</param>
        /// <param name="funcToGet">The function to get</param>
        /// <param name="ftype">The type of function that was found</param>
        /// <param name="funcName">The name of the function that was found</param>
        /// <param name="noExternals"></param>
        /// <param name="lookup"></param>
        /// <returns></returns>
        public static object GetFunc(PSStackFrame callStack, object funcToGet, out FunctionType ftype, out string funcName, bool noExternals = false, bool lookup = true)
        {
            if (funcToGet is PSObject pso)
            {
                funcToGet = pso.BaseObject;
            }

            // First check to see if the argument is directly executable (no symbol lookup required.)
            // If so, then just return that value.
            if (funcToGet is Callable f2c)
            {
                ftype = f2c.FType;
                funcName = f2c.Name;
                return f2c;
            }

            ftype = FunctionType.Function;
            if (funcToGet is IInvokeableValue invokable)
            {
                funcName = invokable.ToString();
                return invokable;
            }

            Symbol funcSymbol = null;
            if (funcToGet == null)
            {
                funcName = string.Empty;
                return null;
            }

            // Next see if the funcToGet names an entry in the variable table
            // This can either be a Symbol or a string.
            funcName = null;
            bool gotFuncFromSymbol = false;
            if (funcToGet is Symbol sym)
            {
                funcSymbol = sym;
                funcName = sym.Value;
                var fvar = callStack.GetVariable(sym);

                if (fvar != null)
                {
                    gotFuncFromSymbol = true;
                    funcToGet = fvar.Value;
                }
            }
            else if (funcToGet is string str)
            {
                if (string.IsNullOrEmpty(str))
                {
                    return false;
                }

                funcSymbol = Symbol.FromString(str);
                funcName = funcSymbol.Value;
                var fval = callStack.GetValue(funcSymbol);
                if (fval != null)
                {
                    gotFuncFromSymbol = true;
                    funcToGet = fval;
                }
            }

            // Now process the resulting value returned from the variable table.
            switch (funcToGet)
            {
                case Callable cb:
                    ftype = cb.FType;
                    funcName = cb.Name;
                    return cb;

                case FunctionLiteral ll:
                    funcName = "lambda";
                    return ll.Value;

                case Func<Vector, object> fn:
                    funcName = funcName ?? "<compiled function>";
                    return new Function(funcName, fn);

                case IInvokeableValue iv:
                    funcName = iv.ToString();
                    return iv;

                case s_Expr sexpr:
                    if (funcSymbol == null)
                    {
                        // Handle ((func ...) 1 2 3) as opposed to
                        //        (func 1 2 3)
                        // i.e. an indirect reference to a function.
                        if (sexpr.IsLambda)
                        {
                            ftype = FunctionType.Function;
                        }
                        funcName = sexpr.Car.ToString();
                    }
                    else
                    {
                        funcName = funcSymbol.Value;
                    }

                    return sexpr;

                // If argument is a System.Type, wrap it in a TypeLiteral which is IInvokeableValue
                case Type type:
                    var tlit = new TypeLiteral(type);
                    funcName = tlit.TypeName;
                    return tlit;

                // Wrap a dictionary in a Function so it can be invoked
                case IDictionary dict:
                    // Handle indexing dictionaries
                    //   ({:a 1 :b 2} :b)
                    // or assigning to elements in dictionaries
                    //   ({:a 1 :b 2} :b 3}
                    funcName = "<IDictionary>";
                    return new Function(funcName, (Func<Vector, object>)(args =>
                    {
                        if (args.Count > 2)
                        {
                            BraidRuntimeException($"Dictionary as a function requires 1 or 2 non-null arguments, {args.Count} were passed.");
                        }

                        if (args.Count == 0)
                        {
                            return dict;
                        }

                        object index = args[0];
                        if (index is Vector vect)
                        {
                            // handle abc[3]
                            index = vect[0];
                        }

                        if (index == null)
                        {
                            return dict;
                        }

                        if (args.Count == 1)
                        {
                            return dict[index];
                        }

                        dict[index] = args[1];
                        return dict;
                    }));

                // Wrap a hashset in a Function so it can be invoked
                case HashSet<object> hashset:
                    // Handle indexing hash sets
                    //   (#{:a 1 :b 2} :b)
                    funcName = "<HashSet>";
                    return new Function(funcName, (Func<Vector, object>)(args =>
                    {
                        if (args.Count > 2)
                        {
                            BraidRuntimeException($"HashSet as a function requires 0-2 non-null arguments, {args.Count} were passed.");
                        }

                        if (args.Count == 0)
                        {
                            return hashset;
                        }

                        object index = args[0];
                        if (index is Vector vect)
                        {
                            // handle abc[3]
                            index = vect[0];
                        }

                        if (index == null)
                        {
                            return hashset;
                        }

                        if (args.Count == 2)
                        {
                            bool set = Braid.IsTrue(args[1]);
                            if (hashset.Contains(args[0]))
                            {
                                if (!set)
                                {
                                    hashset.Remove(args[0]);
                                }
                            }
                            else
                            {
                                if (set)
                                {
                                    hashset.Add(args[0]);
                                }
                            }

                            return hashset;
                        }

                        return hashset.Contains(index);
                    }));

                // Wrap an array in a Function so it can be invoked
                case Array arr:
                    // Special-case arrays instead of just falling through to IList because
                    // arrays can be multidimensional. (See levendtien.tl example)
                    funcName = "<Array>";
                    return new Function(funcName, args =>
                    {
                        if (args.Count > 2)
                        {
                            BraidRuntimeException($"Array as a function requires 1 or 2 non-null arguments, {args.Count} were passed.");
                        }

                        if (args.Count == 0)
                        {
                            return arr;
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
                                if (arr.Rank != vect.Count)
                                {
                                    BraidRuntimeException($"when indexing into a {arr.Rank}-dimensional array, the number " +
                                        $"of indexes provided must match the number of array dimensions; {arr.Rank} != {vect.Count}");
                                }

                                if (args.Count == 1)
                                {
                                    switch (arr.Rank)
                                    {
                                        case 1:
                                            // handle abc[3]
                                            return arr.GetValue(ConvertToHelper<int>(vect[0]));

                                        case 2:
                                            return arr.GetValue(ConvertToHelper<int>(vect[0]), ConvertToHelper<int>(vect[1]));

                                        case 3:
                                            return arr.GetValue(ConvertToHelper<int>(vect[0]), ConvertToHelper<int>(vect[1]),
                                                ConvertToHelper<int>(vect[2]));

                                        case 4:
                                            return arr.GetValue(ConvertToHelper<int>(vect[0]), ConvertToHelper<int>(vect[1]),
                                                ConvertToHelper<int>(vect[2]), ConvertToHelper<int>(vect[3]));

                                        default:
                                            BraidRuntimeException($"accessing array: only array ranks of 1-{arr.Rank} are supported, not {vect.Count}");
                                            break;
                                    }
                                }
                                else
                                {
                                    switch (arr.Rank)
                                    {
                                        case 1:
                                            // handle abc[3]
                                            arr.SetValue(args[1], ConvertToHelper<int>(vect[0]));
                                            return arr;

                                        case 2:
                                            arr.SetValue(args[1], ConvertToHelper<int>(vect[0]), ConvertToHelper<int>(vect[1]));
                                            return arr;

                                        case 3:
                                            arr.SetValue(args[1], ConvertToHelper<int>(vect[0]), ConvertToHelper<int>(vect[1]),
                                                ConvertToHelper<int>(vect[2]));
                                            return arr;

                                        case 4:
                                            arr.SetValue(args[1], ConvertToHelper<int>(vect[0]), ConvertToHelper<int>(vect[1]),
                                                ConvertToHelper<int>(vect[2]), ConvertToHelper<int>(vect[3]));
                                            return arr;

                                        default:
                                            BraidRuntimeException($"setting array: only array ranks of 1-{arr.Rank} are supported, not {vect.Count}");
                                            break;
                                    }
                                }

                            }
                            else
                            {
                                index = ConvertToHelper<int>(args[0]);
                            }
                        }
                        catch (Exception e)
                        {
                            BraidRuntimeException($"index '{args}' for array was invalid: {e.Message}");
                        }

                        if (args.Count == 1)
                        {
                            return arr.GetValue(index);
                        }

                        arr.SetValue(args[1], index);
                        return arr;
                    });

                // Wrap an IList in a Function so it can be invoked
                case IList list:
                    funcName = "<IList>";
                    return new Function(funcName, args =>
                    {
                        if (args.Count == 0)
                        {
                            return list;
                        }

                        if (args.Count > 2)
                        {
                            BraidRuntimeException($"Using an ^IList as a function requires 1 or 2 non-null arguments, {args.Count} were passed.");
                        }

                        int index = 0;
                        try
                        {
                            if (args[0] == null)
                            {
                                index = 0;
                            }
                            else if (args[0] is int iindex)
                            {
                                index = iindex;
                            }
                            else if (args[0] is Vector vect)
                            {
                                // handle abc[3]
                                if (vect.Count != 1)
                                {
                                    BraidRuntimeException("When indexing an ^IList with a vector, that vector must only be one element long.");
                                }

                                index = ConvertToHelper<int>(vect[0]);
                            }
                            else
                            {
                                index = ConvertToHelper<int>(args[0]);
                            }
                        }
                        catch (Exception e)
                        {
                            BraidRuntimeException($"index '{args[0]}' for array was invalid: {e.Message}");
                        }

                        if (args.Count == 1)
                        {
                            return list[index];
                        }

                        list[index] = args[1];
                        return list;
                    });

                // Wrap a non-string enumerable in a Function so it can be invoked
                // We don't wrap strings because they name functions instead of being functions.
                case IEnumerable enumerable when (!(enumerable is string)):
                    funcName = "<IEnumerable>";
                    return new Function(funcName, args =>
                    {
                        if (args.Count > 1)
                        {
                            BraidRuntimeException($"IEnumerable as a function requires 1 index argument, {args.Count} were passed.");
                        }

                        if (args.Count == 0)
                        {
                            return enumerable;
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
                            else
                            {
                                index = ConvertToHelper<int>(args[0]);
                            }
                        }
                        catch (Exception e)
                        {
                            BraidRuntimeException($"index '{args[0]}' for IEnumerable was invalid: {e.Message}");
                        }

                        object result = null;
                        foreach (object obj in enumerable)
                        {
                            result = obj;
                            if (index-- <= 0)
                            {
                                break;
                            }
                        }

                        if (index > -1)
                        {
                            BraidRuntimeException(" Index was out of range. Must be non-negative and less than the size of the collection.");
                        }

                        return result;
                    });

                // Wrap a RegEx in a Function so it can be invoked
                case Regex regex:
                    // Handle
                    //      #"a" "abcabc" "A"
                    // or 
                    //      "hello bob" | #"bob" "Bill"
                    funcName = "#\"" + regex + "\"";
                    return new Function(funcName, args =>
                    {
                        if (args.Count < 1 || args.Count > 3)
                        {
                            BraidRuntimeException($"regex as a function requires 1 to 3 non-null arguments, {args.Count} were passed. " +
                                               "ex. (#\"regex\" [words...] (fn l -> function body...)).");
                        }

                        if (args[0] == null)
                        {
                            return null;
                        }

                        Vector callableArgs = null;
                        Callable callable = null;
                        string repstr = null;
                        if (args.Count > 1)
                        {
                            callable = args[1] as Callable;

                            if (callable == null)
                            {
                                repstr = args[1] == null ? string.Empty : args[1].ToString();
                            }
                            else
                            {
                                callableArgs = new Vector { null };
                            }
                        }

                        Vector result = new Vector();
                        Vector matchArray = new Vector();
                        Match matchResult = null;
                        if (!(args[0] is string) && args[0] is IEnumerable)
                        {
                            foreach (var item in Braid.GetNonGenericEnumerableFrom(args[0]))
                            {
                                string sitem;
                                if (item == null)
                                {
                                    sitem = string.Empty;
                                }
                                else
                                {
                                    sitem = item.ToString();
                                }

                                if (repstr != null)
                                {
                                    result.Add(regex.Replace(sitem, repstr));
                                }
                                else
                                {
                                    matchResult = regex.Match(sitem);
                                    if (matchResult.Success)
                                    {
                                        if (callable != null)
                                        {
                                            matchArray = new Vector(matchResult.Groups);
                                            callStack.SetLocal(Symbol.sym_matches, matchArray);
                                            callableArgs[0] = sitem;
                                            var cresult = callable.Invoke(callableArgs);
                                            if (cresult != null)
                                            {
                                                result.Add(cresult);
                                            }
                                        }
                                        else
                                        {
                                            result.Add(sitem);
                                        }
                                    }
                                }
                            }

                            if (matchResult != null && matchResult.Success)
                            {
                                matchArray = new Vector(matchResult.Groups);
                                callStack.SetLocal(Symbol.sym_matches, matchArray);
                            }
                            else
                            {
                                callStack.SetLocal(Symbol.sym_matches, null);
                            }

                            return result;
                        }
                        else
                        {
                            string item;
                            if (args[0] == null)
                            {
                                item = string.Empty;
                            }
                            else
                            {
                                item = args[0].ToString();
                            }

                            if (repstr != null)
                            {
                                return regex.Replace(item, repstr);
                            }
                            else
                            {
                                matchResult = regex.Match(item);
                                if (matchResult.Success)
                                {
                                    matchArray = new Vector(matchResult.Groups);
                                    callStack.SetLocal(Symbol.sym_matches, matchArray);

                                    if (callable != null)
                                    {
                                        callableArgs[0] = item;
                                        return callable.Invoke(callableArgs);
                                    }
                                    else
                                    {
                                        return item;
                                    }
                                }
                                else
                                {
                                    callStack.SetLocal(Symbol.sym_matches, new Vector());
                                    return null;
                                }
                            }
                        }
                    });

                case CommandInfo ci:
                    ftype = FunctionType.Function;
                    funcName = ci.Name;
                    return ci;

                case ScriptBlock sb:
                    funcName = sb.ToString();
                    return sb;
            }

            if (funcName == null || gotFuncFromSymbol || noExternals)
            {
                funcName = "*unknown*";
                return null;
            }

            //
            // There wasn't a function so see if there is a script file with
            // the expected name in the current directory. If there is, then read the file
            // parse it into an s_Expr and return it. Note - there is no caching - the script is interpreted
            // each time.
            //BUGBUGBUG - only looks in the current directory. It should use the path to find scripts.
            //
            string oldFile = _current_file;
            try
            {
                foreach (string path in new string[] { System.Environment.CurrentDirectory, BraidHome })
                {
                    string scriptName = funcName;
                    if (scriptName.LastIndexOf(".tl") == -1)
                    {
                        scriptName += ".tl";
                    }

                    scriptName = Path.Combine(path, scriptName);

                    _current_file = scriptName;
                    if (File.Exists(scriptName))
                    {
                        if (Braid.Debugger != 0)
                        {
                            if ((Braid.Debugger & DebugFlags.Trace) != 0 && (Braid.Debugger & DebugFlags.TraceException) == 0)
                            {
                                Console.WriteLine("ENTERING SCRIPT: '{0}'.", scriptName);
                            }
                        }

                        string script = File.ReadAllText(scriptName);
                        Braid._current_function = Path.GetFileName(scriptName);
                        Braid._current_file = scriptName;
                        s_Expr parsedScript = Parse(script);
                        if (parsedScript == null)
                        {
                            // BUGBUGBUG - this should be an error?
                            return null;
                        }

                        VectorLiteral scriptArgs = null;
                        s_Expr scriptBody = null;
                        if (parsedScript.IsLambda == false)
                        {
                            scriptBody = (s_Expr)parsedScript;
                            scriptArgs = new VectorLiteral(null, -1);
                        }
                        else
                        {
                            parsedScript = (s_Expr)parsedScript.Cdr;
                            scriptArgs = (VectorLiteral)parsedScript.Car;
                            scriptBody = (s_Expr)parsedScript.Cdr;
                        }

                        Vector argsAndBody = new Vector();
                        argsAndBody.Add(scriptArgs);
                        argsAndBody.AddRange(scriptBody);

                        var scriptLambda = parseFunctionBody(new UserFunction(funcName), funcName, argsAndBody, 0);
                        scriptLambda.File = scriptName;
                        scriptLambda.Function = funcName;
                        scriptLambda.Name = funcName;
                        scriptLambda.Environment = new PSStackFrame(scriptName, funcName, callStack.Caller != null ? callStack.Caller : scriptLambda, callStack);

                        return scriptLambda;
                    }
                }
            }
            catch (System.ArgumentException)
            {
                // This is thrown if the function name has invalid characters like '->>'.
                // We just ignore it an move on.
            }
            catch (System.IO.FileNotFoundException)
            {
                // Ignore this and fall through to PowerShell
            }
            finally
            {
                _current_file = oldFile;
            }

            //
            // There wasn't a script so see if there is a JSON file with
            // the expected name in the current directory.
            //BUGBUGBUG - should use the path to find JSON files too? Or have a JSONPATH variable?
            //BUGBUGBUG - this should be removed - direct execution of JSON is bad - it's only supposed to contain data but it could contain code.
            //
            try
            {
                string scriptName = funcName;
                if (scriptName.LastIndexOf(".json") == -1)
                {
                    scriptName += ".json";
                }

                if (File.Exists(scriptName))
                {
                    string script = File.ReadAllText(scriptName);
                    s_Expr parsedScript = Parse(script);
                    if (parsedScript == null)
                    {
                        return null;
                    }

                    if (parsedScript.IsLambda == false)
                    {
                        var newPS = new s_Expr(Symbol.sym_lambda, new s_Expr(null, parsedScript));
                        newPS.File = parsedScript.File;
                        newPS.LineNo = parsedScript.LineNo;
                        parsedScript = newPS;
                    }

                    parsedScript.Environment = new PSStackFrame(scriptName, scriptName, parsedScript, callStack);
                    parsedScript.Function = scriptName;

                    return Eval(parsedScript);
                }
            }
            catch (System.ArgumentException)
            {
                // This is thrown if the function name has invalid characters like '->>'.
                // We just ignore it an move on.
            }
            catch (System.IO.FileNotFoundException)
            {
                // Ignore this and fall through to PowerShell
            }
            finally
            {
                _current_file = oldFile;
            }

            // Finally try PowerShell commands
            CommandInfo cmdinfo = GetPowershellCommand(funcSymbol, true);

            // No command was found so call HandleUnboundSymbol() to see if it
            // wasn't found because of a typo. Only loaded functions and scripts
            // are checked because getting a list of all of the cmdlets would take
            // too long.
            if (cmdinfo == null && lookup)
            {
                funcSymbol = Utils.HandleUnboundSymbol(callStack, funcSymbol);
                if (funcSymbol != null)
                {
                    return GetFunc(callStack, funcSymbol, out ftype, out funcName, false);
                }
            }

            return cmdinfo;
        }

        public static object GetFunc(PSStackFrame callStack, object funcToGet)
        {
            FunctionType ftype;
            string funcName;

            var result = GetFunc(callStack, funcToGet, out ftype, out funcName);
            return result;
        }

        public static object GetFunc(PSStackFrame callStack, object funcToGet, bool noExternals)
        {
            FunctionType ftype;
            string funcName;

            var result = GetFunc(callStack, funcToGet, out ftype, out funcName, noExternals);
            return result;
        }

        /////////////////////////////////////////////////////////////////////////////////
        /// <summary>
        /// Function to look up PowerShell Command which includes native commands. This
        /// function needs to allocate a runspace so it can call Get-Command.
        /// </summary>
        /// <param name="funcSymbol"></param>
        /// <param name="quiet"></param>
        /// <returns></returns>
        public static CommandInfo GetPowershellCommand(Symbol funcSymbol, bool quiet = false)
        {
            // Short-circuit commands with wildcards...
            if (funcSymbol.Value.Contains("*"))
            {
                return null;
            }

            Runspace allocatedRS = null;
            PowerShell pl = null;

            try
            {
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

                //
                // Now try getting the PowerShell command
                //
                if (_getCommandCommand == null)
                {
                    var ccinfo = pl.AddCommand("Get-Command").AddArgument("Get-Command").Invoke();
                    _getCommandCommand = ccinfo[0].BaseObject as CommandInfo;
                    pl.Commands.Clear();
                }

                pl.AddCommand(_getCommandCommand).AddArgument(funcSymbol.Value);


                int retry = 2;
                Collection<PSObject> result = null;
                while (retry-- > 0)
                {
                    try
                    {
                        result = pl.Invoke();
                        retry = 0;
                    }
                    catch (InvalidOperationException)
                    {
                        System.Threading.Thread.Sleep(300);
                    }
                }

                if (result.Count == 1)
                {
                    return result[0].BaseObject as CommandInfo;
                }

                if (result.Count > 1)
                {
                    //BUGBUGBUG this should never happen,
                    BraidRuntimeException($"Multiple commands matching '{funcSymbol.Value}' were found.");
                }

                if (result.Count == 0 && !quiet)
                {
                    BraidRuntimeException($"No command corresponding to '{funcSymbol.Value}' was found.");
                }

                return null;
            }
            finally
            {
                if (allocatedRS != null)
                    RunspaceManager.Deallocate(allocatedRS);

                if (pl != null)
                    pl.Dispose();
            }
        }
 
        // Cache the Get-Command CommandInfo object for quick access.
        public static CommandInfo _getCommandCommand;

        //////////////////////////////////////////////////////////////////////

        // A recursion counter used to prevent stack overflow, per task instance
        [ThreadStatic]
        internal static int _evalDepth;

        // And set the maximum recursion depth
        public static int MaxDepth = 700;

        // Flag used to tell the Braid evaluator to stop.
        // It's explicitly static and not thread-local to stop all running interpreters.
        public static bool _stop = false;

        // Clear the stop and depth flags.
        public static void ClearRuntimeState()
        {
            _stop = false;
            _evalDepth = 0;
            Debugger = 0;
            CallStack.Caller = null;
        }

        // Enable execution tracing.
        [ThreadStatic]
        public static DebugFlags Debugger;

        [ThreadStatic]
        public static bool TracedException;

        // Used in error messages.
        [ThreadStatic]
        internal static string _current_function = "*global*";

        // NOTE: Needs to be public for loadbraid.ps1
        [ThreadStatic]
        public static string _current_file = "stdin";

        // Holds the currently running pipeline for the main thread.
        // BUGBUGBUG - this is problematic as all threads will set it
        // A concurrent dictionary would be better. The ctrl-c
        // handler would simply stop all of the pipelines in the collection
        static PowerShell _current_pipeline;

        // Utility function used for indenting trace messages.
        public static string spaces(int num, char charToShow = '.')
        {
            StringBuilder sb = new StringBuilder();
            while (num-- > 0)
            {
                sb.Append(charToShow);
            }
            return sb.ToString();
        }
    }


#if !UNIX
    ////////////////////////////////////////////////////////////////////
    /// <summary>
    /// Native methods used by some of the GUI scripts like 'textedit.tl'.
    /// </summary>
    public static class NativeMethods
    {
        public const int WM_SETREDRAW = 0x000B;
        public const int WM_USER = 0x400;
        public const int EM_GETEVENTMASK = (WM_USER + 59);
        public const int EM_SETEVENTMASK = (WM_USER + 69);

        [DllImport("user32", CharSet = CharSet.Ansi, SetLastError = true, ExactSpelling = true)]
        public static extern int LockWindowUpdate(int hWnd);

        [DllImport("user32", CharSet = CharSet.Auto)]
        public extern static IntPtr SendMessage(IntPtr hWnd, UInt32 msg, IntPtr wParam, IntPtr lParam);

        public static IntPtr SuspendRichtextBoxEvents(System.Windows.Forms.RichTextBox rtb)
        {
            // Stop redrawing:
            SendMessage(rtb.Handle, WM_SETREDRAW, IntPtr.Zero, IntPtr.Zero);
            // Stop sending of events:
            return SendMessage(rtb.Handle, EM_GETEVENTMASK, IntPtr.Zero, IntPtr.Zero);
        }

        static IntPtr IntPtrOne = new IntPtr(1);
        public static void ResumeRichtextBoxEvents(System.Windows.Forms.RichTextBox rtb, IntPtr eventMask)
        {
            // turn on events
            SendMessage(rtb.Handle, EM_SETEVENTMASK, IntPtr.Zero, eventMask);
            // turn on redrawing
            var intPtr1 = IntPtr.Add(IntPtr.Zero, 1);
            SendMessage(rtb.Handle, WM_SETREDRAW, IntPtrOne, IntPtr.Zero);
        }
    }
#endif
}

