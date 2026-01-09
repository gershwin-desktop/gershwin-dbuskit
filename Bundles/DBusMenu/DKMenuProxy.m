/** Proxy class for exporting an NSMenu via Canonical's D-Bus interface.
   Copyright (C) 2013 Free Software Foundation, Inc.

   Written by:  Niels Grewe <niels.grewe@halbordnung.de>
   Created: July 2013

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
   Boston, MA 02111 USA.
   */

#import "DKMenuProxy.h"

#import <Foundation/NSArray.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSInvocation.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSMapTable.h>
#import <Foundation/NSString.h>
#import <Foundation/NSValue.h>

#import <GNUstepBase/NSDebug+GNUstepBase.h>

#import <AppKit/NSApplication.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>

#import <DBusKit/DKStruct.h>
#import <DBusKit/DKNumber.h>
#import <DBusKit/DKVariant.h>
#import <DBusKit/DKNotificationCenter.h>

#define VARIANT(X) [DKVariant variantWithObject: X]
#define DK_INT32(X) [DKInt32Number numberWithInt32: X]
/*
 * The keys for menu properties. We export these in the header.
 */
NSString const *kDKMenuTypeKey = @"type";
NSString const *kDKMenuLabelKey = @"label";
NSString const *kDKMenuEnabledKey = @"enabled";
NSString const *kDKMenuVisibleKey = @"visible";
NSString const *kDKMenuIconNameKey = @"icon-name";
NSString const *kDKMenuIconDataKey = @"icon-data";
NSString const *kDKMenuShortcutKey = @"shortcut";
NSString const *kDKMenuToggleTypeKey = @"toggle-type";
NSString const *kDKMenuToggleStateKey = @"toggle-state";
NSString const *kDKMenuChildrenDisplayKey = @"children-display";

/*
 * The default values for the menu properties. We keep these private.
 */
static NSString const 	*DKMenuTypeDefaultValue = @"standard";
static NSString const   *DKMenuTypeSeparatorValue = @"separator";
static NSString const	*DKMenuLabelDefaultValue = @"";
static NSNumber 	*DKMenuEnabledDefaultValue;
static NSNumber 	*DKMenuVisibleDefaultValue;
static NSString const	*DKMenuIconNameDefaultValue = @"";
static NSData		*DKMenuIconDataDefaultValue;
static NSArray		*DKMenuShortcutDefaultValue;
static NSString	const	*DKMenuToggleTypeDefaultValue = @""; 
static NSNumber		*DKMenuToggleStateDefaultValue;
static NSString const   *DKMenuChildrenDisplayDefaultValue = @"";
static NSString const   *DKMenuChildrenDisplaySubmenuValue = @"submenu";
static NSString const	*DKMenuEventClicked = @"clicked";
//static NSString const	*DKMenuEventHovered = @"hovered";

static NSDictionary *DKMenuAllDefaults;

@interface NSMenu (DBusExport)
- (id)valueForDBusProperty: (NSString*)property;
@end

@interface NSMenuItem (DBusExport)
- (id)valueForDBusProperty: (NSString*)property;
- (NSArray*)layoutToDepth: (NSInteger)depth properties: (NSArray*)properties forProxy: (DKMenuProxy*)proxy;
@end

@interface NSMenuItem (MacOSLeopardOrLater)
- (BOOL)isHidden;
@end

BOOL DKMenuValueIsDefaultForKey(id value, NSString *key)
{
  id defaultValue = [DKMenuAllDefaults objectForKey: key];
  return ((defaultValue == value) || [defaultValue isEqual: value]);
}

NSDictionary* DKMenuPropertyDictionaryForDBusProperties(id menuObject, NSArray* propertyNames)
{
  if ((nil == propertyNames) || (0 == [propertyNames count]))
  {
    propertyNames = [DKMenuAllDefaults allKeys];
  }
  NSEnumerator *kEnum = [propertyNames objectEnumerator];
  NSString *key = nil;
  NSMutableDictionary *dict = [NSMutableDictionary dictionary];
  while (nil != (key = [kEnum nextObject]))
  {
    id value = [menuObject valueForDBusProperty: key];
    if ((nil != value) && (NO == DKMenuValueIsDefaultForKey(value, key)))
    {
      [dict setObject: value forKey: key];
    }
  }
  return dict;
}


