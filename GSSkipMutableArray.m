/**
   Copyright (C) 2006 Free Software Foundation, Inc.

   Written by:  Matt Rice <ratmice@yahoo.com>
   Date:        2006

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

#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSValue.h>
#import <Foundation/NSEnumerator.h>
#import <Foundation/NSString.h>

#import "GSSkipMutableArray.h"
#import "GSIndexedSkipList.h"

static Class	abstractClass = 0;
static Class	concreteClass = 0;

@interface GSSkipMutableArray : NSMutableArray
@end

@interface GSConcreteSkipArray : GSSkipMutableArray
{
  GSISList l;
}
- (GSISList) _list;
@end

@implementation	NSMutableArray (GSSkipMutableArray)
+ (NSMutableArray*) skipArray
{
  return [GSSkipMutableArray array];
}
@end

@implementation	GSSkipMutableArray
+ (id) allocWithZone: (NSZone*)z
{
  if (self == abstractClass)
    {
      return [concreteClass allocWithZone: z];
    }
  return [super allocWithZone: z];
}

+ (void) initialize
{
  if (abstractClass == 0)
    {
      abstractClass = [GSSkipMutableArray class];
      concreteClass = [GSConcreteSkipArray class];
    }
}

@end


@interface GSConcreteSkipArrayEnumerator : NSEnumerator
{
  GSISLNode node;  
}
@end

@implementation GSConcreteSkipArrayEnumerator
- (id) initWithArray: (NSArray *)arr
{
  if (![arr isKindOfClass: [GSConcreteSkipArray class]])
    {
      [[NSException exceptionWithName: NSInternalInconsistencyException
			       reason: @"not a GSConcreteSkipArray"
			     userInfo: nil] raise];
    }
  self = [super init];
  node = [(GSConcreteSkipArray *)arr _list]->header->forward[0].next;
  return self;
}

- (id) nextObject
{
  id foo = node->value;

  if (node == GSISLNil)
    return nil;
  node = node->forward[0].next;
  return foo;
}
@end

@implementation GSConcreteSkipArray

- (GSISList) _list
{
  return l;
}

- (void) _raiseRangeExceptionWithIndex: (NSUInteger)index from: (SEL)sel
{
  NSDictionary *info;
  NSException  *exception;
  NSString     *reason;

  info = [NSDictionary dictionaryWithObjectsAndKeys:
    [NSNumber numberWithUnsignedInt: index], @"Index",
    [NSNumber numberWithUnsignedInt: l->count], @"Count",
    self, @"Array", nil, nil];

  reason = [NSString stringWithFormat: @"Index %d is out of range %d (in '%@')",    index, l->count, NSStringFromSelector(sel)];

  exception = [NSException exceptionWithName: NSRangeException
                                      reason: reason
                                    userInfo: info];
  [exception raise];
}

+ (void) initialize
{
  GSISLInitialize();
}

- (id) initWithObjects: (id *)objects count: (NSUInteger) count
{
  int i;
  self = [super init];

  if (!self) return nil;
  
  l = GSISLInitList([self zone]);
  
  for (i = 0; i < count; i++)
    {
      GSISLInsertItemAtIndex(l, [objects[i] retain], i);
    }
  
  return self;
}

- (id) init
{
  self = [super init]; 
  
  if (!self) return nil;
  
  l = GSISLInitList([self zone]);
  return self;
}

- (void) dealloc
{
  GSISLNode p,q;

  p = l->header->forward[0].next;
  while (p != GSISLNil)
    {
      q = p->forward[0].next;
      [p->value release];
      NSZoneFree(l->zone,p);
      p = q;
    }
  
  NSZoneFree(l->zone, l->header); 
  NSZoneFree(l->zone, l);
  [super dealloc];
}

- (void) insertObject: (id)object atIndex: (NSUInteger)index
{
  if (index > l->count)
    {
        [self _raiseRangeExceptionWithIndex: index from: _cmd];
    }

  GSISLInsertItemAtIndex(l, [object retain], index);
}

- (id) objectAtIndex: (NSUInteger)index
{
  if (index >= l->count)
    {
      [self _raiseRangeExceptionWithIndex: index from: _cmd];
    }

  return GSISLItemAtIndex(l, index);
}

- (void) removeObjectAtIndex: (NSUInteger)index
{
  if (index >= l->count)
    {
        [self _raiseRangeExceptionWithIndex: index from: _cmd];
    }

  [GSISLRemoveItemAtIndex(l, index) release]; 
}

- (void) addObject: (id)obj
{
  GSISLInsertItemAtIndex(l, [obj retain], l->count);
}

- (NSUInteger) count
{
  return l->count;
}

- (void) replaceObjectAtIndex: (NSUInteger)index withObject: (id)obj
{
  [GSISLReplaceItemAtIndex(l, [obj retain], index) release];
}

- (NSEnumerator*) objectEnumerator
{
  id    e;

  e = [GSConcreteSkipArrayEnumerator
    allocWithZone: NSDefaultMallocZone()];
  e = [e initWithArray: self];
  return [e autorelease];
}

/* returns an in an NSString suitable for running through graphviz,
 * with the graph named 'graphName' 
 */
