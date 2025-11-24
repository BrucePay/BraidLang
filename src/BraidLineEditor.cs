//
// getline.cs: A command line editor
//
// Authors:
//   Miguel de Icaza (miguel@novell.com)
//   
// Modifications/bugfixes for PowerShell 3.0 and CLR4 on Windows:
//   Oisin Grehan (oising@gmail.com)
//
// Modifications to support BraidLang
//   Bruce Payette (bgpayette@gmail.com)
//
// Copyright 2008 Novell, Inc.
//
// Dual-licensed under the terms of the MIT X11 license or the
// Apache License 2.0
//

using System;
using System.Collections;
using System.Diagnostics;
using System.Text;
using System.IO;
using System.Threading;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Management.Automation;
using System.Management.Automation.Runspaces;

namespace BraidLang
{
    /// <summary>
    /// 
    /// </summary>
    public class LineEditor
    {
        /// <summary>
        /// 
        /// </summary>
        public class Completion
        {
            public string[] Result;

            public int ReplacementIndex;

            public string Prefix;

            public Completion(string prefix, string[] result, int index)
            {
                Prefix = prefix;
                Result = result;
                ReplacementIndex = index;
            }
        }

        public delegate Completion AutoCompleteHandler(string text, int pos);

        //static StreamWriter log;

        // The text being edited.
        private StringBuilder _text;

        // The text as it is rendered (replaces (char)1 with ^A on display for example).
        private readonly StringBuilder _renderedText;

        // The prompt specified, and the prompt shown to the user.
        private Func<string> _prompt;

        private string _shownPrompt;

        // PowerShell already evaluates the prompt, so we should not but still take it into account
        private bool _shouldShowPrompt;

        // The current cursor position, indexes into "text", for an index
        // into rendered_text, use TextToRenderPos
        private int _cursor;

        // The row where we started displaying data.
        private int _homeRow;

        // The maximum length that has been displayed on the screen
        private int _maxRendered;

        // If we are done editing, this breaks the interactive loop
        private bool _done = false;

        // The thread where the Editing started taking place
        private Thread _editThread;

        // Our object that tracks history
        public History CommandHistory { get { return _history; }}
        private readonly History _history;

        public string HistoryDir
        {
            get
            {
	            return Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            }
        }

        // The contents of the kill buffer (cut/paste in Emacs parlance)
        private string _killBuffer = "";

        // The string being searched for
        private string _search;

        private string _lastSearch;

        // whether we are searching (-1= reverse; 0 = no; 1 = forward)
        private int _searching;

        // The position where we found the match.
        private int _matchAt;

        // Used to implement the Kill semantics (multiple Alt-Ds accumulate)
        private KeyHandler _lastHandler;

        private delegate void KeyHandler();

        private struct Handler
        {
            public readonly ConsoleKeyInfo KeyInfo;

            public readonly KeyHandler KeyHandler;

            public Handler(ConsoleKey key, KeyHandler h)
            {
                this.KeyInfo = new ConsoleKeyInfo((char)0, key, shift: false, alt: false, control: false);
                KeyHandler = h;
            }

            public Handler(char c, KeyHandler h)
            {
                KeyHandler = h;
                // Use the "Zoom" as a flag that we only have a character.
                this.KeyInfo = new ConsoleKeyInfo(c, ConsoleKey.Zoom, shift: false, alt: false, control: false);
            }

            public Handler(ConsoleKeyInfo keyInfo, KeyHandler h)
            {
                this.KeyInfo = keyInfo;
                KeyHandler = h;
            }

            public static Handler Control(char c, KeyHandler h)
            {
                return new Handler((char)(c - 'A' + 1), h);
            }

            public static Handler Alt(char c, ConsoleKey k, KeyHandler h)
            {
                var cki = new ConsoleKeyInfo(c, k, shift: false, alt: true, control: false);
                return new Handler(cki, h);
            }
        }

        /// <summary>
        ///   Invoked when the user requests auto-completion using the tab character
        /// </summary>
        /// <remarks>
        ///    The result is null for no values found, an array with a single
        ///    string, in that case the string should be the text to be inserted
        ///    for example if the word at pos is "T", the result for a completion
        ///    of "ToString" should be "oString", not "ToString".
        ///
        ///    When there are multiple results, the result should be the full
        ///    text
        /// </remarks>
        public /*AutoCompleteHandler*/ Func<string, int, Completion> AutoCompleteEvent;

        private static Handler[] _handlers;

        private string _defaultPrompt;

        // Hook for doing tab completion externally
        public static Func<string, string, string, object> BraidCompleter {get; set;}

        // Hook for editiong history externally
        public static Func<object> HistoryEditor {get; set; }

        public LineEditor(string name)
            : this(name, 1000)
        {
        }

