/**
   Copyright (C) 2006 Free Software Foundation, Inc.

   Written by:  Matt Rice <ratmice@yahoo.com>
   Date:        2006

   This file is part of the Performance Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Library General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Library General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111 USA.
   */

#include "GSSkipMutableArray.h"
#include <Foundation/NSException.h>
#include <Foundation/NSValue.h>
#include <Foundation/NSEnumerator.h>

@interface SkipMutableArray(Private)
- (GSISList) _list;
@end

@implementation SkipMutableArray(Private)
- (GSISList) _list
{
  return l;
}
@end

@interface SkipMutableArrayEnumerator : NSEnumerator
{
  GSISLNode node;  
}
@end

@implementation SkipMutableArrayEnumerator
- (id) initWithArray:(NSArray *)arr
{
  if (![arr isKindOfClass:[SkipMutableArray class]])
  {
    [[NSException exceptionWithName:NSInternalInconsistencyException reason:@"not a SkipMutableArray" userInfo:nil] raise];
  }
  self = [super init];
  node = [(SkipMutableArray *)arr _list]->header->forward[0].next;
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

@implementation SkipMutableArray : NSMutableArray
- (void) _raiseRangeExceptionWithIndex: (unsigned)index from: (SEL)sel
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


- (id) initWithObjects:(id *)objects count:(unsigned) count
{
  int i;
  self = [super init];

  if (!self) return nil;
  
  l = GSISLInitList([self zone]);
  
  for (i = 0; i < count; i++)
  {
    GSISLInsertItemAtIndex(l, RETAIN(objects[i]), i);
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
  do
    {
      q = p->forward[0].next;
      RELEASE(p->value);
      NSZoneFree(l->zone,p);
      p = q;
    } while (p != GSISLNil);
  NSZoneFree(l->zone, l->header); 
  NSZoneFree(l->zone, l);
}

- (void) insertObject:(id)object atIndex:(unsigned)index
{
  if (index > l->count)
    {
        [self _raiseRangeExceptionWithIndex: index from: _cmd];
    }

  GSISLInsertItemAtIndex(l, RETAIN(object), index);
}

- (id) objectAtIndex:(unsigned)index
{
  if (index >= l->count)
    {
      [self _raiseRangeExceptionWithIndex: index from: _cmd];
    }

  return GSISLItemAtIndex(l, index);
}

- (void) removeObjectAtIndex:(unsigned) index
{
  if (index >= l->count)
    {
        [self _raiseRangeExceptionWithIndex: index from: _cmd];
    }

  RELEASE(GSISLRemoveItemAtIndex(l, index)); 
}

- (void) addObject:(id)obj
{
  GSISLInsertItemAtIndex(l, RETAIN(obj), l->count);
}

- (unsigned) count
{
  return l->count;
}

- (void) replaceObjectAtIndex:(unsigned)index withObject:(id)obj
{
  RELEASE(GSISLReplaceItemAtIndex(l, RETAIN(obj), index));
}

- (NSEnumerator*) objectEnumerator
{
  id    e;

  e = [SkipMutableArrayEnumerator allocWithZone: NSDefaultMallocZone()];
  e = [e initWithArray: self];
  return AUTORELEASE(e);
}
/* returns an in an NSString suitable for running through graphviz,
 * with the graph named 'graphName' 
 */
- (NSString *) _makeGraphOfInternalLayoutNamed:(NSString *)graphName
{
  GSISLNode p;
  unsigned k, i;
  
  p = l->header;
  k = l->level;
  NSMutableString *graph = [[NSMutableString alloc] init];
  [graph appendString:[NSString stringWithFormat:@"digraph %@ {\n", graphName]];
  [graph appendString:@"graph [rankdir = LR];\n"];
  [graph appendString:@"node [shape = record];\n"];
  NSMutableDictionary *values = [[NSMutableDictionary alloc] init];
  NSMutableArray *edges = [[NSMutableArray alloc] init];
  NSArray *tmp;
  [values setObject:[NSMutableString stringWithFormat:@"\"%p\" [label = \"%p (NIL) |{ <delta0> 0 | <forward0> }",GSISLNil, GSISLNil] forKey:[NSString stringWithFormat:@"%p", GSISLNil]];
  for (k = 0; k < l->level + 1; k++)
    {
      for (p = l->header; p != GSISLNil; p = p->forward[k].next)
        {
	  NSString *value = [NSString stringWithFormat:@"%p", p];
	  NSMutableString *foo = [values objectForKey:value];
	  
	  if (foo == nil)
	    {
	      foo = [[NSMutableString alloc] init];
	      [foo appendString:[NSString stringWithFormat:@"\"%p\" [label = \"%p%@ |{ <delta%i> %i | <forward%i> }", p, p, p == l->header ? @"(HEADER)" : @"", k, p->forward[k].delta, k]];
	      if (p != GSISLNil)
	        [edges addObject:[NSString stringWithFormat:@"\"%p\":forward%i -> \"%p\":delta%i;\n",p,k, p->forward[k].next,p->forward[k].next == GSISLNil ? 0 : k]];
	      [values setObject:foo forKey:value];
	      RELEASE(foo);
	    }
	  else
	    {
	      [foo appendString:[NSString stringWithFormat:@"|{ <delta%i> %i | <forward%i> }", k, p->forward[k].delta, k]];
	      if (p != GSISLNil)
	        [edges addObject:[NSString stringWithFormat:@"\"%p\":forward%i -> \"%p\":delta%i;\n",p,k, p->forward[k].next, p->forward[k].next == GSISLNil ? 0 : k]];
	      [values setObject:foo forKey:value];
	    }
	}
    }
	  
  tmp = [values allKeys];
  for (i = 0; i < [tmp count]; i++)
    {
      [graph appendString:[values objectForKey:[tmp objectAtIndex:i]]];
      [graph appendString:@"\"];\n"];
    }
  for (i = 0; i < [edges count]; i++)
    {
      [graph appendString:[edges objectAtIndex:i]];
    }
  [graph appendString:@"}\n"];
  RELEASE(values);
  RELEASE(edges);
  return AUTORELEASE(graph);
}


@end