- (NSString *) _makeGraphOfInternalLayoutNamed: (NSString *)graphName
{
  GSISLNode p;
  NSUInteger k, i;
  NSMutableDictionary *values;
  NSMutableArray *edges;
  NSMutableString *graph;
  NSArray *tmp;
  
  p = l->header;
  k = l->level;

  graph = [[NSMutableString alloc] initWithCapacity: 1024];
  [graph appendString:
    [NSString stringWithFormat: @"digraph %@ {\n", graphName]];
  [graph appendString: @"graph [rankdir = LR];\n"];
  [graph appendString: @"node [shape = record];\n"];
  values = [[NSMutableDictionary alloc] init];
  edges = [[NSMutableArray alloc] init];
  [values setObject:
    [NSMutableString stringWithFormat:
      @"\"%p\" [label = \"%p (NIL) |{ <delta0> 0 | <forward0> }",
      GSISLNil, GSISLNil]
    forKey: [NSString stringWithFormat: @"%p", GSISLNil]];
  for (k = 0; k < l->level + 1; k++)
    {
      for (p = l->header; p != GSISLNil; p = p->forward[k].next)
        {
	  NSString	*value;
	  NSMutableString *foo;
	  
	  value = [NSString stringWithFormat: @"%p", p];
	  foo = [values objectForKey: value];
	  if (foo == nil)
	    {
	      foo = [[NSMutableString alloc] init];
	      [foo appendString:
		[NSString stringWithFormat:
		  @"\"%p\" [label = \"%p%@ |{ <delta%i> %i | <forward%i> }",
		  p, p, p == l->header ? @"(HEADER)" : @"", k,
		  p->forward[k].delta, k]];
	      if (p != GSISLNil)
	        [edges addObject:
		  [NSString stringWithFormat:
		    @"\"%p\": forward%i -> \"%p\": delta%i;\n",
		    p, k, p->forward[k].next,
		    p->forward[k].next == GSISLNil ? 0 : k]];
	      [values setObject: foo forKey: value];
	      [foo release];
	    }
	  else
	    {
	      [foo appendString:
		[NSString stringWithFormat:
		  @"|{ <delta%i> %i | <forward%i> }",
		  k, p->forward[k].delta, k]];
	      if (p != GSISLNil)
	        [edges addObject:
		  [NSString stringWithFormat:
		    @"\"%p\": forward%i -> \"%p\": delta%i;\n",
		    p, k, p->forward[k].next,
		    p->forward[k].next == GSISLNil ? 0 : k]];
	      [values setObject: foo forKey: value];
	    }
	}
    }
	  
  tmp = [values allKeys];
  for (i = 0; i < [tmp count]; i++)
    {
      [graph appendString: [values objectForKey: [tmp objectAtIndex: i]]];
      [graph appendString: @"\"];\n"];
    }
  for (i = 0; i < [edges count]; i++)
    {
      [graph appendString: [edges objectAtIndex: i]];
    }
  [graph appendString: @"}\n"];
  [values release];
  [edges release];
  return [graph autorelease];
}

@end