        public LineEditor(string name, int histsize)
        {
            _handlers = new[] {
                                  new Handler(ConsoleKey.Home, CmdHome),
                                  new Handler(ConsoleKey.End, CmdEnd),
                                  new Handler(ConsoleKey.LeftArrow, CmdLeft),
                                  new Handler(ConsoleKey.RightArrow, CmdRight),
                                  new Handler(ConsoleKey.UpArrow, CmdHistoryPrev),
                                  new Handler(ConsoleKey.DownArrow, CmdHistoryNext),
                                  new Handler(ConsoleKey.Enter, CmdDone),
                                  new Handler(ConsoleKey.Backspace, CmdBackspace),
                                  new Handler(ConsoleKey.Delete, CmdDeleteChar),
                                  new Handler(ConsoleKey.Tab, CmdTabOrComplete),
                                  new Handler(ConsoleKey.Escape, CmdClearBuffer),
                                  new Handler(new ConsoleKeyInfo('\0', ConsoleKey.LeftArrow, false, false, true), CmdBackwardWord),
                                  new Handler(new ConsoleKeyInfo('\0', ConsoleKey.RightArrow, false, false, true), CmdForwardWord),
                                  new Handler(new ConsoleKeyInfo('\0', ConsoleKey.LeftArrow, true, false, false), CmdBackwardWord),
                                  new Handler(new ConsoleKeyInfo('\0', ConsoleKey.RightArrow, true, false, false), CmdForwardWord),

                                  // Emacs keys
                                  Handler.Control('A', CmdHome),
                                  Handler.Control('B', CmdLeft),
                                  // Handler.Control('F', CmdRight),
                                  Handler.Control('P', CmdHistoryPrev),
                                  Handler.Control('N', CmdHistoryNext),
                                  Handler.Control('K', CmdKillToEOF),
                                  Handler.Alt('K', ConsoleKey.K, CmdClearBuffer),
                                  Handler.Control('B', MatchParen),
                                  Handler.Alt('B', ConsoleKey.B, MatchParen),
                                  Handler.Control('Y', CmdYank),

                                  // Edit the current line in vi
                                  Handler.Control('\\', CmdVisualEdit),
                                  
                                  // Select history entry to invoke
                                  Handler.Control('H', CmdHistoryEdit),

                                  Handler.Control('D', CmdDeleteChar),
                                  Handler.Control('L', CmdRefresh),
                                  Handler.Control('R', CmdReverseSearch),
                                  Handler.Alt('/', ConsoleKey.Oem2, CmdReverseSearch),

                                  // Don't beep.
                                  Handler.Control('G', delegate { }),

                                  Handler.Alt('V', ConsoleKey.V, CmdVisualEdit),

                                  // Handler.Alt('H', ConsoleKey.H, CmdHome),
                                  Handler.Alt('H', ConsoleKey.H, CmdHistoryEdit),

                                  Handler.Alt('M', ConsoleKey.M, CmdMiddle),
                                  Handler.Alt('E', ConsoleKey.E, CmdEnd),
                                  // Handler.Alt('B', ConsoleKey.B, CmdBackwardWord),
                                  Handler.Alt('G', ConsoleKey.G, CmdBackwardWord),
                                  Handler.Alt('F', ConsoleKey.F, CmdForwardWord),
                                  Handler.Alt('D', ConsoleKey.D, CmdDeleteWord),
                                  Handler.Alt('0', ConsoleKey.D0, CmdHome),
                                  Handler.Alt('3', ConsoleKey.D3, CmdMiddleLeft),
                                  Handler.Alt('5', ConsoleKey.D5, CmdMiddle),
                                  Handler.Alt('7', ConsoleKey.D7, CmdMiddleRight),
                                  Handler.Alt('9', ConsoleKey.D9, CmdEnd),
                                  Handler.Alt('A', ConsoleKey.A, CmdEnd),
                                  Handler.Alt('/', ConsoleKey.Divide, CmdReverseSearch),
                                  Handler.Alt((char)8, ConsoleKey.Backspace, CmdDeleteBackword),
                                  // DEBUG
                                  //Handler.Control ('T', CmdDebug),

                                  // quote a character
                                  Handler.Control('Q', () => this.HandleChar(Console.ReadKey(true).KeyChar))
                              };

            //-----------------------------------
            // The auto-completion callback
            this.AutoCompleteEvent += (input, position) =>
            {
                int beginning = position;
                string inputString = (string)input;
                string[] results = new string[] { };

                string prefix = null;
                
                int lastc = (beginning >= input.Length) ? input.Length - 1 : beginning;

                // Search backwards for the start of the token as indicated by a space or '('
                while (lastc >= 0 && (input[lastc] != '(' && !char.IsWhiteSpace(input[lastc])))
                {
                    lastc--;
                }

                beginning = lastc < 0 ? 0 : lastc;

                if (beginning < position)
                {
                    // Skip initial space
                    if (char.IsWhiteSpace(input[beginning]))
                    {
                        ++beginning;
                    }

                    prefix = inputString.Substring(beginning, position - beginning);

                    // Set up for tab completion
                    List<string> matches = new List<string>();
                    var candidates = new List<string>();

                    if (BraidCompleter != null)
                    {
                        try
                        {
                            string before;
                            // Move to the previous token
                            int before_end = beginning == 0 ? 0 : beginning - 1;
                            if (before_end != 0)
                            {
                                while (before_end > 0 && input[before_end] == ' ')
                                    before_end--;
                                int before_start = before_end;
                                while (before_start > 0 && input[before_start] != ' ')
                                {
                                    before_start--;
                                }
                                if (input[before_start] == ' ')
                                    before_start++;
                                before = input.Substring(before_start, before_end - before_start + 1);
                            }
                            else
                            {
                                before = "";
                            }

                            string after;
                            if (input.Length == position)
                            {
                                after = "";
                            }
                            else
                            {
                                after = input.Substring(position);
                            }
                            // BUGBUGBUG Console.WriteLine($"\nbefore '{before}' prefix '{prefix}' after '{after}'\n");
                            object result = BraidCompleter.Invoke(before, prefix, after);
                            if (result is PSObject pso)
                            {
                                result = pso.BaseObject;
                            }

                            if (result != null)
                            {
                                if (result is string)
                                {
                                    candidates.Add((string)result);
                                }
                                else if (result is IEnumerable ienum)
                                {
                                    foreach (var e in ienum)
                                    {
                                        candidates.Add(e.ToString());
                                    }
                                }
                                else
                                {
                                    candidates.Add(result.ToString());
                                }
                            }
                        }
                        catch (Exception)
                        {
                            // Ignore errors (makes it hard to debug)
                        }
                    }

                    candidates = candidates.Distinct().ToList();
                    // BUGBUGBUG candidates.Sort();
                    foreach (var k in candidates)
                    {
                        // Console.WriteLine("checking candidates '{0}'", k); // BUGBUGBUG
                        if (k.Length >= prefix.Length)
                        // && string.Equals(prefix, k.Substring(0, prefix.Length), StringComparison.OrdinalIgnoreCase))
                        {
                            if (prefix.Length > 0 && k[0] == '\'' && prefix[0] != '\'')
                            {
                                matches.Add(k.Substring(prefix.Length+1));
                            }
                            else
                            {
                                matches.Add(k.Substring(prefix.Length));
                            }
                        }
                    }
                    results = matches.ToArray();
                }

                return new LineEditor.Completion(prefix, results, position);
            };

            this._renderedText = new StringBuilder();
            this._text = new StringBuilder();

            this._history = new History(name, histsize);
        }

