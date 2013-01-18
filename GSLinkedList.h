#if	!defined(INCLUDED_GSLINKEDLIST)
#define	INCLUDED_GSLINKEDLIST	1
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

#if !defined (GNUSTEP) &&  (MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_4)
typedef unsigned int NSUInteger;
#endif

@class GSLinkedList;

/** GSListLink provides simple doubly linked list functionality to
 * avoid the need to constantly re-invent it (as the OpenStep/Cocoa
 * APIs do not provide this).  The emphasis is on speed of operation
 * so instance variables are directly accessible and inline functions
 * are provided to manipulate them (without error cehcking), but you
 * can/should avoid these direct access features unless speed is
 * really critical.<br /> 
 * A list may either be 'normal' ... (where the head/tail ends of
 * the list have a nil pointer to the previous/next link) or 'circular'
 * in which case the list is not terminated. <br />
 * The GSListLink item carries a minimal payload of a single item which
 * is retained by the link.<br />
 * The GSListLink owner is an optional pointer to an object which 'owns'
 * the link ... a GSLinkedList instance may use this to check link
 * ownership when manipulating links.
 */
@interface	GSListLink : NSObject
{
  @public
  GSListLink	*next;		// Not retained
  GSListLink	*previous;	// Not retained
  GSLinkedList	*owner;		// Not retained
  NSObject	*item;
}
 
/** Initialise the receiver as a link for a circular linked list.
 */
- (id) initCircular;

/** Return the item in the link.
 */
- (NSObject*) item;

/** Return the next item in the list containing the receiver,
 * or nil if there are no more items.
 */
- (GSListLink*) next;

/** Return the list which owns the receiver or nil if the receiver is
 * not in a list.
 */
- (GSLinkedList*) owner;

/** Return the previous item in the list containing the receiver,
 * or nil if there are no more items.
 */
- (GSListLink*) previous;

/** Set an item value by retaining it and releasing any previous value.
 */
- (void) setItem: (NSObject*)anItem;
@end

/** Inserts link after at in a circular list.<br />
 * Arguments must not be nil and link must not be in a list
 * (ie its next and previous pointers must point to itsself).
 */
static inline void
GSLinkCircularInsertAfter(GSListLink *link, GSListLink *at)
{
  link->next = at->next;
  link->previous = at;
  link->next->previous = link;
  link->previous->next = link;
}

/** Inserts link before at in a circular list.<br />
 * Arguments must not be nil and link must not be in a list
 * (ie its next and previous pointers must point to itsself).
 */
static inline void
GSLinkCircularInsertBefore(GSListLink *link, GSListLink *at)
{
  link->next = at;
  link->previous = at->previous;
  link->next->previous = link;
  link->previous->next = link;
}

/** Removes link from any list it is in.<br />
 * The link argument must not be nil.
 */
static inline void
GSLinkCircularRemove(GSListLink *link)
{
  link->next->previous = link->previous;
  link->previous->next = link->next;
  link->next = link->previous = link;
}

/** Inserts link after at in a normal list.<br />
 * Arguments must not be nil and link must not be in a list
 * (ie its next and previous pointers must both be nil).
 */
static inline void
GSLinkInsertAfter(GSListLink *link, GSListLink *at)
{
  if (nil != at->next)
    {
      at->next->previous = link;
    }
  link->previous = at;
  at->next = link;
}

/** Inserts link before at in a normal list.<br />
 * Arguments must not be nil and link must not be in a list
 * (ie its next and previous pointers must both be nil).
 */
static inline void
GSLinkInsertBefore(GSListLink *link, GSListLink *at)
{
  if (nil != at->previous)
    {
      at->previous->next = link;
    }
  link->next = at;
  at->previous = link;
}

/** Removes link from the list it is in.<br />
 * The link argument must not be nil.
 */
static inline void
GSLinkRemove(GSListLink *link)
{
  if (nil != link->next)
    {
      link->next->previous = link->previous;
    }
  if (nil != link->previous)
    {
      link->previous->next = link->next;
    }
  link->next = link->previous = nil;
}


/** GSLinkedList manages a list of GSListLink objects.
 */
@interface	GSLinkedList : NSObject
{
  @public
  GSListLink	*head;		// First link in the list.
  GSListLink	*tail;		// Last link in the list.
  NSUInteger	count;		// Number of links in the list.
}

/** Appends link at the end of the linked list managed by the receiver.<br />
 * Retains the link.
 */
- (void) append: (GSListLink*)link;

/** Returns the number of links in the list.
 */
- (NSUInteger) count;

/** Remove all links from the list and release them all.
 */
- (void) empty;

/** Searches the linked list returning the link containing object or nil
 * if it is not found.<br />
 * The comparison is performed using the [NSObject-isEqual:] method
 * of object.<br />
 * If start is nil then the whole list is searched.<br />
 * This method will <em>not</em> find links containing nil items.
 */
- (GSListLink*) findEqual: (NSObject*)object
		     from: (GSListLink*)start
		     back: (BOOL)aFlag;

/** Searches the linked list returning the link containing object or nil
 * if it is not found.<br />
 * If start is nil then the whole list is searched.<br />
 * A direct pointer comparison is used to determine equality.
 */
- (GSListLink*) findIdentical: (NSObject*)object
			 from: (GSListLink*)start
			 back: (BOOL)aFlag;

/** Returns the first link in the list.
 */
- (GSListLink*) head;

/** Inserts other immediately after the receiver.<br />
 * Retains the link.
 */
- (void) insert: (GSListLink*)link after: (GSListLink*)at;

/** Inserts other immediately before the receiver.<br />
 * Retains the link.
 */
- (void) insert: (GSListLink*)link before: (GSListLink*)at;

/** Removes the link from the receiver.<br />
 * releases the link.
 */
- (void) removeLink: (GSListLink*)link;

/** Returns the last link in the list.
 */
- (GSListLink*) tail;

@end

/** Searches from list to the end looking for the first link containing
 * object (as determined by using object's [NSObject-isEqual:] method).<br />
 * If from is nil the list is search from head or tail as appropriate
 * to the direction in which it is searched.
 */
extern GSListLink*
GSLinkedListFindEqual(NSObject *object, GSLinkedList *list,
  GSListLink *from, BOOL back);

/** Searches from list to the end looking for the first link containing
 * object (as determined by direct pointer comparison).<br />
 * If from is nil the list is search from head or tail as appropriate
 * to the direction in which it is searched.
 */
extern GSListLink*
GSLinkedListFindIdentical(NSObject *object, GSLinkedList *list,
  GSListLink *from, BOOL back);

/** Inserts link immediately after at.<br />
 * Updates the head, tail and count variables of list.<br />
 * Does not retain link.
 */
extern void
GSLinkedListInsertAfter(GSListLink *link, GSLinkedList *list, GSListLink *at);

/** Inserts link immediately before at.<br />
 * Updates the head, tail and count variables of list.<br />
 * Does not retain link.
 */
extern void
GSLinkedListInsertBefore(GSListLink *link, GSLinkedList *list, GSListLink *at);

/** Moves the link to the head of the list if it is not already there.
 */
extern void
GSLinkedListMoveToHead(GSListLink *link, GSLinkedList *list);

/** Moves the link to the tail of the list if it is not already there.
 */
extern void
GSLinkedListMoveToTail(GSListLink *link, GSLinkedList *list);

/** Removes link from the list.<br />
 * Updates the head, tail and count variables of list.<br />
 * Does not release link.
 */
extern void
GSLinkedListRemove(GSListLink *link, GSLinkedList *list);

#endif
