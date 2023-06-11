/////////////////////////////////////////////////////////////////////////////
//
// The Braid Programming Language - RunSpace management
//
//
// Copyright (c) 2023 Bruce Payette (see LICENCE file) 
//
////////////////////////////////////////////////////////////////////////////

using System.Collections.Concurrent;
using System.Management.Automation.Runspaces;

namespace BraidLang
{

    /////////////////////////////////////////////////////////////////////////////////////////
    //
    // Class that manages PowerShell runspace allocation/deallocation/reuse
    // and reset for multi-threaded operations.
    //
    public static class RunspaceManager
    {
        public static Runspace Allocate()
        {
            Runspace workerRunspace;

            if (!RunspaceQueue.TryDequeue(out workerRunspace))
            {
                var iss = InitialSessionState.CreateDefault2();
                iss.ThreadOptions = PSThreadOptions.UseCurrentThread;
                if (Braid.Host != null)
                {
                    // Use the same object in all runspaces
                    workerRunspace = RunspaceFactory.CreateRunspace(Braid.Host, iss);
                }
                else
                {
                    workerRunspace = RunspaceFactory.CreateRunspace(iss);
                }

                workerRunspace.Open();
            }
            else
            {
                // Restore the runspace variables to their default settings. Note - this
                // doesn't clear out functions or cmdlets. but it does reduce the chance of
                // cross contamination between different executions.
                workerRunspace.ResetRunspaceState();
            }

            return workerRunspace;
        }

        public static void Deallocate(Runspace runspaceToDeallocate)
        {
            Runspace.DefaultRunspace = null;
            RunspaceQueue.Enqueue(runspaceToDeallocate);
            // If it isn't already setup, set up a timer to clean up unused runspaces
            if (RunspaceCleanupTimer == null)
            {
                lock (timerLock)
                {
                    if (RunspaceCleanupTimer == null)
                    {
                        RunspaceCleanupTimer = new System.Timers.Timer();
                        RunspaceCleanupTimer.Elapsed += (x, y) => {
                            // If a runspace was just allocated, skip this cycle in 
                            // case there are more allocations but clear the flag
                            if (_allocatedRunspace)
                            {
                                _allocatedRunspace = false;
                                return;
                            }

                            // Release a runspace
                            if (RunspaceQueue.TryDequeue(out Runspace r))
                            {
                                r.Dispose();
                            }

                            // If the queue is empty, disable the timer
                            // so it doesn't keep running uselessly in the background
                            if (RunspaceQueue.Count == 0)
                            {
                                RunspaceCleanupTimer.Stop();
                            }
                        };

                        // Set the cleanup interval to be 2 second.
                        // The choice of value is arbitrary and not based
                        // on evidence. With experience we may choose to make
                        // a different choice.
                        RunspaceCleanupTimer.Interval = _runspaceCleanupInterval;
                    }
                }
            }

            // A runspace has been added to the queue so start the timer.
            if (RunspaceQueue.Count > 0)
            {
                RunspaceCleanupTimer.Start();
            }
        }

        internal static int RunspaceCleanupInterval
        {
            get { return _runspaceCleanupInterval; }
            set {
                _runspaceCleanupInterval = value;
                if (RunspaceManager.RunspaceCleanupTimer != null)
                {
                    RunspaceManager.RunspaceCleanupTimer.Interval = value * 1000;
                }
            }
        }
        static int _runspaceCleanupInterval = 4;

        static ConcurrentQueue<Runspace> RunspaceQueue = new ConcurrentQueue<Runspace>();
        static System.Timers.Timer RunspaceCleanupTimer = null;
        static object timerLock = new object();
        static bool _allocatedRunspace;
    }
}
