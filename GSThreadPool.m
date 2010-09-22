#include "GSLinkedList.h"
#include "GSThreadPool.h"
#include <Foundation/NSLock.h>
#include <Foundation/NSThread.h>

@class	GSThreadPool;

@interface	GSOperation : GSLinkedList
{
  @public
  SEL		sel;
  NSObject	*arg;
}
@end
@implementation	GSOperation
- (void) dealloc
{
  [arg release];
  [super dealloc];
}
@end

@interface	GSThreadLink : GSLinkedList
{
  @public
  GSThreadPool		*pool;	// Not retained
  NSConditionLock	*lock;
  GSOperation		*op;
}
@end
@implementation	GSThreadLink
- (void) dealloc
{
  [lock release];
  [super dealloc];
}

- (id) init
{
  if ((self = [super init]) != nil)
    {
      lock = [[NSConditionLock alloc] initWithCondition: 0];
    }
  return self;
}
@end
;
@interface	GSThreadPool (Internal)
- (void) _any;
- (void) _dead: (GSThreadLink*)link;
- (BOOL) _idle: (GSThreadLink*)link;
- (BOOL) _more: (GSThreadLink*)link;
- (void) _run: (GSThreadLink*)link;
@end


@implementation	GSThreadPool

- (void) dealloc
{
  [poolLock lock];
  while (nil != operations)
    {
      id	link = operations;

      operations = [link remove];
      [link release];
    }
  while (nil != unused)
    {
      id	link = operations;

      unused = [link remove];
      [link release];
    }
  while (nil != idle)
    {
      GSThreadLink	*link = idle;

      idle = [link remove];
      [link->lock lock];
      [link->lock unlockWithCondition: 1];
    }
  while (nil != live)
    {
      GSThreadLink	*link = live;

      live = [link remove];
      link->pool = nil;
    }
  [poolLock unlock];
  [poolLock release];
  [super dealloc];
}

- (BOOL) drain: (NSDate*)before
{
  BOOL	result = [self isEmpty];

  while (NO == result && [before timeIntervalSinceNow] > 0.0)
    {
      [NSThread sleepForTimeInterval: 0.1];
      result = [self isEmpty];
    }
  return result;
}

- (NSUInteger) flush
{
  NSUInteger	counter;

  [poolLock lock];
  counter = operationCount;
  while (nil != operations)
    {
      id	o = operations;

      operations = [o remove];
      operationCount--;
      [o release];
    }
  [poolLock unlock];
  return counter;
}

- (id) init
{
  if ((self = [super init]) != nil)
    {
      poolLock = [NSRecursiveLock new];
      [self setOperations: 100];
      [self setThreads: 2];
    }
  return self;
}

- (BOOL) isEmpty
{
  return (nil == operations) ? YES : NO;
}

- (BOOL) isIdle
{
  return (nil == live) ? YES : NO;
}

- (BOOL) isSuspended
{
  return suspended;
}

- (NSUInteger) maxOperations
{
  return maxOperations;
}

- (NSUInteger) maxThreads
{
  return maxThreads;
}

- (void) resume
{
  [poolLock lock];
  if (YES == suspended)
    {
      suspended = NO;
      /* No longer suspended ... start as many operations as we have idle
       * threads available for.
       */
      [self _any];
    }
  [poolLock unlock];
}

- (void) scheduleSelector: (SEL)aSelector
               onReceiver: (NSObject*)aReceiver
	       withObject: (NSObject*)anArgument
{
  if (0 == aSelector)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"Null selector"];
    }
  if (nil == aReceiver)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"Nil receiver"];
    }
  [poolLock lock];
  if (operationCount < maxOperations && maxThreads > 0)
    {
      GSOperation	*op = unused;

      if (nil == op)
	{
	  op = [GSOperation new];	// Need a new one
	}
      else
	{
	  unused = [op remove];		// Re-use an old one
	  unusedCount--;
	}
      [op setItem: aReceiver];
      op->sel = aSelector;
      op->arg = [anArgument retain];

      if (nil == operations)
	{
	  operations = lastOperation = op;
	}
      else
	{
	  [lastOperation append: op];
	}
      lastOperation = op;
      operationCount++;
      [self _any];
      [poolLock unlock];
    }
  else
    {
      [poolLock unlock];
      [aReceiver performSelector: aSelector withObject: anArgument];
    }
}

- (void) setOperations: (NSUInteger)max
{
  maxOperations = max;
}

- (void) setThreads: (NSUInteger)max
{
  [poolLock lock];
  if (max != maxThreads)
    {
      maxThreads = max;
      if (0 == maxThreads)
	{
	  [poolLock unlock];
	  if (NO == [self drain: [NSDate dateWithTimeIntervalSinceNow: 30.0]])
	    {
	      [self flush];
	    }
	  [poolLock lock];
	}
      while (maxThreads < threadCount && idle != nil)
	{
	  GSThreadLink	*link = idle;

	  /* Remove thread link from the idle list, then start up the
	   * thread using the condition lock ... the thread will see
	   * that it has no operation to work with and will terminate
	   * itsself and release the link.
	   */
	  idle = [idle remove];
	  threadCount--;
	  [link->lock lock];
	  [link->lock unlockWithCondition: 1];
	}
      [self _any];
    }
  [poolLock unlock];
}

