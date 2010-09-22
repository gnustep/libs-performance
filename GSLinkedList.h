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

/** GSLinkedList provides simple doubly linked list functionality to
 * avoid the need to constantly re-invent it (as the OpenStep/Cocoa
 * APIs do not provide this).  The emphasis is on speed of operation
 * so instance variables are directly accessible and functions are
 * provided to manipulate them, but you can/should avoid these direct
 * access features unless speed is really critical.<br /> 
 * A list is handled simply as a pointer to the link whose 'prev'
 * pointer is nil. <br />
 * While the item value of a link is retaned by the link, links in a
 * list are not retained, so you must manage retain/relase yourself.
 */
@interface	GSLinkedList : NSObject
{
  @public
  GSLinkedList	*next;	// Not retained
  GSLinkedList	*prev;	// Not retained
  NSObject	*item;
}

/** Appends other at the end of the linked list contining the receiver.
 */
- (void) append: (GSLinkedList*)other;

/** Searches the linked list containing the receiver from the
 * receiver onwards, returning the link containing object or nil
 * if it is not found.<br />
 * The comparison is performed using the -isEqual: method of object.<br />
 * This method will <em>not</em> find links containins nil items.
 */
- (id) findEqual: (NSObject*)object;

/** Searches the linked list containing the receiver, from the receiver
 * onwards, returning the link containing object or nil if it is not found.
 * A direct pointer comparison is used to determine equality.
 */
- (id) findIdentical: (NSObject*)object;

/** Returns the first link in the list.
 */
- (id) head;

/** Inserts other immediately before the receiver.
 */
- (void) insert: (GSLinkedList*)other;

/** Returns the item in the link represented by the receiver.<br />
 * The item may be nil.
 */
- (NSObject*) item;

/** Returns the next link in the list, or nil if the receiver is at the tail.
 */
- (id) next;

/** Returns the previous link in the list, or nil if the receiver is at the
 * head.
 */
- (id) previous;

/** Removes the receiver from the linked list containing it.<br />
 * Returns the link which was next after the receiver.
 */
- (id) remove;

/** Replaces any existing item in the receiver with the supplied object.<br />
 * The item may be nil.
 */
- (void) setItem: (NSObject*)object;

/** Returns the last link in the list.
 */
- (id) tail;

@end

/** Appends link at the end of the list.
 */
extern void
GSLinkedListAppend(GSLinkedList *link, GSLinkedList *list);

/** Searches from list to the end looking for the first link containing
 * object (as determiend by using object's -isEqual: method).
 */
extern id
GSLinkedListFindEqual(NSObject *object, GSLinkedList *list);

/** Searches from list to the end looking for the first link containing
 * object (as determiend by direct pointer comparison).
 */
extern id
GSLinkedListFindIdentical(NSObject *object, GSLinkedList *list);

/** Inserts link immediately before at.
 */
extern void
GSLinkedListInsert(GSLinkedList *link, GSLinkedList *at);

/** Removes link from it list and returns the next item in the list
 * or nil if there is no next item.
 */
extern id
GSLinkedListRemove(GSLinkedList *link);

#endif