@implementation NSMenuItem (DBusExport)

-(id)_DBusMenu_valueFor_children_display_Property
{
  if ([self hasSubmenu])
    {
      return DKMenuChildrenDisplaySubmenuValue;
    }
  return DKMenuChildrenDisplayDefaultValue;
}


- (id)_DBusMenu_valueFor_visible_Property
{
  // GNUstep doesn't implement -isHidden yet
  if (([self respondsToSelector: @selector(isHidden)])
    && ([self isHidden]))
    {
      return [NSNumber numberWithBool: NO];
    }
 return [NSNumber numberWithBool: YES]; 
}

- (id)_DBusMenu_valueFor_type_Property
{
  if ([self isSeparatorItem])
    {
      return DKMenuTypeSeparatorValue; 
    }
  return DKMenuTypeDefaultValue;
}

- (id)_DBusMenu_valueFor_label_Property
{
  NSString *title = [self title];
  NSUInteger mnemonic = [self mnemonicLocation];
  NSUInteger titleLength = [title length];
  
  // Check if mnemonic is valid and within the title bounds
  if (NSNotFound != mnemonic && mnemonic < titleLength)
    {
      NSString *first =  [title substringToIndex: mnemonic];
      NSString *second = [title substringFromIndex: mnemonic];
      first = [first stringByReplacingOccurrencesOfString: @"_" withString: @"__"];
      second = [second stringByReplacingOccurrencesOfString: @"_" withString: @"__"]; 
      title = [NSString stringWithFormat: @"%@_%@", first, second];
    }
  else
    {
      title = [title stringByReplacingOccurrencesOfString: @"_" withString: @"__"];
    }
  return title;
}

- (id)_DBusMenu_valueFor_enabled_Property
{
  return [NSNumber numberWithBool: YES];
}

- (id)_DBusMenu_valueFor_icon_data_Property
{
  NSImage *image = [self image];
  if (nil == image)
    {
      return nil;
    }
  [image lockFocus];
  NSSize s = [image size];
  NSBitmapImageRep *bitmapRep = [[NSBitmapImageRep alloc] initWithFocusedViewRect:
    NSMakeRect(0, 0, s.width, s.height)];
  [image unlockFocus]; 
  return [bitmapRep representationUsingType: NSPNGFileType
                                 properties: nil];
}

-(id)_DBusMenu_valueFor_shortcut_Property
{
  NSString *equiv = [self keyEquivalent];
  if ([@"" isEqualToString: equiv])
    {
      return nil;
    }
  NSMutableArray *shortcut = [NSMutableArray array];
  NSUInteger modifiers = [self keyEquivalentModifierMask];
  if (modifiers & NSShiftKeyMask)
    {
      [shortcut addObject: @"Shift"];
    }
  if (modifiers & NSAlternateKeyMask)
    {
      [shortcut addObject: @"Alt"];
    }
  if (modifiers & NSControlKeyMask)
    {
      [shortcut addObject: @"Control"];
    }
  if (modifiers & NSCommandKeyMask)
    {
      [shortcut addObject: @"Super"];
    }
  [shortcut addObject: equiv];
  return [NSArray arrayWithObject: shortcut];
}

- (id)valueForDBusProperty: (NSString*)key
{
  NSString *str = [NSString stringWithFormat: @"_DBusMenu_valueFor_%@_Property", [key stringByReplacingOccurrencesOfString: @"-" withString: @"_"]];
  SEL selector = NSSelectorFromString(str);
  id returnValue = nil;
  if ((NULL != selector) && [self respondsToSelector: selector])
    {
      NSInvocation *inv = [NSInvocation invocationWithMethodSignature: [self methodSignatureForSelector: selector]];
      [inv setTarget: self];
      [inv setSelector: selector];
      NS_DURING
        {
          [inv invoke];
          [inv getReturnValue: &returnValue];
        }
      NS_HANDLER
        {
          NSWarnMLog(@"Exception getting D-Bus menu property %@: %@", key, localException);
        }
      NS_ENDHANDLER
    }
  returnValue = VARIANT(returnValue);
  return returnValue;
}

