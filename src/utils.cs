/////////////////////////////////////////////////////////////////////////////
//
// The Braid Programming Language - Utility functions for the interpreter
//
////////////////////////////////////////////////////////////////////////////

using System;
using System.Linq;
using System.Numerics;
using System.Collections;
using System.Text;
using System.Text.RegularExpressions;
using System.Collections.Generic;
using System.IO;

namespace BraidLang
{
    /// <summary>
    /// Utility functions for braid.
    /// </summary>
    public static class Utils
    {
        // Used by the following routines for indenting the text being printed.
        public static string textoffset = string.Empty;

        /// <summary>
        /// Returns the source string representation of an object. Strings are
        /// returned with escapes sequences, doubles will always have a decimal point,
        /// dictionaries will be represented as dictionary literals, etc.
        /// </summary>
        /// <param name="obj">The object to stringize</param>
        /// <returns>The source string representation of the object.</returns>
        public static string ToSourceString(object obj)
        {
            if (obj == null)
            {
                return "nil";
            }

            if (Utils.textoffset.Length > 1000)
            {
                Utils.textoffset = string.Empty;
                Braid.BraidRuntimeException($"ToSourceString is too deeply nested; current object is type ^{obj.GetType()}");
            }

            switch (obj)
            {
                case double d:
                    // Added a trailing ".0" to a string with no decimal point so it will reparse as a decimal.
                    string sd = d.ToString();
                    if (!sd.Contains('.'))
                    {
                        sd += ".0";
                    }

                    return sd;

                case Callable cb:
                    if (string.Equals(cb.Name, "lambda", StringComparison.OrdinalIgnoreCase))
                    {
                        // Anonymous function
                        return cb.ToString();
                    }
                    else
                    {
                        // Named function
                        return cb.Name;
                    }

                case IDictionary dict:
                    return ToStringDict(dict);

                case HashSet<object> hs:
                    return ToStringHashSet(hs);

                case Type t:
                    return "^" + t.ToString();

                case TypeLiteral tlit:
                    return "^" + tlit.TypeName;

                case BigInteger bigint:
                    return bigint.ToString() + "i";

                case char c:
                    switch (c)
                    {
                        case ' ': return "\\space";
                        case '\n': return "\\newline";
                        case '\t': return "\\tab";
                        case (char)0x1b: return "\\esc";
                        // BUGBUGBUG - fill in the rest of the char literal escapes (e.g. unicode \uNNNN) and make sure they are consistent.
                        default:
                            return "\\" + c;
                    }

                case KeywordLiteral kwlit:
                    return ":" + kwlit.ToString();

                case BraidTypeBase btb:
                case IInvokeableValue iiv:
                case Slice s:
                case Vector v:
                case NamedParameter np:
                case ArgIndexLiteral ail:
                case s_Expr sexpr:
                case MatchElementBase meb:
                case FunctionLiteral flit:
                    return obj.ToString();

                case DictionaryEntry dentry:
                    return "{" + ToSourceString(dentry.Key) + " " + ToSourceString(dentry.Value) + "}";

                case KeyValuePair<object, object> kvp:
                    return "{" + ToSourceString(kvp.Key) + " " + ToSourceString(kvp.Value) + "}";

                case Symbol sym:
                    return sym.Value;

                default:
                    if (Braid.Numberp(obj))
                    {
                        return obj.ToString();
                    }

                    if (obj is ExpandableStringLiteral esl)
                    {
                        obj = esl.RawStr;
                    }

                    StringBuilder sb = new StringBuilder();
                    if (obj is Regex)
                    {
                        sb.Append("#\"");
                    }
                    else
                    {
                        sb.Append('"');
                    }

                    string str = obj.ToString();
                    foreach (var sc in str)
                    {
                        switch (sc)
                        {
                            case '\t': sb.Append("\\t"); break;   // tab
                            case '\r': sb.Append("\\r"); break;   // carriage return
                            case '\n': sb.Append("\\n"); break;   // new line
                            case '\\': sb.Append(@"\\"); break;   // slash
                            case (char)0x1b: sb.Append("\\e"); break;   //escape
                            case '"': sb.Append("\\\""); break;  // double-quote
                            default: sb.Append(sc); break;
                        }
                    }

                    sb.Append('"');
                    return sb.ToString();
            }
        }