        public static string PromptForChoice(string promptmsg, string[] matches)
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

        private void Render()
        {
            if (_shouldShowPrompt)
            {
                var oldColor = Console.ForegroundColor;
                try
                {
                    //BUGBUG consolidate with old prompt function

                    Console.ForegroundColor = ConsoleColor.Green;
                    Console.Write(this._shownPrompt);
                }
                finally
                {
                    Console.ForegroundColor = oldColor;
                }
            }

            Console.Write(this._renderedText);

            int max = Math.Max(this._renderedText.Length + this._shownPrompt.Length, this._maxRendered);

            for (int i = this._renderedText.Length + this._shownPrompt.Length; i < this._maxRendered; i++)
            {
                Console.Write(' ');
            }
            this._maxRendered = this._shownPrompt.Length + this._renderedText.Length;

            // Write one more to ensure that we always wrap around properly if we are at the
            // end of a line.
            Console.Write(' ');

            UpdateHomeRow(max);
        }

        private void UpdateHomeRow(int screenpos)
        {
            //int lines = 1 + (screenpos / 120);
            //BUGBUG
            int conwidth = Console.WindowWidth;
            int lines = 1 + (screenpos / conwidth);

            this._homeRow = Console.CursorTop - (lines - 1);
            if (this._homeRow < 0) this._homeRow = 0;
        }

        private void RenderFrom(int pos)
        {
            int rpos = TextToRenderPos(pos);
            int i;

            for (i = rpos; i < this._renderedText.Length; i++)
            {
                Console.Write(this._renderedText[i]);
            }

            int maxExtra = this._maxRendered - this._shownPrompt.Length;
            
            if ((this._shownPrompt.Length + this._renderedText.Length) > this._maxRendered)
            {
                this._maxRendered = this._shownPrompt.Length + this._renderedText.Length;
            }
            else
            {
                for (; i < maxExtra; i++) Console.Write(' ');
            }
        }

        private void ComputeRendered()
        {
            this._renderedText.Length = 0;

            for (int i = 0; i < this._text.Length; i++)
            {
                int c = (int)this._text[i];
                if (c < 26)
                {
                    if (c == '\t')
                    {
                        this._renderedText.Append("    ");
                    }
                    else
                    {
                        this._renderedText.Append('^');
                        this._renderedText.Append((char)(c + (int)'A' - 1));
                    }
                }
                else this._renderedText.Append((char)c);
            }
        }

        private int TextToRenderPos(int pos)
        {
            int p = 0;

            for (int i = 0; i < pos; i++)
            {
                int c = (int)this._text[i];

                if (c < 26)
                {
                    if (c == 9) p += 4;
                    else p += 2;
                }
                else p++;
            }

            return p;
        }

        private int TextToScreenPos(int pos)
        {
            return this._shownPrompt.Length + TextToRenderPos(pos);
        }