/**
 * This method returns a recursive structure compliant with the DBus menu format:
 * identifier,propertyDict,{child structures}
 */
- (NSArray*)layoutToDepth: (NSInteger)depth 
               properties: (NSArray*)properties
                 forProxy: (DKMenuProxy*)proxy
{
  // Safety check: Ensure self is actually an NSMenuItem
  // Use exception handler to catch crashes from corrupt pointers
  NS_DURING
    {
      if (![self isKindOfClass: [NSMenuItem class]])
        {
          NSWarnMLog(@"layoutToDepth called on invalid object: %p. Returning nil.", self);
          return nil;
        }
    }
  NS_HANDLER
    {
      NSWarnMLog(@"layoutToDepth crashed checking self validity: %@. Returning nil.", localException);
      return nil;
    }
  NS_ENDHANDLER
  
  NSNumber *identifier = DK_INT32([proxy DBusIDForMenuObject: self]);
  NSDictionary *props = DKMenuPropertyDictionaryForDBusProperties(self, properties);
  NSArray *children = nil;
  NSDebugMLLog(@"DKMenu", @"Generating layout for %@. D-Bus facing identifier is %@, properties %@ (requested depth: %ld)", self, identifier, properties, depth);
  if ((depth == 0) || (NO == [self hasSubmenu]))
    {
      children = [NSArray array];
      NSDebugMLLog(@"DKMenu", @"Generating layout for %@. Not emitting any child layouts.", self);
    }
  else
    {
      NSMutableArray *c = [NSMutableArray array];
      NSInteger nextDepth = depth;
      if (-1 != depth)
        {
          nextDepth = depth - 1;
        }
      
      // Make a copy of the itemArray to avoid issues if the menu changes
      NSArray *items = [[[[self submenu] itemArray] copy] autorelease];
      
      // Safety check: Ensure items is actually an array
      if (!items || ![items isKindOfClass: [NSArray class]])
        {
          NSWarnMLog(@"Invalid itemArray returned from submenu: %@ (class: %@). Using empty array.", 
                    items, [items class]);
          items = [NSArray array];
        }
      
      NSUInteger count = [items count];
      NSDebugMLLog(@"DKMenu", @"Generating layout for %@. Emitting %lu child layouts.", 
        self, count);
      
      // Use index-based iteration which is safer than enumerators
      for (NSUInteger i = 0; i < count; i++)
        {
          id item = [items objectAtIndex: i];
          
          // Validate that item is an NSMenuItem before using it
          if (!item || ![item isKindOfClass: [NSMenuItem class]])
            {
              NSWarnMLog(@"Skipping invalid menu item at index %lu in layout (class: %@, ptr: %p)",
                        i, [item class], item);
              continue;
            }
          
          NSArray *childLayout = [item layoutToDepth: nextDepth
                                          properties: properties
                                            forProxy: proxy];
          if (nil != childLayout)
            {
              [c addObject: childLayout];
            }
        }
      children = c;
    }
    NSDebugMLLog(@"DKMenu", @"Identifier %@ Obj-C type: %s", identifier, [identifier objCType]); 
  return [DKStructArray arrayWithObjects: identifier, props, children, nil];
}

@end


@implementation NSMenu (DBusExport)
- (id)valueForDBusProperty: (NSString*)key
{
  if ([kDKMenuTypeKey isEqualToString: key])
  {
    return DKMenuTypeDefaultValue;
  }

  if ([kDKMenuLabelKey isEqualToString: key])
  {
    return [self title];  
  }
  if ([kDKMenuChildrenDisplayKey isEqualToString: key])
    {
      return DKMenuChildrenDisplaySubmenuValue;
    }
  
  return nil;
}
@end

@implementation DKMenuProxy

