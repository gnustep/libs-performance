#include <inttypes.h>

#import "GSLinkedList.h"
#import "GSThreadPool.h"
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSThread.h>
#import <Foundation/NSString.h>
#import <Foundation/NSException.h>

@class	GSThreadPool;

@interface	GSOperation : GSListLink
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

@interface	GSThreadLink : GSListLink
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

@interface	GSThreadPool (Internal)
- (void) _any;
- (void) _dead: (GSThreadLink*)link;
- (BOOL) _idle: (GSThreadLink*)link;
- (BOOL) _more: (GSThreadLink*)link;
- (void) _run: (GSThreadLink*)link;
@end


@implementation	GSThreadPool

static GSThreadPool	*shared = nil;

+ (void) initialize
{
  if ([GSThreadPool class] == self && nil == shared)
    {
      shared = [self new];
    }
}

+ (GSThreadPool*) sharedPool
{
  return shared;
}

- (void) dealloc
{
  GSThreadLink	*link;

  if (self == shared)
    {
      [self retain];
      [NSException raise: NSInternalInconsistencyException
	format: @"[GSThreadPool-dealloc] attempt to deallocate shared pool"];
    }
  [poolLock lock];
  [operations release];
  operations = nil;
  [unused release];
  unused = nil;
  if (nil != idle)
    {
      while (nil != (link = (GSThreadLink*)idle->head))
	{
	  GSLinkedListRemove(link, idle);
	  [link->lock lock];
	  [link->lock unlockWithCondition: 1];
	}
      [idle release];
      idle = nil;
    }
  if (nil != live)
    {
      while (nil != (link = (GSThreadLink*)live->head))
	{
	  GSLinkedListRemove(link, live);
	  link->pool = nil;
	}
      [live release];
      live = nil;
    }
  [poolName release];
  [poolLock unlock];
  [poolLock release];
  [super dealloc];
}

- (NSString*) description
{
  NSString	*result = [self info];

  [poolLock lock];
  result = [NSString stringWithFormat: @"%@ %@ %@",
    [super description], poolName, result];
  [poolLock unlock];
  return result;
}

- (BOOL) drain: (NSDate*)before
{
  BOOL	result = [self isEmpty];

  while (NO == result && [before timeIntervalSinceNow] > 0.0)
    {
#if !defined (GNUSTEP) && (MAC_OS_X_VERSION_MAX_ALLOWED<=MAC_OS_X_VERSION_10_4)
      NSDate	*when;

      when = [[NSDate alloc] initWithTimeIntervalSinceNow: 0.1];
      [NSThread sleepUntilDate: when];
      [when release];
#else
      [NSThread sleepForTimeInterval: 0.1];
#endif
      result = [self isEmpty];
    }
  return result;
}

- (NSUInteger) flush
{
  NSUInteger	counter;

  [poolLock lock];
  counter = operations->count;
  [operations empty];
  [poolLock unlock];
  return counter;
}

- (id) init
{
  if ((self = [super init]) != nil)
    {
      poolLock = [NSRecursiveLock new];
      poolName = @"GSThreadPool";
      idle = [GSLinkedList new];
      live = [GSLinkedList new];
      operations = [GSLinkedList new];
      unused = [GSLinkedList new];
      [self setOperations: 100];
      [self setThreads: 2];
    }
  return self;
}

- (NSString*) info
{
  NSString	*result;

  [poolLock lock];
  result = [NSString stringWithFormat:
    @"queue: %"PRIuPTR"(%"PRIuPTR")"
    @" threads: %"PRIuPTR"(%"PRIuPTR")"
    @" active: %"PRIuPTR" processed: %"PRIuPTR""
    @" suspended: %s",
    operations->count, maxOperations,
    idle->count + live->count, maxThreads, live->count, processed,
    (suspended ? "yes" : "no")];
  [poolLock unlock];
  return result;
}

- (BOOL) isEmpty
{
  return (0 == operations->count) ? YES : NO;
}