        private string GetPromptSafe()
        {
            string promptText = _defaultPrompt;
            try
            {
                promptText = _prompt();
            }
            catch (Exception ex)
            {
                // swallow prompt delegate errors
                Trace.WriteLine("GetPromptSafe error: " + ex);
            }

            return promptText;
        }

        private int LineCount
        {
            get
            {
                return (this._shownPrompt.Length + this._renderedText.Length) / Console.WindowWidth;
            }
        }

        private void ForceCursor(int newpos)
        {
            this._cursor = newpos;

            int actualPos = this._shownPrompt.Length + TextToRenderPos(this._cursor);
            //int row = this._homeRow + (actualPos / 120);
            //int col = actualPos % 120;
            var conwidth = Console.WindowWidth;
            int row = this._homeRow + (actualPos / conwidth);
            int col = actualPos % conwidth;

            if (row >= Console.BufferHeight) row = Console.BufferHeight - 1;
            Console.SetCursorPosition(col, row);

            //log.WriteLine ("Going to cursor={0} row={1} col={2} actual={3} prompt={4} ttr={5} old={6}", newpos, row, col, actual_pos, prompt.Length, TextToRenderPos (cursor), cursor);
            //log.Flush ();
        }

        private void UpdateCursor(int newpos)
        {
            if (this._cursor == newpos)
            {
                return;
            }

            ForceCursor(newpos);
        }

        private void InsertChar(char c)
        {
            int prevLines = LineCount;
            this._text = this._text.Insert(this._cursor, c);
            ComputeRendered();
            if (prevLines != LineCount)
            {
                Console.SetCursorPosition(0, this._homeRow);
                Render();
                ForceCursor(++this._cursor);
            }
            else
            {
                RenderFrom(this._cursor);
                ForceCursor(++this._cursor);
                UpdateHomeRow(TextToScreenPos(this._cursor));
            }
        }

        //
        // Commands
        //
        public void CmdDone()
        {
            this._done = true;
        }

        private void CmdTabOrComplete()
        {
            bool complete = false;

            if (AutoCompleteEvent != null)
            {
                if (TabAtStartCompletes)
                {
                    complete = true;
                }
                else
                {
                    for (int i = 0; i < this._cursor; i++)
                    {
                        if (!Char.IsWhiteSpace(this._text[i]))
                        {
                            complete = true;
                            break;
                        }
                    }
                }

                if (complete)
                {
                    Completion completion = AutoCompleteEvent(this._text.ToString(), this._cursor);
                    string[] completions = completion.Result;
                    if (completions == null)
                    {
                        return;
                    }

                    int ncompletions = completions.Length;
                    if (ncompletions == 0) return;

                    if (completions.Length == 1)
                    {
                        InsertTextAtCursor(completions[0]);
                    }
                    else
                    {
                        int last = -1;

                        for (int p = 0; p < completions[0].Length; p++)
                        {
                            char c = completions[0][p];

                            for (int i = 1; i < ncompletions; i++)
                            {
                                if (completions[i].Length <= p)
                                {
                                    goto mismatch;
                                }

                                if (completions[i][p] != c)
                                {
                                    goto mismatch;
                                }
                            }
                            last = p;
                        }

                    mismatch:
                        if (last != -1)
                        {
                            // Needed to insert renderafter and cmdkilltoeof to fixup for NT
                            RenderAfter(completion.ReplacementIndex);
                            InsertTextAtCursor(completions[0].Substring(0, last + 1));
                            CmdKillToEOF();
                        }
                        Console.WriteLine();
                        var fg = Console.ForegroundColor;
                        try
                        {
                            Console.ForegroundColor = ConsoleColor.Yellow;
                            foreach (string s in completions)
                            {
                                Console.Write(completion.Prefix);
                                Console.Write(s);
                                Console.Write(' ');
                            }
                        }
                        finally
                        {
                            Console.ForegroundColor = fg;
                        }
                        Console.WriteLine();
                        Render();
                        ForceCursor(this._cursor);
                    }
                }
                else HandleChar('\t');
            }
            else HandleChar('\t');
        }

        private void CmdHome()
        {
            UpdateCursor(0);
        }

        private void CmdMiddle()
        {
            UpdateCursor(this._text.Length/2);
        }

        private void CmdMiddleLeft()
        {
            UpdateCursor(this._text.Length / 4);
        }

        private void CmdMiddleRight()
        {
            UpdateCursor(this._text.Length / 2 + this._text.Length / 4);
        }

        private void CmdEnd()
        {
            UpdateCursor(this._text.Length);
        }

        private void CmdLeft()
        {
            if (this._cursor == 0) return;
            UpdateCursor(this._cursor - 1);
        }

        private void CmdBackwardWord()
        {
            int p = WordBackward(this._cursor);
            if (p == -1) return;
            UpdateCursor(p);
        }

        private void CmdForwardWord()
        {
            int p = WordForward(this._cursor);
            if (p == -1) return;
            UpdateCursor(p);
        }

