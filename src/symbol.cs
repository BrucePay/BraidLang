/////////////////////////////////////////////////////////////////////////////
//
// The Braid Programming Language - the Symbol type
//
//
// Copyright (c) 2023 Bruce Payette (see LICENCE file) 
//
////////////////////////////////////////////////////////////////////////////

using System;
using System.Linq;
using System.Text.RegularExpressions;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Threading;

namespace BraidLang
{
    /////////////////////////////////////////////////////////////////////////
    /// <summary>
    /// Represents a symbol in Braid. Symbols are interned.
    /// </summary>
    public sealed class Symbol : IEquatable<Symbol>, IComparable
    {
        public string Value { get; private set; }

        public int SymId { get { return _symId; } }
        int _symId;

        // Members used for multiple assignment.
        public List<Symbol> ComponentSymbols;
        public bool CompoundSymbol;
        public bool _bindRestToLast = true;

        static int _nextSymId;

        // Used to intern symbols
        public static ConcurrentDictionary<string, Symbol> _symbolTable =
            new ConcurrentDictionary<string, Symbol>(StringComparer.OrdinalIgnoreCase);

        // Get the symbol corresponding to a string. Create a new symbol if one doesn't exist.
        public static Symbol FromString(string name)
        {
            Symbol symout;

            lock (_lockObj)
            {
                if (_symbolTable.TryGetValue(name, out symout))
                {
                    return symout;
                }

                var sym = new Symbol(name);
                _symbolTable[name] = sym;
                return sym;
            }
        }

        // Generate a new unique symbol
        public static Symbol GenSymbol()
        {
            lock (_lockObj)
            {
                string name = "sym_" + Braid._rnd.Next().ToString();
                var sym = new Symbol(name);
                _symbolTable[name] = sym;
                return sym;
            }
        }

        //
        // Get the symbol corresponding to the specified name.
        // Don't create a symbol if there isn't already one, just
        // return null in that case.
        //
        public static Symbol GetSymbol(string symbolName)
        {
            Symbol symbol;
            if (_symbolTable.TryGetValue(symbolName, out symbol))
            {
                return symbol;
            }
            else
            {
                return null;
            }
        }

        static object _lockObj = new object();

        Symbol(string val)
        {
            if (string.IsNullOrEmpty(val))
            {
                Braid.BraidRuntimeException("Cannot create a symbol with an empty name.");
            }

            this.Value = val;
            if (val.Length > 1 && val.Contains(":"))
            {
                CompoundSymbol = true;
                ComponentSymbols = new List<Symbol>();
                string[] elements = val.Split(':');
                // If the last segment is empty, remove it so patterns
                // like a:b:c: match [1 2 3]
                int numElements = elements.Length;
                if (elements[elements.Length - 1].Length == 0)
                {
                    numElements--;
                    _bindRestToLast = false;
                }

                // Add the names as symbols to the list
                for (var i = 0; i < numElements; i++)
                {
                    ComponentSymbols.Add(Symbol.FromString(elements[i]));
                }
            }

            this._symId = Interlocked.Increment(ref _nextSymId);
        }

