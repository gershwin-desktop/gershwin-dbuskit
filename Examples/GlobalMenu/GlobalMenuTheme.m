#include "GlobalMenuTheme.h"

static Class _menuRegistryClass;

@implementation GlobalMenuTheme

- (Class)_findDBusMenuRegistryClass
{
  NSString	*path;
  NSBundle	*bundle;
  NSArray	*paths;
  NSUInteger	count;

  if (Nil != _menuRegistryClass)
    {
      return _menuRegistryClass;
    }
  paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory,
    NSAllDomainsMask, YES);
  count = [paths count];
  
  while (count-- > 0)
    {
       path = [paths objectAtIndex: count];
       path = [path stringByAppendingPathComponent: @"Bundles"];
       path = [path stringByAppendingPathComponent: @"DBusMenu"];
       path = [path stringByAppendingPathExtension: @"bundle"];
       
       bundle = [NSBundle bundleWithPath: path];
       if (bundle != nil)
         {
           if ((_menuRegistryClass = [bundle principalClass]) != Nil)
             {
               break;  
             }
         }
     }
     
  return _menuRegistryClass;
}

- (id) initWithBundle: (NSBundle *)bundle
{
  if((self = [super initWithBundle: bundle]) != nil)
    {
      menuRegistry = [[self _findDBusMenuRegistryClass] new];
      
      [[NSNotificationCenter defaultCenter] 
        addObserver: self
           selector: @selector(macintoshMenuDidChange:)
               name: @"NSMacintoshMenuDidChangeNotification"
             object: nil];
    }
  return self;
}

- (void) dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver: self];
  [super dealloc];
}

- (void) macintoshMenuDidChange: (NSNotification*)notification
{
  NSMenu *menu = [notification object];
  
  if (([NSApp mainMenu] == menu) && menuRegistry != nil)
    {
      NSWindow *keyWindow = [NSApp keyWindow];
      if (keyWindow != nil)
        {
          [self setMenu: menu forWindow: keyWindow];
        }
    }
}

- (void)setMenu: (NSMenu*)m forWindow: (NSWindow*)w
{
  if (nil != menuRegistry && m != nil && [m numberOfItems] > 0)
    {
      @try 
        {
          [menuRegistry setMenu: m forWindow: w];
        }
      @catch (NSException *exception)
        {
        }
    }
  else if (nil == menuRegistry)
    {
      [super setMenu: m forWindow: w];
    }
}

- (void)updateAllWindowsWithMenu: (NSMenu*)menu
{
  [super updateAllWindowsWithMenu: menu];
}

- (NSRect)modifyRect: (NSRect)rect forMenu: (NSMenu*)menu isHorizontal: (BOOL)horizontal
{
  NSInterfaceStyle style = NSInterfaceStyleForKey(@"NSMenuInterfaceStyle", nil);
  
  if (style == NSMacintoshInterfaceStyle && menuRegistry != nil && ([NSApp mainMenu] == menu))
    {
      return NSZeroRect;
    }
  
  return [super modifyRect: rect forMenu: menu isHorizontal: horizontal];
}

- (BOOL)proposedVisibility: (BOOL)visibility forMenu: (NSMenu*)menu
{
  NSInterfaceStyle style = NSInterfaceStyleForKey(@"NSMenuInterfaceStyle", nil);
  
  if (style == NSMacintoshInterfaceStyle && menuRegistry != nil && ([NSApp mainMenu] == menu))
    {
      return NO;
    }
  
  return [super proposedVisibility: visibility forMenu: menu];
}

@end