        private void CmdRight()
        {
            if (this._cursor == this._text.Length) return;
            UpdateCursor(this._cursor + 1);
        }

        private void RenderAfter(int p)
        {
            ForceCursor(p);
            RenderFrom(p);
            ForceCursor(this._cursor);
        }

        private void CmdBackspace()
        {
            if (this._cursor == 0) return;

            this._text.Remove(--this._cursor, 1);
            ComputeRendered();
            RenderAfter(this._cursor);
        }

        private void CmdDeleteChar()
        {
            // If there is no input, this behaves like EOF
            if (this._text.Length == 0)
            {
                this._done = true;
                this._text = null;
                Console.WriteLine();
                return;
            }

            if (this._cursor == this._text.Length) return;
            this._text.Remove(this._cursor, 1);
            ComputeRendered();
            RenderAfter(this._cursor);
        }

        private void MatchParen()
        {
            int p = this._cursor;
            if (p >= this._text.Length) return;

            int i = p;

            if (this._text[p] == ')')
            {
                int count = 1;
                outer:  while (--p >= 0)
                {
                    if (this._text[p] == '"')
                    {
                        while (--p >= 0 && this._text[p] != '"')
                        {
                            if (p >= 0 && this._text[p] == '"')
                            {
                                p--;
                                goto outer;
                            }
                        }
                    }

                    if (p < 0)
                    {
                        break;
                    }

                    if (this._text[p] == '(')
                    {
                        if (--count == 0)
                        {
                            break;
                        }
                    }
                    else if (this._text[p] == ')') {
                        count++;
                    }
                }

                if (count == 0)
                {
                    this._cursor = p;
                    RenderAfter(this._cursor);
                }
            }
            else if (this._text[p] == '(') {
                int count = 1;
                outer: while (++p < this._text.Length) {

                    if (this._text[p] == '"')
                    {
                        while (++p < this._text.Length && this._text[p] != '"')
                        {
                            if (p <=  0 && this._text[p] == '"')
                            {
                                p++;
                                goto outer;
                            }
                        }
                    }

                    if (p >= this._text.Length)
                    {
                        break;
                    }

                    if (this._text[p] == ')') {
                        if (--count == 0) {
                            break;
                        }
                    }
                    else if (this._text[p] == '(') {
                        count++;
                    }
                }

                if (count == 0) {
                    this._cursor = p;
                    RenderAfter(this._cursor);
                }
            }
        }

        private int WordForward(int p)
        {
            if (p >= this._text.Length) return -1;

            int i = p;
            if (Char.IsPunctuation(this._text[p]) || Char.IsWhiteSpace(this._text[p]))
            {
                for (; i < this._text.Length; i++)
                {
                    if (Char.IsLetterOrDigit(this._text[i])) break;
                }
                for (; i < this._text.Length; i++)
                {
                    if (!Char.IsLetterOrDigit(this._text[i])) break;
                }
            }
            else
            {
                for (; i < this._text.Length; i++)
                {
                    if (!Char.IsLetterOrDigit(this._text[i])) break;
                }
            }
            if (i != p) return i;
            return -1;
        }

        private int WordBackward(int p)
        {
            if (p == 0) return -1;

            int i = p - 1;
            if (i == 0) return 0;

            if (Char.IsPunctuation(this._text[i]) || Char.IsSymbol(this._text[i]) || Char.IsWhiteSpace(this._text[i]))
            {
                for (; i >= 0; i--)
                {
                    if (Char.IsLetterOrDigit(this._text[i])) break;
                }

                for (; i >= 0; i--)
                {
                    if (! Char.IsLetterOrDigit(this._text[i])) break;
                }
            }
            else
            {
                for (; i >= 0; i--)
                {
                    if (!Char.IsLetterOrDigit(this._text[i])) break;
                }
            }
            i++;

            if (i != p) return i;

            return -1;
        }

        private void CmdDeleteWord()
        {
            int pos = WordForward(this._cursor);

            if (pos == -1) return;

            string k = this._text.ToString(this._cursor, pos - this._cursor);

            if (this._lastHandler == CmdDeleteWord) this._killBuffer = this._killBuffer + k;
            else this._killBuffer = k;

            this._text.Remove(this._cursor, pos - this._cursor);
            ComputeRendered();
            RenderAfter(this._cursor);
        }

        private void CmdDeleteBackword()
        {
            int pos = WordBackward(this._cursor);
            if (pos == -1) return;

            string k = this._text.ToString(pos, this._cursor - pos);

            if (this._lastHandler == CmdDeleteBackword) this._killBuffer = k + this._killBuffer;
            else this._killBuffer = k;

            this._text.Remove(pos, this._cursor - pos);
            ComputeRendered();
            RenderAfter(pos);
        }

        //
        // Adds the current line to the history if needed
        //
        private void HistoryUpdateLine()
        {
            this._history.Update(this._text.ToString());
        }

        private void CmdHistoryPrev()
        {
            if (!this._history.PreviousAvailable()) return;

            HistoryUpdateLine();
            SetText(this._history.Previous());
        }

