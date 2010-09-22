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
#import <Foundation/NSException.h>
#import "GSLinkedList.h"

@implementation	GSLinkedList
- (void) append: (GSLinkedList*)other
{
  if (nil == other)
    {
      [NSException raise: NSInvalidArgumentException
	format: @"[%@-%@] nil argument",
	NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
    }
  if (other->next || other->prev)
    {
      [NSException raise: NSInvalidArgumentException
	format: @"[%@-%@] other link is still in a list",
	NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
    }
  GSLinkedListAppend(other, self);
}

- (void) dealloc
{
  if (next || prev)
    {
      [NSException raise: NSInternalInconsistencyException
	format: @"[%@-%@] receiver is still in a list",
	NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
    }
  [item release];
  [super dealloc];
}

- (id) findEqual: (NSObject*)object;
{
  return GSLinkedListFindEqual(object, self);
}

- (id) findIdentical: (NSObject*)object;
{
  return GSLinkedListFindIdentical(object, self);
}

- (id) head
{
  GSLinkedList	*link = self;

  while (nil != link->prev)
    {
      link = link->prev;
    }
  return link;
}

- (void) insert: (GSLinkedList*)other
{
  if (nil == other)
    {
      [NSException raise: NSInvalidArgumentException
	format: @"[%@-%@] nil argument",
	NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
    }
  if (other->next || other->prev)
    {
      [NSException raise: NSInvalidArgumentException
	format: @"[%@-%@] other link is still in a list",
	NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
    }
  GSLinkedListInsert(other, self);
}

- (NSObject*) item
{
  return item;
}

- (id) next
{
  return next;
}

- (id) previous
{
  return prev;
}

- (id) remove
{
  return GSLinkedListRemove(self);
}

- (void) setItem: (NSObject*)object
{
  id	o = item;

  item = [object retain];
  [o release];
}

- (id) tail
{
  GSLinkedList	*link = self;

  while (nil != link->next)
    {
      link = link->next;
    }
  return link;
}

@end

void
GSLinkedListAppend(GSLinkedList *link, GSLinkedList *list)
{
  while (nil != list->next)
    {
      list = list->next;
    }
  link->prev = list;
  list->next = link;
}

void
GSLinkedListInsert(GSLinkedList *link, GSLinkedList *at)
{
  link->next = at;
  if (nil != at->prev)
    {
      at->prev->next = link;
      link->prev = at->prev;
    }
  at->prev = link;
}

id
GSLinkedListRemove(GSLinkedList *link)
{
  GSLinkedList	*next = link->next;

  if (nil != link->next)
    {
      link->next->prev = link->prev;
    }
  if (nil != link->prev)
    {
      link->prev->next = link->next;
    }
  link->next = nil;
  link->prev = nil;
  return next;
}

id
GSLinkedListFindEqual(NSObject *object, GSLinkedList *list)
{
  if (nil != object)
    {
      BOOL	(*imp)(id, SEL, id);

      imp = (BOOL(*)(id,SEL,id))[object methodForSelector: @selector(isEqual:)];
      while (nil != list)
	{
	  if (YES == (*imp)(object, @selector(isEqual:), list->item))
	    {
	      return list;
	    }
	  list = list->next;
	}
    }
  return nil;
}

id
GSLinkedListFindIdentical(NSObject *object, GSLinkedList *list)
{
  while (nil != list)
    {
      if (object == list->item)
	{
	  return list;
	}
      list = list->next;
    }
  return nil;
}