        // Implicit conversion from symbol to string/regex and vise versa.
        public static implicit operator string(Symbol s) => s.Value;
        public static implicit operator Symbol(string str) =>
            Symbol.FromString(str);
        public static implicit operator Regex(Symbol s) =>
            new Regex(s.Value,
                RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        public static implicit operator Symbol(Regex re) =>
            Symbol.FromString(re.ToString());

        public override string ToString()
        {
            return Value;
        }

        public override bool Equals(object obj)
        {
            if (obj == null) return false;
            if (obj is Symbol sobj)
            {
                return this._symId == sobj._symId;
            }
            else
            {
                return false;
            }
        }

        public bool Equals(Symbol sym) => this._symId == sym._symId;

        public override int GetHashCode() => _symId;

        public int CompareTo(object obj)
        {
            if (obj is Symbol sym)
            {
                if (this.SymId == sym.SymId)
                    return 0;

                return string.Compare(Value, sym.Value, StringComparison.OrdinalIgnoreCase);
            }
            else
            {
                return -1;
            }
        }

        public static void DumpSymbols()
        {
            Console.WriteLine("Dumping symbols:");
            foreach (var sym in _symbolTable.Values.OrderBy((n) => n.SymId))
            {
                Console.WriteLine($"{sym.SymId,4} '{sym}'");
            }
        }

        ////////////////////////////////////////////////////////////////
        //
        // Pre-defined symbols
        //
        ////////////////////////////////////////////////////////////////

        // These symbols must be first.
        public static Symbol sym_quote = Symbol.FromString("quote");
        public static Symbol sym_lambda = Symbol.FromString("lambda");
        public static Symbol sym_splat = Symbol.FromString("splat");
        public static Symbol sym_quasiquote = Symbol.FromString("quasiquote");
        public static Symbol sym_unquote = Symbol.FromString("unquote");
        public static Symbol sym_unquotesplat = Symbol.FromString("unquotesplat");

        // Remaining predefined symbols...
        public static Symbol sym_nil = Symbol.FromString("nil");
        public static Symbol sym_null = Symbol.FromString("null");
        public static Symbol sym_args = Symbol.FromString("args");
        public static Symbol sym_and_args = Symbol.FromString("&args");
        public static Symbol sym_named_parameters = Symbol.FromString("named-parameters");

        public static Symbol sym_it = Symbol.FromString("it");
        public static Symbol sym_it2 = Symbol.FromString("it2");
        public static Symbol sym_this = Symbol.FromString("this");
        public static Symbol sym_keywords = Symbol.FromString("keywords");
        public static Symbol sym_defn = Symbol.FromString("defn");
        public static Symbol sym_defspecial = Symbol.FromString("defspecial");
        public static Symbol sym_defmacro = Symbol.FromString("defmacro");
        public static Symbol sym_deftype = Symbol.FromString("deftype");
        public static Symbol sym_definterface = Symbol.FromString("definterface");
        public static Symbol sym_defrecord = Symbol.FromString("defrecord");
        public static Symbol sym_dot = Symbol.FromString(".");
        public static Symbol sym_true = Symbol.FromString("true");
        public static Symbol sym_false = Symbol.FromString("false");

        public static Symbol sym_dispatch = Symbol.FromString("dispatch");
        public static Symbol sym_underbar = Symbol.FromString("_");
        public static Symbol sym_pipe = Symbol.FromString("|");
        public static Symbol sym_matches = Symbol.FromString("Matches");
        public static Symbol sym_matchp = Symbol.FromString("matchp");
        public static Symbol sym_let = Symbol.FromString("let");
        public static Symbol sym_local = Symbol.FromString("local");
        public static Symbol sym_argindex_0 = Symbol.FromString("%0");
        public static Symbol sym_recur = Symbol.FromString("recur");
        public static Symbol sym_recur_to = Symbol.FromString("recur-to");
        public static Symbol sym_loop = Symbol.FromString("loop");
        public static Symbol sym_new = Symbol.FromString("new");
        public static Symbol sym_new_dict = Symbol.FromString("new-dict");
        public static Symbol sym_new_vector = Symbol.FromString("new-vector");
        public static Symbol sym_to_vector = Symbol.FromString("to-vector");
        public static Symbol sym_join = Symbol.FromString("join");
        public static Symbol sym_tostring = Symbol.FromString("tostring");
        public static Symbol sym_compareto = Symbol.FromString("compareto");
        public static Symbol sym_gethashcode = Symbol.FromString("gethashcode");
        public static Symbol sym_equals = Symbol.FromString("Equals");
        public static Symbol sym_mod = Symbol.FromString("%");
        public static Symbol sym_add = Symbol.FromString("+");
        public static Symbol sym_subtract = Symbol.FromString("-");
        public static Symbol sym_multiply = Symbol.FromString("*");
        public static Symbol sym_divide = Symbol.FromString("/");
        public static Symbol sym_gt = Symbol.FromString(">");
        public static Symbol sym_ge = Symbol.FromString(">=");
        public static Symbol sym_lt = Symbol.FromString("<");
        public static Symbol sym_le = Symbol.FromString("<=");
        public static Symbol sym_prior_task = Symbol.FromString("prior-task");
        public static Symbol sym_task_args = Symbol.FromString("task-args");
        public static Symbol sym_prior_result = Symbol.FromString("prior-result");
        public static Symbol sym_arrow = Symbol.FromString("->");
        public static Symbol sym_leftarrow = Symbol.FromString("<-");
        public static Symbol sym_fail = Symbol.FromString("!");
        public static Symbol sym_smaller = Symbol.FromString("smaller");
        public static Symbol sym_bigger = Symbol.FromString("bigger");
        public static Symbol sym_keyword = Symbol.FromString("where");
    }
}