        // Edits the current command line in the program specified by the EDITOR environment
        // variable. If EDITOR is not set, then it defaults to 'notepad' on Windows and 'nano'
        // on UNIX systems.
        private void CmdVisualEdit()
        {
            string editor = Environment.GetEnvironmentVariable("EDITOR");
            if (editor == null || editor.Length == 0)
            {
                Console.WriteLine("\n*** 'EDITOR' environment variable is not set, using default editor.");
#if UNIX
                editor = "nano";
#else
                string path = Path.Combine(Environment.GetEnvironmentVariable("SystemRoot"), "System32");
                editor = Path.Combine(path, "notepad.exe");
#endif
            }

            if (File.Exists(editor) == false)
            {
                Console.WriteLine($"\n*** Unable to find editor program '{editor}'; giving up.\n");
                CmdDone();
                return;
            }

            string tempFile = Path.GetTempFileName() + ".tl"; // Add '.tl' so we get syntax highlighting if available.
            File.WriteAllText(tempFile, this._text.ToString());

            var process = new System.Diagnostics.Process();
            process.StartInfo.FileName = editor;
            process.StartInfo.WorkingDirectory = Environment.CurrentDirectory;
            process.StartInfo.Arguments = tempFile;
            // process.StartInfo.CreateNoWindow = true; // Setting this causes the editor to hang on startup
            process.StartInfo.UseShellExecute = false;
            // Console.WriteLine($"*** Starting editor '{editor}' on file '{tempFile}'\n");
            process.Start();
            process.WaitForExit();
            string newText = System.IO.File.ReadAllText(tempFile)
                .Trim('\n').Trim('\r').Replace('\r', ' ');
            System.IO.File.Delete(tempFile);
            SetText(newText);
            CmdDone();
        }

        /// <summary>
        /// Launch the history editor
        /// </summary>
        private void CmdHistoryEdit()
        {
            if (HistoryEditor != null)
            {
                HistoryEditor.Invoke();
            }
        }

        private void CmdHistoryNext()
        {
            if (!this._history.NextAvailable())
            {
                return;
            }

            this._history.Update(this._text.ToString());
            SetText(this._history.Next());
        }

        private void CmdKillToEOF()
        {
            this._killBuffer = this._text.ToString(this._cursor, this._text.Length - this._cursor);
            this._text.Length = this._cursor;
            ComputeRendered();
            RenderAfter(this._cursor);
        }

        private void CmdClearBuffer()
        {
            CmdHome();
            CmdKillToEOF();
        }

        private void CmdYank()
        {
            InsertTextAtCursor(this._killBuffer);
        }

        private void InsertTextAtCursor(string str)
        {
            int prevLines = LineCount;
            this._text.Insert(this._cursor, str);
            ComputeRendered();
            if (prevLines != LineCount)
            {
                Console.SetCursorPosition(0, this._homeRow);
                Render();
                this._cursor += str.Length;
                ForceCursor(this._cursor);
            }
            else
            {
                RenderFrom(this._cursor);
                this._cursor += str.Length;
                ForceCursor(this._cursor);
                UpdateHomeRow(TextToScreenPos(this._cursor));
            }
        }

        private void SetSearchPrompt(string s)
        {
            SetPrompt("Reverse-Search:" + s + "': ");
        }

        private void ReverseSearch()
        {
            int p;

            if (this._cursor == this._text.Length)
            {
                // The cursor is at the end of the string

                p = this._text.ToString().LastIndexOf(this._search, StringComparison.OrdinalIgnoreCase);
                if (p != -1)
                {
                    this._matchAt = p;
                    this._cursor = p;
                    ForceCursor(this._cursor);
                    return;
                }
            }
            else
            {
                // The cursor is somewhere in the middle of the string
                int start = (this._cursor == this._matchAt) ? this._cursor - 1 : this._cursor;
                if (start != -1)
                {
                    p = this._text.ToString().LastIndexOf(this._search, start, StringComparison.OrdinalIgnoreCase);
                    if (p != -1)
                    {
                        this._matchAt = p;
                        this._cursor = p;
                        ForceCursor(this._cursor);
                        return;
                    }
                }
            }

            // Need to search backwards in history
            HistoryUpdateLine();
            string s = this._history.SearchBackward(this._search);
            if (s != null)
            {
                this._matchAt = -1;
                SetText(s);
                ReverseSearch();
            }
        }

        private void CmdReverseSearch()
        {
            if (this._searching == 0)
            {
                this._matchAt = -1;
                this._lastSearch = this._search;
                this._searching = -1;
                this._search = string.Empty;
                SetSearchPrompt(string.Empty);
            }
            else
            {
                if (this._search == "")
                {
                    if (!string.IsNullOrEmpty(this._lastSearch))
                    {
                        this._search = this._lastSearch;
                        SetSearchPrompt(this._search);

                        ReverseSearch();
                    }
                    return;
                }
                ReverseSearch();
            }
        }