+ (void)initialize
{ 
  if (self == [DKMenuProxy class])
  {
    DKMenuEnabledDefaultValue = [[NSNumber numberWithBool: YES] retain];
    DKMenuVisibleDefaultValue = [[NSNumber numberWithBool: YES] retain];
    DKMenuIconDataDefaultValue = [NSData new];
    DKMenuShortcutDefaultValue = [NSArray new];
    DKMenuToggleStateDefaultValue = [DK_INT32(-1) retain];
    DKMenuAllDefaults = [[NSDictionary alloc] initWithObjectsAndKeys:
      DKMenuTypeDefaultValue, kDKMenuTypeKey,
      DKMenuLabelDefaultValue, kDKMenuLabelKey, 
      DKMenuEnabledDefaultValue, kDKMenuEnabledKey, 
      DKMenuVisibleDefaultValue, kDKMenuVisibleKey,
      DKMenuIconNameDefaultValue, kDKMenuIconNameKey, 
      DKMenuIconDataDefaultValue, kDKMenuIconDataKey,
      DKMenuShortcutDefaultValue, kDKMenuShortcutKey,
      DKMenuToggleTypeDefaultValue, kDKMenuToggleTypeKey, 
      DKMenuToggleStateDefaultValue, kDKMenuToggleStateKey,
      DKMenuChildrenDisplayDefaultValue, kDKMenuChildrenDisplayKey, nil];
  }
}


- (void)_mapMenu: (NSMenu*)menu usingIdentifierReference: (int32_t*)identifier
{
  if (!menu)
    {
      NSWarnMLog(@"_mapMenu called with nil menu");
      return;
    }
    
  // Make a copy of the itemArray to avoid issues if the menu changes
  NSArray *items = [[menu itemArray] copy];
  if (!items)
    {
      NSWarnMLog(@"itemArray returned nil for menu: %@", menu);
      return;
    }
  
  NSUInteger count = [items count];
  NSDebugMLLog(@"DKMenu", @"_mapMenu processing %lu items from menu: %@", count, [menu title]);
  
  // Use index-based iteration which is safer than enumerators
  for (NSUInteger i = 0; i < count; i++)
    {
      id item = [items objectAtIndex: i];
      
      // Validate that item is an NSMenuItem before using it
      if (!item || ![item isKindOfClass: [NSMenuItem class]])
        {
          NSWarnMLog(@"Skipping invalid menu item at index %lu (class: %@, ptr: %p)", 
                    i, [item class], item);
          continue;
        }
      
      [lock lock];
      // Only add if not already present (use pointer as key directly)
      if ([nativeToDBus objectForKey: item] == nil)
        {
          int32_t ident = (*identifier)++;
          [nativeToDBus setObject: (void*)(intptr_t)ident forKey: item];
          [dBusToNative setObject: item forKey: (void*)(intptr_t)ident];
          
          // Check if item has submenu while still holding the lock
          BOOL hasSubmenu = [item hasSubmenu];
          NSMenu *submenu = hasSubmenu ? [item submenu] : nil;
          [lock unlock];
          
          // Recursively map submenu outside the lock to avoid deadlock
          if (hasSubmenu && submenu)
            {
              [self _mapMenu: submenu usingIdentifierReference: identifier];
            }
        }
      else
        {
          [lock unlock];
        }
    }
  
  [items release];
}

- (void)_createMapping
{
  [lock lock];
  [nativeToDBus removeAllObjects];
  [dBusToNative removeAllObjects];
  int32_t identifier = 1; // 0 would be the root
  [lock unlock];
  [self _mapMenu: representedMenu usingIdentifierReference: &identifier]; 
            
  NSDebugMLLog(@"DKMenu", @"Created mappings for %d menu items", (identifier - 1));
}

- (NSMapTable*)_nativeToDBusMap
{
  return nativeToDBus;
}

- (NSMapTable*)_DBusToNativeMap
{
  return dBusToNative;
}

- (BOOL)isExported
{
  return exported;
}

