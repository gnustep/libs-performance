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

#import <Foundation/NSArray.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSRunLoop.h>
#import <Foundation/NSThread.h>
#import <Foundation/NSTimer.h>
#import <Foundation/NSException.h>
#import <Foundation/NSUserDefaults.h>
#import	"GSIOThreadPool.h"

/* Protect changes to a thread's counter
 */
static NSLock   *countLock = nil;

@interface	GSIOThread (Private)
- (NSUInteger) _count;
- (void) _finish: (NSTimer*)t;
- (void) _run;
- (void) _setCount: (NSUInteger)c;
@end

@implementation	GSIOThread (Private)

+ (void) initialize
{
  if (nil == countLock)
    {
      countLock = [NSLock new];
    }
}

- (NSUInteger) _count
{
  return _count;
}

/* Force termination of this thread.
 */
- (void) _finish: (NSTimer*)t
{
  _timer = nil;
  [NSThread exit];
}

/* Run the thread's main runloop until terminated.
 */
- (void) _run
{
  NSDate		*when = [NSDate distantFuture];
  NSTimeInterval	delay = [when timeIntervalSinceNow];

  _timer = [NSTimer scheduledTimerWithTimeInterval: delay
					    target: self
					  selector: @selector(_finish:)
					  userInfo: nil
					   repeats: NO];
  [[NSRunLoop currentRunLoop] run];
}

- (void) _setCount: (NSUInteger)c
{
  if (NSNotFound != _count)
    {
      _count = c;
    }
}

@end

@implementation	GSIOThread

#if defined(GNUSTEP) || (MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_4)
- (id) init
{
  self = [super initWithTarget: self selector: @selector(_run) object: nil];
  if (nil != self)
    {
      [self start];
    }
  return self;
}
#endif

/* End execution of the thread by the specified date.
 */
- (void) terminate: (NSDate*)when
{
  NSTimeInterval	delay = 0.0;

  if ([when isKindOfClass: [NSDate class]])
    {
      delay = [when timeIntervalSinceNow];
    }
  [_timer invalidate];

  [countLock lock];
  if (0 == _count || delay <= 0.0)
    {
      _count = NSNotFound;      // Mark as terminating
      _timer = nil;
      delay = 0.0;
    }
  [countLock unlock];

  if (delay > 0.0)
    {
      _timer = [NSTimer scheduledTimerWithTimeInterval: delay
					        target: self
					      selector: @selector(_finish:)
					      userInfo: nil
					       repeats: NO];
    }
  else
    {
      [self _finish: nil];
    }
}
@end


@implementation	GSIOThreadPool

static GSIOThreadPool	*shared = nil;

/* Return the thread with the lowest usage.
 */
static GSIOThread *
best(NSMutableArray *a)
{
  NSUInteger	c = [a count];
  NSUInteger	l = NSNotFound;
  GSIOThread	*t = nil;

  while (c-- > 0)
    {
      GSIOThread	*o = [a objectAtIndex: c];

      if ([o isExecuting])
        {
          NSUInteger    i;

          if ((i = [o _count]) < l)
            {
              t = o;
              l = i;
            }
        }
      else if ([o isCancelled] || [o isFinished])
        {
          [a removeObjectAtIndex: c];
        }
    }
  return t;
}

+ (void) initialize
{
  if ([GSIOThreadPool class] == self && nil == shared)
    {
      NSInteger size;

      size = [[NSUserDefaults standardUserDefaults]
        integerForKey: @"GSIOThreadPoolSize"];
      if (size < 0)
        {
          size = 0;
        }
      shared = [self new];
      [shared setThreads: size];
    }
}

+ (GSIOThreadPool*) sharedPool
{
  return shared;
}

- (NSThread*) acquireThread
{
  GSIOThread	*t;
  NSUInteger    c;

  [poolLock lock];
  if (0 == maxThreads)
    {
      [poolLock unlock];
      return [NSThread mainThread];
    }
  [countLock lock];
  t = best(threads);
  if (nil == t || ((c = [t _count]) > 0 && [threads count] < maxThreads))
    {
      t = [GSIOThread new];
      [threads addObject: t];
      [t release];
      c = 0;
    }
  [t _setCount: c + 1];
  [countLock unlock];
  [poolLock unlock];
  return t;
}

- (NSUInteger) countForThread: (NSThread*)aThread
{
  NSUInteger	count = 0;

  [poolLock lock];
  if ([threads indexOfObjectIdenticalTo: aThread] != NSNotFound)
    {
      count = [((GSIOThread*)aThread) _count];
    }
  [poolLock unlock];
  return count;
}

- (void) dealloc
{
#if defined(GNUSTEP) || (MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_4)
  GSIOThread	*thread;
  NSDate	*when = [NSDate dateWithTimeIntervalSinceNow: timeout];

  [poolLock lock];
  while ((thread = [threads lastObject]) != nil)
    {
      [thread performSelector: @selector(terminate:)
		     onThread: thread
		   withObject: when
		waitUntilDone: NO];
      [threads removeLastObject];
    }
  [threads release];
  [poolLock unlock];
  [poolLock release];
#endif
  [super dealloc];
}

- (id) init
{
#if defined(GNUSTEP) || (MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_4)
  if ((self = [super init]) != nil)
    {
      poolLock = [NSLock new];
      threads = [NSMutableArray new];
    }
#else
  [self release];
  NSLog(@"WARNING, your OSX system is too old to use GSIOthreadPool");
  return nil;
#endif
  return self;
}

- (NSUInteger) maxThreads
{
  return maxThreads;
}

- (void) setThreads: (NSUInteger)max
{
  [poolLock lock];
  maxThreads = max;
  [poolLock unlock];
}

- (void) setTimeout: (NSTimeInterval)t
{
  timeout = t;
}

- (NSTimeInterval) timeout
{
  return timeout;
}

- (void) unacquireThread: (NSThread*)aThread
{
  [poolLock lock];
  if ([threads indexOfObjectIdenticalTo: aThread] != NSNotFound)
    {
      NSUInteger        c;

      [countLock lock];
      c = [((GSIOThread*)aThread) _count];
      if (0 == c)
	{
          [countLock unlock];
	  [poolLock unlock];
	  [NSException raise: NSInternalInconsistencyException
		      format: @"-unacquireThread: called too many times"];
	}
      [((GSIOThread*)aThread) _setCount: --c];
      [countLock unlock];
      if (0 == c && [threads count] > maxThreads)
        {
          [aThread retain];
          [threads removeObjectIdenticalTo: aThread];
          [aThread performSelector: @selector(terminate:)
                          onThread: aThread
                        withObject: [NSDate date]
                     waitUntilDone: NO];
          [aThread release];
        }
    }
  [poolLock unlock];
}

@end