- (BOOL) isIdle
{
  return (0 == live->count) ? YES : NO;
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

- (NSString*) poolName
{
  NSString	*n;

  [poolLock lock];
  n = RETAIN(poolName);
  [poolLock unlock];
  return AUTORELEASE(n);
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
  if (operations->count < maxOperations && maxThreads > 0)
    {
      GSOperation	*op = (GSOperation*)unused->head;

      if (nil == op)
	{
	  op = [GSOperation new];		// Need a new one
	}
      else
	{
	  GSLinkedListRemove(op, unused);	// Re-use an old one
	}
      [op setItem: aReceiver];
      op->sel = aSelector;
      op->arg = [anArgument retain];

      GSLinkedListInsertAfter(op, operations, operations->tail);
      [self _any];
      [poolLock unlock];
    }
  else
    {
      NSAutoreleasePool	*arp;

      [poolLock unlock];

      NS_DURING
	{
	  arp = [NSAutoreleasePool new];
	  [aReceiver performSelector: aSelector withObject: anArgument];
	  [arp release];
	}
      NS_HANDLER
	{
	  arp = [NSAutoreleasePool new];
	  NSLog(@"[%@-%@] %@",
	    NSStringFromClass([aReceiver class]),
	    NSStringFromSelector(aSelector),
	    localException);
	  [arp release];
	}
      NS_ENDHANDLER
    }
}

- (void) setOperations: (NSUInteger)max
{
  maxOperations = max;
}

- (void) setPoolName: (NSString*)aName
{
  NSString	*s = nil;

  if (aName)
    {
      s = AUTORELEASE([aName copy]);
      NSAssert([s isKindOfClass: [NSString class]], NSInvalidArgumentException);
    }
  [poolLock lock];
  ASSIGN(poolName, s);
  [poolLock unlock];
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
      while (maxThreads < idle->count + live->count && idle->count > 0)
	{
	  GSThreadLink	*link = (GSThreadLink*)idle->head;

	  /* Remove thread link from the idle list, then start up the
	   * thread using the condition lock ... the thread will see
	   * that it has no operation to work with and will terminate
	   * itsself and release the link.
	   */
	  GSLinkedListRemove(link, idle);
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

      while (nil != (op = (GSOperation*)operations->head))
	{
	  GSThreadLink	*link = (GSThreadLink*)idle->head;

	  if (nil == link)
	    {
	      if (maxThreads > idle->count + live->count)
		{
		  NSThread	*thread;
		  NSString	*name;

		  /* Create a new link, add it to the idle list, and start the
		   * thread which will work with it.
		   */
		  link = [GSThreadLink new];
		  link->pool = self;
		  GSLinkedListInsertAfter(link, idle, idle->tail);

#if !defined (GNUSTEP) && (MAC_OS_X_VERSION_MAX_ALLOWED<=MAC_OS_X_VERSION_10_4)

		  /* With the old thread API we can't get an NSThread object
		   * until after the thread has started ... so we start the
		   * thread and then wait for the new thread to have set the
		   * link item up properly.
		   */
		  [NSThread detachNewThreadSelector: @selector(_run:)
					   toTarget: self
				         withObject: link];
		  while (nil == link->item)
		    {
		      NSDate	*when;

		      when = [[NSDate alloc]
			initWithTimeIntervalSinceNow: 0.001];
		      [NSThread sleepUntilDate: when];
		      [when release];
		    }
#else
		  /* New thread API ... create thread object, set it in the
		   * link, then start the thread.
		   */
		  thread = [[NSThread alloc] initWithTarget: self
						   selector: @selector(_run:)
						     object: link];
		  if (nil == (name = poolName))
		    {
		      name = @"GSThreadPool";
		    }
		  name = [NSString stringWithFormat: @"%@-%u",
		    name, ++created];
		  [thread setName: name];
		  [link setItem: thread];
		  [thread start];
		  [thread release];	// Retained by link
#endif
		}
	      else
		{
		  break;		// No idle thread to perform operation
		}
	    }
	  GSLinkedListRemove(op, operations);
	  GSLinkedListRemove(link, idle);
	  GSLinkedListInsertAfter(link, live, live->tail);
	  link->op = op;
	  [link->lock lock];
	  [link->lock unlockWithCondition: 1];
	}
    }
}

- (void) _dead: (GSThreadLink*)link
{
  [poolLock lock];
  if (link->owner != nil)
    {
      GSLinkedListRemove(link, link->owner);
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
  if (link->owner != nil) 
    {
      GSLinkedListRemove(link, link->owner);
    }
  if (idle->count + live->count > maxThreads)
    {
      madeIdle = NO;		// Made dead instead
    }
  else
    {
      GSLinkedListInsertAfter(link, idle, idle->tail);
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
  processed++;
  if (unused->count < maxOperations)
    {
      if (nil != op->arg)
	{
	  [op->arg release];
	  op->arg = nil;
	}
      [op setItem: nil];
      GSLinkedListInsertAfter(op, unused, unused->tail);
    }
  else
    {
      [op release];
    }
  link->op = (GSOperation*)operations->head;
  if (nil != link->op)
    {
      GSLinkedListRemove(link->op, operations);
      more = YES;
    }
  [poolLock unlock];
  return more;
}

- (void) _run: (GSThreadLink*)link
{
  NSAutoreleasePool	*arp;

#if !defined (GNUSTEP) && (MAC_OS_X_VERSION_MAX_ALLOWED<=MAC_OS_X_VERSION_10_4)
  /* With the older thread API we must set up the link item *after* the
   * thread starts.  With the new API this is not needed as we can set
   * things up and then start the thread.
   */
  [link setItem: [NSThread currentThread]];
#endif

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

