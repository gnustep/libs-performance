#if	!defined(INCLUDED_GSIOTHREADPOOL)
#define	INCLUDED_GSIOTHREADPOOL	1
/**
   Copyright (C) 2010 Free Software Foundation, Inc.

   Written by:  Richard Frith-Macdonald <rfm@gnu.org>
   Date:        September 2010

   This file is part of the Performance Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 3 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111 USA.
   */
#import <Foundation/NSObject.h>
#import <Foundation/NSThread.h>

#if !defined (GNUSTEP) && (MAC_OS_X_VERSION_MAX_ALLOWED<=MAC_OS_X_VERSION_10_4)
typedef unsigned int NSUInteger;
#endif

@class	NSMutableArray;
@class	NSTimer;

/** This is the class for threads in the pool.<br />
 * Each thread runs a runloop and is kept 'alive' waiting for a timer in
 * the far future, but can be terminated earlier using the -terminate:
 * method (which is called when the pool size is changed and the pool
 * wishes to stop an idle thread).<br />
 */
@interface	GSIOThread : NSThread
{
@private
  NSTimer	*_timer;                /** Pool termination timer */
  NSUInteger	_count;                 /** Number of times acquired */ 
}
/** Terminates the thread by the specified date (as soon as possible if
 * the date is nil or is in the past).<br />
 * If called from another thread, this method asks the receiver thread to
 * perform the method, and waits (running the run loop in the calling
 * thread) until either the receiver thread finishes executing or until
 * the timeout date (when) is reached.
 */
- (void) terminate: (NSDate*)when;

/** Called when the thread is shut down (immediately before exit).<br />
 * Does nothing, provided for subclasses to override.
 */
- (void) shutdown;

/** Called when the thread is started up (before the run loop starts).<br />
 * Does nothing, provided for subclasses to override.
 */
- (void) startup;
@end

/** This class provides a thread pool for performing methods which need to
 * make use of a runloop for I/O and/or timers.<br />
 * Operations are performed on these threads using the standard
 * -performSelector:onThread:withObject:waitUntilDone: method ... the
 * pool is simply used to keep track of allocation of threads so that
 * you can share jobs between them.<br />
 * NB. The threading API in OSX 10.4 and earlier is incapable of supporting
 * this functionality ... in that case this class cannot be instantiated
 * and initialised.
 */
@interface	GSIOThreadPool : NSObject
{
  NSMutableArray	*threads;
  NSTimeInterval	timeout;
  NSUInteger		maxThreads;
  Class                 threadClass;
}

/** Returns an instance intended for sharing between sections of code which
 * wish to make use of threading by performing operations in other threads,
 * but which don't mind operations being interleaved with those belonging to
 * other sections of code.<br />
 * Always returns the same instance whenever the method is called.<br />
 * The shared pool is created with an initial size as specified by the
 * GSIOThreadPoolSize user default (zero if there is no such positive
 * integer in the defauilts system), however you can modify that using
 * the -setThreads: method.
 */
+ (GSIOThreadPool*) sharedPool;

/** Selects a thread from the pool to be used for some job.<br />
 * This method selectes the least used thread in the pool (ie the
 * one with the lowest acquire count).<br />
 * If the receiver is configured with a size of zero, the main thread
 * is returned.
 */
- (NSThread*) acquireThread;

/** Returns the acquire count for the specified thread.
 */
- (NSUInteger) countForThread: (NSThread*)aThread;

/** Returns the currently configured maximum number of threads in the pool.
 */
- (NSUInteger) maxThreads;

/* Sets the class to be used to create any new threads in this pool.<br />
 * Must be a subclass of the GSIOThread class.
 */
- (void) setThreadClass: (Class)aClass;

/** Specify the maximum number of threads in the pool (the actual number
 * used may be lower than this value).<br />
 * Default is 0 (no thread pooling in use).<br />
 * The pool creates threads on demand up to the specified limit (or a lower
 * limit if dictated by system resources) but will not destroy idle threads
 * unless the limit is subsequently lowered.<br />
 * Setting a value of zero means that operations are performed in the
 * main thread.
 */
- (void) setThreads: (NSUInteger)max;

/** Specifies the timeout allowed for a thread to close down when the pool
 * is deallocated or has its size decreased.  Any operations in progress in
 * the thread need to close down within this period.
 */
- (void) setTimeout: (NSTimeInterval)t;

/** Returns the current timeout set for the pool.
 */
- (NSTimeInterval) timeout;

/** Releases a thread previously selected from the pool.  This decreases the
 * acquire count for the thread.  If a thread has a zero acquire count, it is
 * a candidatre for termination and removal from the pool if/when the pool
 * has its size changed.
 */
- (void) unacquireThread: (NSThread*)aThread;

@end

#endif
