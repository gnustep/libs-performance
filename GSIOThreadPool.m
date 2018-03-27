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
static NSRecursiveLock   *classLock = nil;

@interface	GSIOThread (Private)
- (NSUInteger) _count;
- (void) _finish: (NSTimer*)t;
- (void) _setCount: (NSUInteger)c;
@end

@implementation	GSIOThread (Private)

+ (void) initialize
{
  if (nil == classLock)
    {
      classLock = [NSRecursiveLock new];
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
  [self shutdown];
  [NSThread exit];
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

/* Run the thread's main runloop until terminated.
 */
- (void) main
{
  NSAutoreleasePool     *pool = [NSAutoreleasePool new];
  NSDate		*when = [NSDate distantFuture];
  NSTimeInterval	delay = [when timeIntervalSinceNow];

  [self startup];
  _timer = [NSTimer scheduledTimerWithTimeInterval: delay
					    target: self
					  selector: @selector(_finish:)
					  userInfo: nil
					   repeats: NO];
  [[NSRunLoop currentRunLoop] run];
  [pool release];
}

- (void) shutdown
{
  return;
}

- (void) startup
{
  return;
}

/* End execution of the thread by the specified date.
 */
- (void) terminate: (NSDate*)when
{
  if (YES == [self isFinished])
    {
      return;
    }

  if (NO == [when isKindOfClass: [NSDate class]])
    {
      when = [NSDate date];
    }
  [self retain];
  if ([NSThread currentThread] == self)
    {
      NSTimeInterval	delay = [when timeIntervalSinceNow];

      [_timer invalidate];

      [classLock lock];
      if (0 == _count || delay <= 0.0)
        {
          _count = NSNotFound;      // Mark as terminating
          _timer = nil;
          delay = 0.0;
        }
      [classLock unlock];

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
  else if ([self isExecuting])
    {
      NSRunLoop *loop;

      /* We need to execute -terminate: in the thread itself,
       * and wait until either the thread actually finishes or
       * until our time limit expires, whichever comes first.
       */
      [self performSelector: _cmd
                   onThread: self
                 withObject: when
              waitUntilDone: NO];

      loop = [NSRunLoop currentRunLoop];
      while ([self isExecuting] && [when timeIntervalSinceNow] > 0.0)
        {
          NSDate        *d;

          d = [[NSDate alloc] initWithTimeIntervalSinceNow: 0.01];

          NS_DURING
            {
              [loop runUntilDate: d];
            }
          NS_HANDLER
            {
              NSLog(@"Problem waiting for thread termination: %@",
                localException);
            }
          NS_ENDHANDLER
          [d release];
        }
    }
  [self release];
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

      [GSIOThread class];
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

  if (0 == maxThreads)
    {
      return [NSThread mainThread];
    }

  [classLock lock];
  t = best(threads);
  if (nil == t || ((c = [t _count]) > 0 && [threads count] < maxThreads))
    {
      t = [threadClass new];
      [threads addObject: t];
      [t release];
      [t start];
      c = 0;
    }
  [t _setCount: c + 1];
  [classLock unlock];
  return t;
}

- (NSUInteger) countForThread: (NSThread*)aThread
{
  NSUInteger	count = 0;

  [classLock lock];
  if ([threads indexOfObjectIdenticalTo: aThread] != NSNotFound)
    {
      count = [((GSIOThread*)aThread) _count];
    }
  [classLock unlock];
  return count;
}

- (void) dealloc
{
#if defined(GNUSTEP) || (MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_4)
  GSIOThread	*thread;
  NSDate	*when = [NSDate dateWithTimeIntervalSinceNow: timeout];

  [classLock lock];
  while ((thread = [threads lastObject]) != nil)
    {
      [thread performSelector: @selector(terminate:)
		     onThread: thread
		   withObject: when
		waitUntilDone: NO];
      [threads removeObjectIdenticalTo: thread];
    }
  [threads release];
  [classLock unlock];
#endif
  [super dealloc];
}

- (id) init
{
#if defined(GNUSTEP) || (MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_4)
  if ((self = [super init]) != nil)
    {
      threads = [NSMutableArray new];
      threadClass = [GSIOThread class];
    }
#else
  [self release];
  NSLog(@"WARNING, your OSX system is too old to use GSIOThreadPool");
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
  maxThreads = max;
}

- (void) setThreadClass: (Class)aClass
{
  if (NO == [aClass isSubclassOfClass: [GSIOThread class]])
    {
      [NSException raise: NSInvalidArgumentException
                  format: @"Thread class must be a subclass of GSIOThread"];
    }
  threadClass = aClass;
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
  [classLock lock];
  if ([threads indexOfObjectIdenticalTo: aThread] != NSNotFound)
    {
      NSUInteger        c;

      c = [((GSIOThread*)aThread) _count];
      if (0 == c)
	{
          [classLock unlock];
	  [NSException raise: NSInternalInconsistencyException
		      format: @"-unacquireThread: called too many times"];
	}
      [((GSIOThread*)aThread) _setCount: --c];
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
  [classLock unlock];
}

@end