- (int32_t)DBusIDForMenuObject: (NSMenuItem*)item
{
  int32_t identifier = 0;
  
  // Safety check: Ensure item is actually an NSMenuItem
  // Use exception handler to catch crashes from corrupt pointers
  NS_DURING
    {
      if (!item || ![item isKindOfClass: [NSMenuItem class]])
        {
          NSWarnMLog(@"DBusIDForMenuObject called with invalid item: %p. Returning 0.", item);
          return 0;
        }
    }
  NS_HANDLER
    {
      NSWarnMLog(@"DBusIDForMenuObject crashed checking item validity: %@. Returning 0.", localException);
      return 0;
    }
  NS_ENDHANDLER
  
  [lock lock];
  void *value = [nativeToDBus objectForKey: item];
  if (value != NULL)
    {
      identifier = (int32_t)(intptr_t)value;
    }
  [lock unlock];
  return identifier;
}

- (NSMenuItem*)_nativeMenuObjectForDBusID: (int32_t)identifier
{
  NSMenuItem* item = nil;
  [lock lock];
  item = [dBusToNative objectForKey: (void*)(intptr_t)identifier];
  [lock unlock];
  return item;
}
- (void)notifyMenuServer
{
 if (NO == exported)
   {
     return;
   }
 // We could do this much more efficiently if we had a smarter
 // idea of how the menu changed.
 NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
   [NSNumber numberWithUnsignedInteger: revision], @"arg0", 
   DK_INT32(0), @"arg1", nil];
 if (center == nil)
   {
     center = [[DKNotificationCenter sessionBusCenter] retain];
   }
 [center postSignalName: @"LayoutUpdated"
              interface: @"com.canonical.dbusmenu"
                 object: self
               userInfo: info];
}

- (void)setExported: (BOOL)yesno
{
  if ((exported == NO) && (yesno == YES))
    {
      [self notifyMenuServer];
    }
  exported = yesno;
}



- (id)initWithMenu:(NSMenu *)menu
{
  if (menu == nil || [menu numberOfItems] == 0)
  {
    NSLog(@"[DKMenuProxy] Skipping initWithMenu: due to empty or nil menu");
    return nil;
  }

  if ((self = [super init]) != nil)
  {
    representedMenu = [menu retain];
    // Use NSMapTable with pointer identity semantics to avoid messaging potentially
    // corrupt/deallocated objects during lookups
    nativeToDBus = [[NSMapTable alloc] initWithKeyOptions: NSPointerFunctionsOpaqueMemory | NSPointerFunctionsOpaquePersonality
                                             valueOptions: NSPointerFunctionsIntegerPersonality | NSPointerFunctionsOpaqueMemory
                                                 capacity: 24];
    dBusToNative = [[NSMapTable alloc] initWithKeyOptions: NSPointerFunctionsIntegerPersonality | NSPointerFunctionsOpaqueMemory
                                             valueOptions: NSPointerFunctionsOpaqueMemory | NSPointerFunctionsOpaquePersonality
                                                 capacity: 24];
    lock = [NSRecursiveLock new];
    [self _createMapping];
  }
  return self;
}
- (void)menuUpdated:(NSMenu *)menu
{
  if (menu == nil || [menu numberOfItems] == 0)
  {
    NSLog(@"[DKMenuProxy] Skipping menuUpdated: due to empty or nil menu");
    return;
  }

  [lock lock];
  if (![menu isEqual:representedMenu])
  {
    ASSIGN(representedMenu, menu);
  }

  NS_DURING
    {
      [self _createMapping];
    }
  NS_HANDLER
    {
      [lock unlock];
      [localException raise];
    }
  NS_ENDHANDLER

  __sync_fetch_and_add(&revision, 1);
  [self notifyMenuServer];
  NSDebugMLLog(@"DKMenu", @"Represented menu updated");
  [lock unlock];
}

- (uint32_t)Version
{
  // Seems to be 2 presently
  return 2;
}

- (NSString*)Status
{
  return @"standard";
}

