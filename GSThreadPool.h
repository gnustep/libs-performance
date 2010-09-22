#if	!defined(INCLUDED_GSTHREADPOOL)
#define	INCLUDED_GSTHREADPOOL	1
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

@class	GSOperation;
@class	GSThreadLink;
@class	NSLock;

/** This class provides a thread pool for performing methods
 * of objects in parallel in other threads.<br />
 * This is similar to the NSOperationQueue class but is a
 * lightweight alternative designed to operate rather faster
 * though with slightly decreased functionality ... for instance
 * there is no dependency checking supported.
 */
@interface	GSThreadPool : NSObject
{
  NSLock	*poolLock;
  BOOL		shutdown;
  BOOL		suspended;
  NSUInteger	maxThreads;
  NSUInteger	threadCount;
  GSThreadLink	*idle;
  GSThreadLink	*live;
  NSUInteger	maxOperations;
  NSUInteger	operationCount;
  GSOperation	*operations;
  GSOperation	*lastOperation;
  NSUInteger	unusedCount;
  GSOperation	*unused;
}

/** Waits until the pool of operations is empty or until the specified
 * timestamp.  Returns YES if the pool was emptied, NO otherwise.
 */
- (BOOL) drain: (NSDate*)before;

/** Removes all operations which have not yet started, returning a count
 * of the abandoned operations.
 */
- (NSUInteger) flush;

/** Returns YES if no operations are waiting to be performed, NO otherwise.
 */
- (BOOL) isEmpty;

/** Returns YES if NO operations are in progress, NO otherwise.
 */
- (BOOL) isIdle;

/** Returns YES if startup of new operations is suspended, NO otherwise.
 */
- (BOOL) isSuspended;

/** Returns the currently configured maximum number of operations which
 * may be scheduled at any one time.
 */
- (NSUInteger) maxOperations;

/** Returns the currently configured maximum number of threads in the pool.
 */
- (NSUInteger) maxThreads;

/** Reverses the effect of -suspend.
 */
- (void) resume;

/** Adds the object to the queue for which operations should be performed.<br />
 * You may add an object more than once, but that may result in the operation
 * being performed simultaneously in more than one thread.<br />
 * If the pool is configured with zero threads or zero operations,
 * this method will simply perform the operation immediately.
 */
- (void) scheduleSelector: (SEL)aSelector
               onReceiver: (NSObject*)aReceiver
	       withObject: (NSObject*)anArgument;

/** Specify the number of operations which may be waiting.<br />
 * Default is 100.<br />
 * Setting a value of zero ensures that operations are performed
 * immediately rather than being queued.
 */
- (void) setOperations: (NSUInteger)max;

/** Specify the maximum number of threads in the pool (the actual number
 * used may be lower than this value).<br />
 * Default is 2.<br />
 * The pool creates threads on demand up to the specified limit (or a lower
 * limit if dictated by system resources) but will not destroy idle threads
 * unless the limit is subsequently released.<br />
 * Setting a value of zero means that operations are performed in the
 * main thread.  In this case -drain: will be used (with a 30 second limit)
 * followed by -flush to ensure that the queue is emptied before the threads
 * are shut down.
 */
- (void) setThreads: (NSUInteger)max;

/** Turns off startup of new operations.
 */
- (void) suspend;
@end

#endif