        private void SearchAppend(char c)
        {
            this._search = this._search + c;
            SetSearchPrompt(this._search);

            //
            // If the new typed data still matches the current text, stay here
            //
            if (this._cursor < this._text.Length)
            {
                string r = this._text.ToString(this._cursor, this._text.Length - this._cursor);
                if (r.StartsWith(this._search)) return;
            }

            ReverseSearch();
        }

        private void CmdRefresh()
        {
            Console.Clear();
            this._maxRendered = 0;
            Render();
            ForceCursor(this._cursor);
        }

        private void InterruptEdit(object sender, ConsoleCancelEventArgs a)
        {
            // Do not abort our program:
            a.Cancel = true;

            // BUGBUG thread abort is not supported in .Net Core
            // Interrupt the editor
            // this._editThread.Abort();
        }

        private void HandleChar(char c)
        {
            if (this._searching != 0)
            {
                SearchAppend(c);
            }
            else
            {
                if (c == '\"')
                {
                    InsertChar(c);
                    // BUGBUGBUG - this needs to be refined, also it breaks pasting code
                    // InsertChar(c);
                    // CmdLeft();
                }
                else if (c == '(')
                {
                    InsertChar('(');
                    // InsertChar(')');
                    // CmdLeft();
                }
                else if (c == ')')
                {
                    InsertChar(')');
                    CmdLeft();
                    MatchParen();
                    // BUGBUGBUG - replace with with character highlighting instead of moving the cursor.
                    System.Threading.Thread.Sleep(300);
                    MatchParen();
                    CmdRight();
                    // InsertChar(')');
                    // CmdLeft();
                }
                else if (c == '[')
                {
                    InsertChar('[');
                    // InsertChar(']');
                    // CmdLeft();
                }
                else if (c == '{')
                {
                    InsertChar('{');
                    // InsertChar('}');
                    //  CmdLeft();
                }
                else
                {
                    InsertChar(c);
                }
            }
        }

        private void EditLoop()
        {
            ConsoleKeyInfo cki;

            while (!this._done)
            {
                ConsoleModifiers mod;

                cki = Console.ReadKey(true);
                mod = cki.Modifiers;
                if (cki.Key == ConsoleKey.Escape)
                {
                    cki = Console.ReadKey(true);
                    if (cki.Key != ConsoleKey.Escape)
                    {
                        mod = ConsoleModifiers.Alt;
                    }
                }

                bool handled = false;

                foreach (Handler handler in _handlers)
                {
                    ConsoleKeyInfo t = handler.KeyInfo;

                    if (t.Key == cki.Key && t.Modifiers == mod)
                    {
                        handled = true;
                        handler.KeyHandler();
                        this._lastHandler = handler.KeyHandler;
                        break;
                    }
                    if (t.KeyChar == cki.KeyChar && t.Key == ConsoleKey.Zoom)
                    {
                        handled = true;
                        handler.KeyHandler();
                        this._lastHandler = handler.KeyHandler;
                        break;
                    }
                }
                if (handled)
                {
                    if (this._searching != 0)
                    {
                        if (this._lastHandler != CmdReverseSearch)
                        {
                            this._searching = 0;
                            SetPrompt(this.GetPromptSafe());
                        }
                    }
                    continue;
                }

                if (cki.KeyChar != (char)0) HandleChar(cki.KeyChar);
            }
        }

        private void InitText(string initial)
        {
            this._text = new StringBuilder(initial);
            ComputeRendered();
            this._cursor = this._text.Length;
            Render();
            ForceCursor(this._cursor);
        }

        public void SetText(string newtext)
        {
            Console.SetCursorPosition(0, this._homeRow);
            InitText(newtext);
        }

        private void SetPrompt(string newprompt)
        {
            this._shownPrompt = newprompt;
            Console.SetCursorPosition(0, this._homeRow);
            Render();
            ForceCursor(this._cursor);
        }

        /// <summary>
        /// 
        /// </summary>
        /// <param name="promptHandler"></param>
        /// <param name="defaultPrompt"></param>
        /// <param name="shouldShowPrompt"> </param>
        /// <param name="initialText"></param>
        /// <returns></returns>
        public string Edit(Func<string> promptHandler = null, bool shouldShowPrompt = true, Hashtable options = null, string initialText = "", string defaultPrompt = "")
        {
            this._defaultPrompt = defaultPrompt;
            this._editThread = Thread.CurrentThread;
            this._searching = 0;
            Console.CancelKeyPress += InterruptEdit;

            this._done = false;
            this._history.CursorToEnd();
            this._maxRendered = 0;

            this._prompt = promptHandler;
            this._shownPrompt = promptHandler != null ?  GetPromptSafe() : String.Empty;
            this._shouldShowPrompt = shouldShowPrompt;

            InitText(initialText);
            this._history.Append(initialText);

            do
            {
                try
                {
                    EditLoop();
                }
                catch (ThreadAbortException)
                {
                    this._searching = 0;
                    Thread.ResetAbort();
                    Console.WriteLine();
                    SetPrompt(GetPromptSafe());
                    SetText(String.Empty);
                }
            }
            while (!this._done);
            Console.WriteLine();

            Console.CancelKeyPress -= InterruptEdit;

            if (this._text == null)
            {
                this._history.Close();
                return null;
            }

            string result = this._text.ToString();
            if (result != "" && string.Compare(result, LastCommand, StringComparison.OrdinalIgnoreCase) != 0)
            {
                this._history.Accept(result);
                this.LastCommand = result;
            }
            else
            {
                this._history.RemoveLast();
            }

            return result;
        }

