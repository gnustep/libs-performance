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
#import	"GSIOThreadPool.h"

@interface	GSIOThread : NSThread
{
  NSTimer	*timer;
  @public
  NSUInteger	count;
}
- (void) exit: (NSTimer*)t;
- (void) run;
- (void) terminate: (NSDate*)when;
@end

@implementation	GSIOThread

/* Force termination of this thread.
 */
- (void) exit: (NSTimer*)t
{
  [NSThread exit];
}

- (id) init
{
  self = [super initWithTarget: self selector: @selector(run) object: nil];
  if (nil != self)
    {
      [self start];
    }
  return self;
}

/* Run the thread's main runloop until terminated.
 */
- (void) run
{
  NSDate		*when = [NSDate distantFuture];
  NSTimeInterval	delay = [when timeIntervalSinceNow];

  timer = [NSTimer scheduledTimerWithTimeInterval: delay
					   target: self
					 selector: @selector(exit:)
					 userInfo: nil
					  repeats: NO];
  [[NSRunLoop currentRunLoop] run];
}

/* End execution of the thread by the specified date.
 */
- (void) terminate: (NSDate*)when
{
  NSTimeInterval	delay = [when timeIntervalSinceNow];

  [timer invalidate];
  if (delay > 0.0)
    {
      timer = [NSTimer scheduledTimerWithTimeInterval: delay
					       target: self
					     selector: @selector(exit:)
					     userInfo: nil
					      repeats: NO];
    }
  else
    {
      timer = nil;
      [self exit: nil];
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

      if (o->count < l)
	{
	  t = o;
	  l = o->count;
	}
    }
  return t;
}

+ (void) initialize
{
  if ([GSIOThreadPool class] == self && nil == shared)
    {
      shared = [self new];
    }
}

+ (GSIOThreadPool*) sharedPool
{
  return shared;
}

- (NSThread*) acquireThread
{
  GSIOThread	*t;

  [poolLock lock];
  t = best(threads);
  if (t->count > 0 && [threads count] < maxThreads)
    {
      t = [GSIOThread new];
      [threads addObject: t];
      [t release];
    }
  t->count++;
  [poolLock unlock];
  return t;
}

- (NSUInteger) countForThread: (NSThread*)aThread
{
  NSUInteger	count = 0;

  [poolLock lock];
  if ([threads indexOfObjectIdenticalTo: aThread] != NSNotFound)
    {
      count = ((GSIOThread*)aThread)->count;
    }
  [poolLock unlock];
  return count;
}

- (void) dealloc
{
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
  [super dealloc];
}

- (id) init
{
  if ((self = [super init]) != nil)
    {
      poolLock = [NSLock new];
      threads = [NSMutableArray new];
    }
  return self;
}

- (NSUInteger) maxThreads
{
  return maxThreads;
}

- (void) setThreads: (NSUInteger)max
{
  [poolLock lock];
  if (max != maxThreads)
    {
      maxThreads = max;
      while ([threads count] > maxThreads)
	{
	}
    }
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
      if (0 == ((GSIOThread*)aThread)->count)
	{
	  [poolLock unlock];
	  [NSException raise: NSInternalInconsistencyException
		      format: @"-unacquireThread: called too many times"];
	}
      ((GSIOThread*)aThread)->count--;
    }
  [poolLock unlock];
}

@end