- (NSArray*)layoutForParent: (int32_t)parentID depth: (int32_t)depth properties: (NSArray*)propertyNames
{ 
  NSArray *layout = nil;
  [lock lock];
  // TODO: Exception handler
  if (parentID == 0)
    {
      NSNumber *identifier = DK_INT32(0);
      NSDictionary *properties = DKMenuPropertyDictionaryForDBusProperties(representedMenu, propertyNames);
      NSArray *children = nil;
      if (0 == depth)
        {
          children = [NSArray array];
        }
      else
        {
          NSMutableArray *c = [NSMutableArray array];
          NSInteger nextDepth = depth;
          if (depth != -1)
            {
              nextDepth = depth - 1;
            }
          // Make a copy of the itemArray to avoid issues if the menu changes
          NSArray *items = [[representedMenu itemArray] copy];
          if (!items)
            {
              NSWarnMLog(@"itemArray returned nil for representedMenu");
              items = [[NSArray array] retain];
            }
          NSUInteger count = [items count];
          for (NSUInteger i = 0; i < count; i++)
            {
              id item = [items objectAtIndex: i];
              if (!item || ![item isKindOfClass: [NSMenuItem class]])
                {
                  NSWarnMLog(@"Skipping invalid menu item at index %lu in layoutForParent", i);
                  continue;
                }
              NSArray *childLayout = [item layoutToDepth: nextDepth
                                              properties: propertyNames
                                                forProxy: self];   
              if (nil != childLayout)
                {
                  [c addObject: childLayout];
                }
            }
          [items release];
          children = c;
        }
      layout = [DKStructArray arrayWithObjects: identifier, properties, children, nil];
    }
  else
    {
       // General case
       id menuObject = [self _nativeMenuObjectForDBusID: parentID];
       layout =  [menuObject layoutToDepth: depth
                                properties: propertyNames
                                  forProxy: self];
    }
  [lock unlock];
  NSDebugMLLog(@"DKMenu", @"Created layout: %@", layout);
  return [NSArray arrayWithObjects: [NSNumber numberWithUnsignedInt: revision], layout, nil];
}

- (NSArray*)menuItems: (NSArray*)menuItemIDs properties: (NSArray*)propertyNames
{
  NSEnumerator *mEnum = [menuItemIDs objectEnumerator];
  NSNumber *item = nil;
  NSMutableArray *array = [NSMutableArray arrayWithCapacity: [menuItemIDs count]]; 
  while (nil != (item = [mEnum nextObject]))
  {
    id menuObject = nil;
    if (0 == [item unsignedIntegerValue])
      {
        menuObject = representedMenu;
      }
    else
      {
        menuObject = [self _nativeMenuObjectForDBusID: [item unsignedIntegerValue]]; 
      }
    if (nil == menuObject)
    {
      continue;
    }
    NSDictionary *propertyDict =  DKMenuPropertyDictionaryForDBusProperties(menuObject,propertyNames);
    [array addObject: [DKStructArray arrayWithObjects: item, propertyDict, nil]]; 
  }
  NSDebugMLLog(@"DKMenu", @"Responding to property query %@ for %@: %@", propertyNames, menuItemIDs, array);
  return array;
}

- (id)menuItem: (NSNumber*)menuID property: (NSString*)property
{
  id menuObject = [self _nativeMenuObjectForDBusID: [menuID unsignedIntegerValue]];
  return [menuObject valueForDBusProperty: property];
}


- (void)menuItem: (NSNumber*)menuID
   receivedEvent: (NSString*)eventType
            data: (id)data 
       timestamp: (NSNumber*)timestamp
{
  if ([DKMenuEventClicked isEqualToString: eventType])
    {
      NSMenuItem *item = [self _nativeMenuObjectForDBusID: [menuID unsignedIntegerValue]];
      SEL action = [item action];
      id target = [item target];
      NSDebugMLLog(@"DKMenu", @"Sending action %@ to %@ from %@ (D-Bus ID: %@)",
        NSStringFromSelector(action), target, item, menuID);
      [NSApp sendAction: action
                     to: target
                   from: item];
    }
  else
    {
      NSDebugMLLog(@"DKMenu", @"Ignored '%@' event for D-Bus menu item with ID %@", eventType, menuID);
    }
}

- (BOOL)willShowMenuItem: (NSNumber*)menuID
{
  // Ignore
  return NO;
}

- (void)dealloc
{
  [representedMenu release];
  [nativeToDBus release];
  [dBusToNative release];
  [center release];
  [lock release];
  [super dealloc];
}
@end