        string LastCommand = "";

        public void Close()
        {
            this._history.Close();
        }

        public bool TabAtStartCompletes { get; set; } = true;

        /// <summary>
        /// Emulates the bash-like behavior, where edits done to the
        /// history are recorded
        /// </summary>
        public class History
        {
            private readonly string[] _history;

            private int _head, _tail;

            private int _cursor;

            private int _count;

            private readonly string _histfile;

            public History(string app, int size)
            {
                if (size < 1) throw new ArgumentException("size");

                if (app != null) {
                
					string dir = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
                    if (!Directory.Exists(dir))
                    {
                        try
                        {
                            Directory.CreateDirectory(dir);
                        }
                        catch
                        {
                            app = null;
                        }
                    }
                    if (app != null) this._histfile = Path.Combine(dir, app) + ".history";
                }

                this._history = new string[size];
                this._head = this._tail = this._cursor = 0;

                if (File.Exists(this._histfile))
                {
                    using (StreamReader sr = File.OpenText(this._histfile))
                    {
                        string line;
                        string lastCommand = "";
                        while ((line = sr.ReadLine()) != null)
                        {
                            if (line != "" && string.Compare(line, lastCommand, StringComparison.OrdinalIgnoreCase) != 0)
                            {
                                Append(line);
                                lastCommand = line;
                            }
                        }
                    }
                }
            }

            public void Close()
            {
                if (this._histfile == null) return;

                try
                {
                    using (StreamWriter sw = File.CreateText(this._histfile))
                    {
                        int start = (this._count == this._history.Length) ? this._head : this._tail;
                        for (int i = start; i < start + this._count; i++)
                        {
                            int p = i % this._history.Length;
                            sw.WriteLine(this._history[p]);
                        }
                    }
                }
                catch
                {
                    // ignore
                }
            }

            //
            // Appends a value to the history
            //
            public void Append(string s)
            {
                this._history[this._head] = s;
                this._head = (this._head + 1) % this._history.Length;
                if (this._head == this._tail) this._tail = (this._tail + 1 % this._history.Length);
                if (this._count != this._history.Length) this._count++;
            }

            //
            // Updates the current cursor location with the string,
            // to support editing of history items.   For the current
            // line to participate, an Append must be done before.
            //
            public void Update(string s)
            {
                this._history[this._cursor] = s;
            }

            public void RemoveLast()
            {
                this._head = this._head - 1;
                if (this._head < 0) this._head = this._history.Length - 1;
            }

            public void Accept(string s)
            {
                int t = this._head - 1;
                if (t < 0) t = this._history.Length - 1;

                this._history[t] = s;
            }

            public bool PreviousAvailable()
            {
                //Console.WriteLine ("h={0} t={1} cursor={2}", head, tail, cursor);
                if (this._count == 0 || this._cursor == this._tail) return false;

                return true;
            }

            public bool NextAvailable()
            {
                int next = (this._cursor + 1) % this._history.Length;
                //BUGBUGBUG - NEXT THE DOWNARROW BUG if (this._count == 0 || next >= this._head) return false;
                if (next == this._head) return false;

                return true;
            }

            //
            // Returns: a string with the previous line contents, or
            // null if there is no data in the history to move to.
            //
            public string Previous()
            {
                if (!PreviousAvailable()) return null;

                this._cursor--;
                if (this._cursor < 0) this._cursor = this._history.Length - 1;

                return this._history[this._cursor];
            }

            public string Next()
            {
                if (!NextAvailable()) return null;

                this._cursor = (this._cursor + 1) % this._history.Length;
                return this._history[this._cursor];
            }

            public void CursorToEnd()
            {
                if (this._head == this._tail) return;

                this._cursor = this._head;
            }

            public List<string>  Dump()
            {
                List<string> cmds = new List<string>();
                int index = this._history.Length;
                for (int i = this._cursor+1; i < this._history.Length; i++)
                {
                    cmds.Add(string.Format("{0,3}: {1}", index--, this._history[i]));
                }
                for (int i = 0; i <= this._cursor; i++)
                {
                    cmds.Add(string.Format("{0,3}: {1}", index--, this._history[i]));
                }
                return cmds;
            }

            public string SearchBackward(string term)
            {
                for (int i = 0; i < this._count; i++)
                {
                    int slot = this._cursor - i - 1;
                    if (slot < 0) slot = this._history.Length + slot;
                    if (slot >= this._history.Length) slot = 0;
                    if (this._history[slot] != null && this._history[slot].IndexOf(term, StringComparison.OrdinalIgnoreCase) != -1)
                    {
                        this._cursor = slot;
                        return this._history[slot];
                    }
                }

                return null;
            }

        }
    }
}