        /// <summary>
        /// Routine to render a dictionary as a string.
        /// </summary>
        /// <param name="dict">The dictionary to render</param>
        /// <returns>The resulting string</returns>
        public static string ToStringDict(IDictionary dict)
        {
            if (dict == null)
            {
                return "nil";
            }

            if (dict.Count == 0)
            {
                return "{}";
            }

            var sb = new StringBuilder();
            sb.Append('{');
            bool first = true;
            textoffset += "  ";
            foreach (DictionaryEntry pair in dict)
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
                    sb.Append(",");
                }

                sb.Append("\n" + textoffset);
                sb.Append(ToSourceString(pair.Key));
                sb.Append(" : ");
                sb.Append(ToSourceString(pair.Value));
            }

            if (textoffset.Length >= 2)
            {
                textoffset = textoffset.Substring(0, textoffset.Length - 2);
            }

            sb.Append("\n" + textoffset + "}");

            return sb.ToString();
        }

        /// <summary>
        /// Routine to render a hashset into a Braid source string representation.
        /// </summary>
        /// <param name="hashset">The hashset to render.</param>
        /// <returns>The hashset in Braid source format.</returns>
        public static string ToStringHashSet(HashSet<object> hashset)
        {
            if (hashset == null)
            {
                return "nil";
            }

            var sb = new StringBuilder();
            sb.Append("#{");
            bool first = true;
            textoffset += "  ";

            foreach (var item in hashset)
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
                    sb.Append(",");
                }

                sb.Append("\n" + textoffset);
                sb.Append(ToSourceString(item));
            }

            if (textoffset.Length >= 2)
            {
                textoffset = textoffset.Substring(0, textoffset.Length - 2);
            }

            sb.Append("\n" + textoffset + "}");

            return sb.ToString();
        }

        /// <summary>
        /// Compute the edit distance between two strings using the Damerau-Levenshtein
        /// algorithm. See: https://en.wikipedia.org/wiki/Damerau%E2%80%93Levenshtein_distance
        /// </summary>
        /// <param name="s">First string to compare</param>
        /// <param name="t">Second string to compare</param>
        /// <returns>The type distance as a number</returns>
        public static int EditDistance(string s, string t)
        {
            var bHeight = s.Length + 1;
            var bWidth = t.Length + 1;

            int[,] arr = new int[bHeight, bWidth];

            for (var h = 0; h < bHeight; h++)
            {
                arr[h, 0] = h;
            }

            for (var w = 0; w < bWidth; w++)
            {
                arr[0, w] = w;
            }

            for (var h = 1; h < bHeight; h++)
            {
                for (var w = 1; w < bWidth; w++)
                {
                    var editCost = (s[h - 1] == t[w - 1]) ? 0 : 1;
                    var insertion = arr[h, w - 1] + 1;
                    var deletion = arr[h - 1, w] + 1;
                    var substitution = arr[h - 1, w - 1] + editCost;

                    int distance = Math.Min(insertion, Math.Min(deletion, substitution));

                    if (h > 1 && w > 1 && (s[h - 1] == t[w - 2]) && (s[h - 2] == t[w - 1]))
                    {
                        distance = Math.Min(distance, arr[h - 2, w - 2] + editCost);
                    }

                    arr[h, w] = distance;
                }
            }

            return arr[bHeight - 1, bWidth - 1];
        }

        /// <summary>
        /// A comparer class using the edit distance to compare strings.
        /// Used by the 'BestMatchFunction' function.
        /// </summary>
        public sealed class DistanceComparer : IComparer
        {
            public int Compare(object obj1, object obj2)
            {
                ValueTuple<int, string> x = (ValueTuple<int, string>)obj1;
                ValueTuple<int, string> y = (ValueTuple<int, string>)obj2;

                if (x.Item1 == y.Item1)
                    return 0;
                if (x.Item1 > y.Item1)
                    return 1;
                return -1;
            }
        }

        /// <summary>
        /// Find the best match for a string against the set of available functions and scripts
        /// using the edit distance function.
        /// </summary>
        /// <param name="partialName"></param>
        /// <returns></returns>
        public static string[] BestMatchFunction(string partialName)
        {
            // var distances = Symbol._symbolTable.Select(p => (EditDistance(p.Key, partialName), p.Value)).ToArray();
            List<string> candidates = new List<string>();

            // Get all of the loaded functions
            candidates.AddRange(Braid.CallStack.GetSnapshot().Vars.Keys.Select(s => s.Value));

            // Get all of the scripts in the current directory if we're not in the BraidHome directory
            if (!string.Equals(System.Environment.CurrentDirectory, Braid.BraidHome, StringComparison.OrdinalIgnoreCase))
            {
                candidates.AddRange(System.IO.Directory.GetFiles(".", "*.tl").Select(f => Path.GetFileName(f)));
            }

            // Get all of the scripts in the BraidHome directory.
            candidates.AddRange(System.IO.Directory.GetFiles(Braid.BraidHome, "*.tl").Select(f => Path.GetFileName(f)));

            // Create an array of tuples with edit distance and name
            var distances = candidates.Select(p => (EditDistance(p, partialName), p)).ToArray();

            // Sort the tuple array by distance descending
            Array.Sort(distances, new DistanceComparer());

            return distances.Select(t => t.Item2).ToArray();
        }

        /// <summary>
        /// Returns an enumerable object that skips the specified number of elements
        /// </summary>
        /// <param name="coll">The collection to operate on</param>
        /// <param name="numToSkip">The number of initial elements to skip.</param>
        /// <returns>The Skip enumerable.</returns>
        public static IEnumerable<object> GetSkipEnumerable(IEnumerable coll, int numToSkip)
        {
            foreach (object obj in coll)
            {
                if (numToSkip > 0)
                {
                    numToSkip--;
                    continue;
                }

                yield return obj;
            }
        }

        /// <summary>
        /// Returns an enumerable object that skips initial elements while the condition function is true.
        /// </summary>
        /// <param name="coll">The collection to operate on</param>
        /// <param name="condition">The skip function</param>
        /// <returns>The Skip enumerable.</returns>
        public static IEnumerable<object> GetSkipWhileEnumerable(IEnumerable coll, Callable condition)
        {
            var argsVec = new Vector();
            argsVec.Add(null);

            bool skipping = true;
            foreach (var e in coll)
            {
                if (skipping)
                {
                    argsVec[0] = e;
                    if (Braid.IsTrue(condition.Invoke(argsVec)))
                    {
                        continue;
                    }
                    else
                    {
                        skipping = false;
                    }
                }

                yield return e;
            }
        }

        /// <summary>
        /// Returns initial elements from a collection until the matching terminal element is encountered,
        /// or, if a function is provided, while the function evaluates to true.
        /// </summary>
        /// <param name="coll">The collection to process</param>
        /// <param name="value">The value or function used to decide when to stop taking elements.</param>
        /// <returns>The matched set of elements.</returns>
        public static IEnumerable<object> TakeWhileEnumerable(IEnumerable coll, object value)
        {
            Vector argVect = new Vector { null };
            if (value is Callable condition)
            {
                foreach (var e in coll)
                {
                    argVect[0] = e;
                    if (Braid.IsTrue(condition.Invoke(argVect)))
                    {
                        break;
                    }

                    yield return e;
                }
            }
            else
            {
                foreach (var e in coll)
                {
                    if (Braid.Equals(e, value))
                    {
                        break;
                    }

                    yield return e;
                }
            }
        }

        public static IEnumerable<object> TakeAfterEnumerable(IEnumerable coll, object value)
        {
            Vector argVect = new Vector { null };
            bool keep = false;

            if (value is Callable condition)
            {
                foreach (var e in coll)
                {
                    if (keep)
                    {
                        yield return e;
                    }
                    else
                    {
                        argVect[0] = e;
                        if (Braid.IsTrue(condition.Invoke(argVect)))
                        {
                            keep = true;
                        }
                    }
                }
            }
            else
            {
                foreach (var e in coll)
                {
                    if (keep)
                    {
                        yield return e;
                    }
                    else
                    {
                        if (Braid.Equals(e, value))
                        {
                            keep = true;
                        }
                    }
                }
            }
        }

        /// <summary>
        /// Dynamically looks up a symbol using the type-distance algorithm and
        /// gives the user the opportunity to continue with the resolved symbol.
        /// </summary>
        /// <param name="sym">The symbol to look up</param>
        /// <returns>The best match that was found or null if nothing was found or the user cancelled the operation.</returns>
        public static Symbol HandleUnboundSymbol(PSStackFrame callStack, Symbol sym)
        {
            if (callStack.IsInteractive == false)
            {
                Braid.BraidRuntimeException($"Unbound symbol '{sym.Value}'.");
            }

            string[] matches = BestMatchFunction(sym.Value);

            string result = BraidPromptForChoice(
                $"\n  Symbol '{sym.Value}' was not found. Choose one of the following options or press 'c' to cancel:\n",
                matches);
            if (result != null)
            {
                var resolvedSym = Symbol.FromString(result);
                if (callStack.GetVariable(resolvedSym) != null || Braid.GetFunc(callStack, resolvedSym) != null)
                {
                    return resolvedSym;
                }
            }

            Braid.BraidRuntimeException($"Unbound symbol '{sym.Value}': a symbol must have a value or function assigned to it before it can be used in an expression.");
            return null;
        }

        /// <summary>
        /// Utility to allow the selection from a choice of alternatives.
        /// </summary>
        /// <param name="promptmsg">The message to display to the user</param>
        /// <param name="matches">The list of candidate strings to display.</param>
        /// <returns></returns>
        private static string BraidPromptForChoice(string promptmsg, string[] matches)
        {
            while (true)
            {
                var oldColor = Console.ForegroundColor;
                Console.ForegroundColor = ConsoleColor.Green;
                Console.WriteLine(promptmsg);
                Console.WriteLine();
                var itemCount = matches.Length;
                if (itemCount > 9)
                {
                    itemCount = 9;
                }

                int length = matches.Take(itemCount).Select(t => t.Length).Max() + 1;

                int itemsPerLine = (Console.BufferWidth / (length + 4)) - 1;

                for (int i = 0; i < itemCount; i++)
                {
                    if (i == itemsPerLine)
                    {
                        Console.WriteLine();
                    }

                    Console.ForegroundColor = ConsoleColor.Green;
                    Console.Write($"[{i + 1}] ");
                    Console.ForegroundColor = oldColor;
                    Console.Write(matches[i].PadRight(length));
                }

                Console.ForegroundColor = ConsoleColor.Green;
                Console.Write("[C] ");
                Console.ForegroundColor = oldColor;
                Console.Write("Cancel : ");

                var key = Console.ReadKey(true);
                Console.WriteLine();

                switch (key.KeyChar)
                {
                    case 'c':
                    case 'C':
                        Console.WriteLine("\nCancelled...\n");
                        return null;

                    default:
                        if (Char.IsDigit(key.KeyChar))
                        {
                            int index = key.KeyChar - '0';
                            if (index > 0 && index < 10)
                            {
                                return matches[index - 1];
                            }
                        }
                        break;
                }
            }
        }
    }
}
