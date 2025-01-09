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

#import <Foundation/NSString.h>
#import <Foundation/NSException.h>
#import "GSLinkedList.h"

#if !defined (GNUSTEP)
#import  "GNUstep.h"
#endif


@implementation	GSListLink

- (void) dealloc
{
  NSAssert(nil == owner, NSInternalInconsistencyException);
  [item release];
  DEALLOC;
}

- (id) initCircular
{
  if ((self = [super init]) != nil)
    {
      next = previous = self;
    }
  return self;
}

- (NSObject*) item
{
  return item;
}

- (GSListLink*) next
{
  if (next == self)
    {
      return nil;
    }
  return next;
}

- (GSLinkedList*) owner
{
  return owner;
}

- (GSListLink*) previous
{
  if (previous == self)
    {
      return nil;
    }
  return previous;
}

- (void) setItem: (NSObject*)anItem
{
  id	o = item;

  item = [anItem retain];
  RELEASE(o);
}

@end


@implementation	GSLinkedList
- (void) append: (GSListLink*)link
{
  if (nil == link)
    {
      [NSException raise: NSInvalidArgumentException
	format: @"[%@-%@] nil argument",
	NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
    }
  if (self == link->owner)
    {
      if (link != tail)
	{
	  GSLinkedListRemove(link, self);
	  GSLinkedListInsertAfter(link, self, tail);
	}
    }
  else
    {
      if (nil != link->owner || nil != link->next || nil != link->previous)
	{
	  [NSException raise: NSInvalidArgumentException
	    format: @"[%@-%@] other link is still in a list",
	    NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
	}
      GSLinkedListInsertAfter(link, self, tail);
      RETAIN(link);
    }
}

- (NSUInteger) count
{
  return count;
}

- (void) dealloc
{
  [self empty];
  DEALLOC;
}

- (void) empty
{
  GSListLink	*link;

  while (nil != (link = head))
    {
      head = link->next;
      link->owner = nil;
      link->next = link->previous = nil;
      RELEASE(link);
    }
  tail = nil;
  count = 0;
}

- (GSListLink*) findEqual: (NSObject*)object
		     from: (GSListLink*)start
		     back: (BOOL)aFlag
{
  if (nil != start && start->owner != self)
    {
      [NSException raise: NSInvalidArgumentException
	format: @"[%@-%@] start link is not in this list",
	NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
    }
  return GSLinkedListFindEqual(object, self, start, aFlag);
}

- (GSListLink*) findIdentical: (NSObject*)object
			 from: (GSListLink*)start
			 back: (BOOL)aFlag
{
  if (nil != start && start->owner != self)
    {
      [NSException raise: NSInvalidArgumentException
	format: @"[%@-%@] start link is not in this list",
	NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
    }
  return GSLinkedListFindIdentical(object, self, start, aFlag);
}

- (GSListLink*) head
{
  return head;
}

- (void) insert: (GSListLink*)link after: (GSListLink*)at
{
  if (nil == link)
    {
      [NSException raise: NSInvalidArgumentException
	format: @"[%@-%@] nil link argument",
	NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
    }
  if (nil == at)
    {
      at = tail;
    }
  if (at->owner != self)
    {
      [NSException raise: NSInvalidArgumentException
	format: @"[%@-%@] 'at' link is not in this list",
	NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
    }
  if (at == link)
    {
      return;
    }
  if (link->owner == self)
    {
      GSLinkedListRemove(link, self);
      GSLinkedListInsertAfter(link, self, at);
    }
  else
    {
      if (nil != link->owner || nil != link->next || nil != link->previous)
	{
	  [NSException raise: NSInvalidArgumentException
	    format: @"[%@-%@] other link is still in a list",
	    NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
	}
      GSLinkedListInsertAfter(link, self, at);
      RETAIN(link);
    }
}

- (void) insert: (GSListLink*)link before: (GSListLink*)at
{
  if (nil == link)
    {
      [NSException raise: NSInvalidArgumentException
	format: @"[%@-%@] nil link argument",
	NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
    }
  if (nil == at)
    {
      at = head;
    }
  if (at->owner != self)
    {
      [NSException raise: NSInvalidArgumentException
	format: @"[%@-%@] 'at' link is not in this list",
	NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
    }
  if (at == link)
    {
      return;
    }
  if (link->owner == self)
    {
      GSLinkedListRemove(link, self);
      GSLinkedListInsertBefore(link, self, at);
    }
  else
    {
      if (nil != link->owner || nil != link->next || nil != link->previous)
	{
	  [NSException raise: NSInvalidArgumentException
	    format: @"[%@-%@] other link is still in a list",
	    NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
	}
      GSLinkedListInsertBefore(link, self, at);
      RETAIN(link);
    }
}

- (void) removeLink: (GSListLink*)link
{
  if (nil == link)
    {
      [NSException raise: NSInvalidArgumentException
	format: @"[%@-%@] nil link argument",
	NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
    }
  if (link->owner != self)
    {
      [NSException raise: NSInvalidArgumentException
	format: @"[%@-%@] link is not in this list",
	NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
    }
  GSLinkedListRemove(link, self);
  RETAIN(link);
}

- (GSListLink*) tail
{
  return tail;
}

@end

GSListLink*
GSLinkedListFindEqual(NSObject *object, GSLinkedList *list,
  GSListLink *from, BOOL back)
{
  if (nil == object)
    {
      return GSLinkedListFindIdentical(object, list, from, back);
    }
  else
    {
      BOOL	(*imp)(id, SEL, id);

      imp = (BOOL(*)(id,SEL,id))[object methodForSelector: @selector(isEqual:)];
      if (YES == back)
	{
          if (nil == from)
            {
              from = list->tail;
            }
	  while (nil != from)
	    {
	      if (YES == (*imp)(object, @selector(isEqual:), from->item))
		{
		  return from;
		}
	      from = from->previous;
	    }
	}
      else
	{
          if (nil == from)
            {
              from = list->head;
            }
	  while (nil != from)
	    {
	      if (YES == (*imp)(object, @selector(isEqual:), from->item))
		{
		  return from;
		}
	      from = from->next;
	    }
	}
    }
  return nil;
}


GSListLink*
GSLinkedListFindIdentical(NSObject *object, GSLinkedList *list,
  GSListLink *from, BOOL back)
{
  if (YES == back)
    {
      if (nil == from)
        {
	  from = list->tail;
        }
      while (nil != from)
	{
	  if (object == from->item)
	    {
	      return from;
	    }
	  from = from->previous;
	}
    }
  else
    {
      if (nil == from)
        {
          from = list->head;
        }
      while (nil != from)
	{
	  if (object == from->item)
	    {
	      return from;
	    }
	  from = from->next;
	}
    }
  return nil;
}

void
GSLinkedListInsertAfter(GSListLink *link, GSLinkedList *list, GSListLink *at)
{
  if (nil == list->head)
    {
      list->head = list->tail = link;
    }
  else
    {
      if (nil == at)
        {
          at = list->tail;
        }
      link->next = at->next;
      link->previous = at;
      if (at->next)
	{
	  at->next->previous = link;
	}
      at->next = link;
      if (list->tail == at)
	{
	  list->tail = link;
	}
    }
  link->owner = list;
  list->count++;
}

void
GSLinkedListInsertBefore(GSListLink *link, GSLinkedList *list, GSListLink *at)
{
  if (nil == list->head)
    {
      list->head = list->tail = link;
    }
  else
    {
      if (nil == at)
        {
          at = list->head;
        }
      link->previous = at->previous;
      link->next = at;
      if (at->previous)
	{
	  at->previous->next = link;
	}
      at->previous = link;
      if (list->head == at)
	{
	  list->head = link;
	}
    }
  link->owner = list;
  list->count++;
}

void
GSLinkedListRemove(GSListLink *link, GSLinkedList *list)
{
  if (list->head == link)
    {
      list->head = link->next;
      if (nil != list->head)
	{
          list->head->previous = nil;
	}
    }
  else
    {
      link->previous->next = link->next;
    }
  if (list->tail == link)
    {
      list->tail = link->previous;
      if (nil != list->tail)
	{
          list->tail->next = nil;
	}
    }
  else
    {
      link->next->previous = link->previous;
    }
  link->next = link->previous = nil;
  link->owner = nil;
  list->count--;
}

extern void
GSLinkedListMoveToHead(GSListLink *link, GSLinkedList *list)
{
  if (link != list->head)
    {
      if (link == list->tail)
	{
	  list->tail = link->previous;
	  list->tail->next = nil;
	}
      else
	{
	  link->next->previous = link->previous;
	  link->previous->next = link->next;
	}
      link->next = list->head;
      link->previous = nil;
      list->head->previous = link;
      list->head = link;
    }
}

extern void
GSLinkedListMoveToTail(GSListLink *link, GSLinkedList *list)
{
  if (link != list->tail)
    {
      if (link == list->head)
	{
	  list->head = link->next;
	  list->head->previous = nil;
	}
      else
	{
	  link->next->previous = link->previous;
	  link->previous->next = link->next;
	}
      link->next = nil;
      link->previous = list->tail;
      list->tail->next = link;
      list->tail = link;
    }
}

@implementation GSLinkStore

+ (GSLinkStore*) storeFor: (Class)theLinkClass
{
  Class		c = [GSListLink class];
  GSLinkStore	*s;

  if (Nil == theLinkClass)
    {
      theLinkClass = c;
    }
  NSAssert([theLinkClass isSubclassOfClass: c], NSInvalidArgumentException);
  s = [self new];
  s->linkClass = theLinkClass;
  return AUTORELEASE(s);
}

- (GSListLink*) addObject: (id)anObject
{
  return GSLinkStoreInsertObjectAfter(anObject, self, tail);
}

- (void) consumeLink: (GSListLink*)link
{
  NSAssert(link, NSInvalidArgumentException);
  NSAssert(nil == link->previous, NSInvalidArgumentException);
  NSAssert(nil == link->next, NSInvalidArgumentException);
  NSAssert(nil == link->owner, NSInvalidArgumentException);
  NSAssert(nil == link->item, NSInvalidArgumentException);
  NSAssert([link class] == linkClass, NSInvalidArgumentException);
  GSLinkStoreConsumeLink(self, link);
}

- (void) dealloc
{
  [self empty];
  [self purge];
  DEALLOC
}

- (void) empty
{
  while (nil != head)
    {
      GSLinkStoreRemoveObjectAt(self, head);
    }
}

- (id) firstObject
{
  return GSLinkedListFirstObject(self);
}

- (id) init
{
  if (nil != (self = [super init]))
    {
      linkClass = [GSListLink class];
    }
  return self;
}

- (GSListLink*) insertObject: (id)anObject after: (GSListLink*)at
{
  return GSLinkStoreInsertObjectAfter(anObject, self, at);
}

- (GSListLink*) insertObject: (id)anObject before: (GSListLink*)at
{
  return GSLinkStoreInsertObjectBefore(anObject, self, at);
}

- (id) lastObject
{
  return GSLinkedListLastObject(self);
}

- (void) purge
{
  while (nil != free)
    {
      GSListLink        *link = free;

      free = link->next;
      link->next = nil;
      RELEASE(link);
    }
}

- (void) removeFirstObject
{
  if (nil != head)
    {
      GSLinkStoreRemoveObjectAt(self, head);
    }
}

- (void) removeLastObject
{
  if (nil != tail)
    {
      GSLinkStoreRemoveObjectAt(self, tail);
    }
}

- (void) removeObjectAt: (GSListLink*)at
{
  GSLinkStoreRemoveObjectAt(self, at);
}

- (void) removeObjectAtIndex: (NSUInteger)index
{
  GSListLink    *link = head;

  if (index >= count)
    {
      [NSException raise: NSInvalidArgumentException
	format: @"[%@-%@] index too large",
	NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
    }
  while (index-- > 0)
    {
      link = link->next;
    }
  GSLinkStoreRemoveObjectAt(self, link);
}

@end

GSListLink*
GSLinkStoreInsertObjectAfter(
  NSObject *anObject, GSLinkStore *list, GSListLink *at)
{
  GSListLink    *link = GSLinkStoreProvideLink(list);

  link->item = RETAIN(anObject);
  GSLinkedListInsertAfter(link, list, at);
  return link;
}

GSListLink*
GSLinkStoreInsertObjectBefore(
  NSObject *anObject, GSLinkStore *list, GSListLink *at)
{
  GSListLink    *link = GSLinkStoreProvideLink(list);

  link->item = RETAIN(anObject);
  GSLinkedListInsertBefore(link, list, at);
  return link;
}

void
GSLinkStoreRemoveObjectAt(GSLinkStore *list, GSListLink *at)
{
  if (nil != at && at->owner == list)
    {
      GSLinkedListRemove(at, list);
      RELEASE(at->item);
      at->item = nil;
      GSLinkStoreConsumeLink(list, at);
    }
}