- (void) suspend
{
  [poolLock lock];
  suspended = YES;
  [poolLock unlock];
}
@end

@implementation	GSThreadPool (Internal)

/* This method expects the global lock to already be held.
 */
- (void) _any
{
  if (NO == suspended)
    {
      GSOperation	*op;

      while (nil != (op = operations))
	{
	  GSThreadLink	*link = idle;

	  if (nil == link)
	    {
	      if (maxThreads > threadCount)
		{
		  NSThread	*thread;

		  /* Create a new link, add it to the idle list, and start the
		   * thread which will work withn it.
		   */
		  threadCount++;
		  link = [GSThreadLink new];
		  link->pool = self;
		  thread = [[NSThread alloc] initWithTarget: self
						   selector: @selector(_run:)
						     object: link];
		  [link release];	// Retained by thread
		  [link setItem: thread];
		  [thread release];	// Retained by link
		  [idle insert: link];
		  idle = link;
		  [thread start];
		}
	      else
		{
		  break;		// No idle thread to perform operation
		}
	    }
	  operations = [op remove];
	  operationCount--;
	  if (nil == operations)
	    {
	      lastOperation = nil;
	    }
	  idle = [link remove];
	  [live insert: link];
	  live = link;
	  link->op = op;
	  [link->lock lock];
	  [link->lock unlockWithCondition: 1];
	}
    }
}

- (void) _dead: (GSThreadLink*)link
{
  [poolLock lock];
  if (nil == link->next)
    {
      if (link == live)
	{
	  live = [link remove];
	  threadCount--;
	}
      else if (link == idle)
	{
	  idle = [link remove];
	  threadCount--;
	}
      else
	{
	  // Already dead ... don't change threadCount.
	}
    }
  else
    {
      if (link == live) live = [link remove];
      else if (link == idle) idle = [link remove];
      else [link remove];
      threadCount--;
    }
  [poolLock unlock];
}

/* Make the thread link idle ... returns YES on success, NO if the thread
 * should actually terminate instead.
 */
- (BOOL) _idle: (GSThreadLink*)link
{
  BOOL	madeIdle = YES;

  [poolLock lock];
  if (link == live)
    {
      live = [link remove];
    }
  else if (link == idle)
    {
      idle = [link remove];
    }
  else
    {
      [link remove];
    }
  if (threadCount > maxThreads)
    {
      threadCount--;
      madeIdle = NO;		// Made dead instead
    }
  else
    {
      [idle insert: link];
      idle = link;
    }
  [poolLock unlock];
  return madeIdle;
}

/* If there are more operations waiting for work, move the first one from the
 * operations queue into the supplied thread link.<br />
 * In any case, remove the old operation.
 */
- (BOOL) _more: (GSThreadLink*)link
{
  GSOperation	*op = link->op;
  BOOL		more = NO;

  [poolLock lock];
  if (unusedCount < maxOperations)
    {
      if (nil != op->arg)
	{
	  [op->arg release];
	  op->arg = nil;
	}
      [op setItem: nil];
      [unused insert: op];
      unused = op;
      unusedCount++;
    }
  else
    {
      [op release];
    }
  link->op = operations;
  if (nil != link->op)
    {
      operations = [operations remove];
      operationCount--;
      if (nil == operations)
	{
	  lastOperation = nil;
	}
      more = YES;
    }
  [poolLock unlock];
  return more;
}

- (void) _run: (GSThreadLink*)link
{
  NSAutoreleasePool	*arp;

  for (;;)
    {
      GSOperation	*op;

      [link->lock lockWhenCondition: 1];
//NSLog(@"locked");
      op = link->op;
      if (nil == op)
        {
//NSLog(@"nil op");
	  break;
        }
      else
        {
          [link->lock unlockWithCondition: 0];
//NSLog(@"unlock");
	  while (nil != op)
	    {
	      NS_DURING
		{
		  arp = [NSAutoreleasePool new];
		  [op->item performSelector: op->sel withObject: op->arg];
		  [arp release];
		}
	      NS_HANDLER
		{
		  arp = [NSAutoreleasePool new];
		  NSLog(@"[%@-%@] %@",
		    NSStringFromClass([op->item class]),
		    NSStringFromSelector(op->sel),
		    localException);
		  [arp release];
		}
	      NS_ENDHANDLER
	      if (NO == [link->pool _more: link])
		{
//NSLog(@"no more");
		  op = nil;
		}
	      else
		{
//NSLog(@"more");
	          op = link->op;
		}
	    }
	  if (NO == [link->pool _idle: link])		// Make this idle
	    {
//NSLog(@"no idle");
	      break;	// Thread should exit rather than be idle
	    }
	}
    }

  arp = [NSAutoreleasePool new];
  [link->pool _dead: link];
  NSLog(@"Thread for %@ terminated.", self);
  [arp release];
  [NSThread exit];	// Will release 'link'
}

@end

