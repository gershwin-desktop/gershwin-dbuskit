#include "GlobalMenuTheme.h"

/*
 * The class used by the DBus menu registry
 */
static Class _menuRegistryClass;

@implementation GlobalMenuTheme

- (Class)_findDBusMenuRegistryClass
{
  NSString	*path;
  NSBundle	*bundle;
  NSArray	*paths;
  NSUInteger	count;

  NSLog(@"[GlobalMenuTheme] Looking for DBusMenu.bundle...");
  
  if (Nil != _menuRegistryClass)
    {
      NSLog(@"[GlobalMenuTheme] Already found registry class: %@", _menuRegistryClass);
      return _menuRegistryClass;
    }
  paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory,
    NSAllDomainsMask, YES);
  count = [paths count];
  
  NSLog(@"[GlobalMenuTheme] Searching in %lu directories", (unsigned long)count);
  for (NSUInteger i = 0; i < count; i++)
    {
      NSString *searchPath = [paths objectAtIndex: i];
      NSLog(@"[GlobalMenuTheme] Checking directory: %@", searchPath);
    }
  
  while (count-- > 0)
    {
       path = [paths objectAtIndex: count];
       path = [path stringByAppendingPathComponent: @"Bundles"];
       path = [path stringByAppendingPathComponent: @"DBusMenu"];
       path = [path stringByAppendingPathExtension: @"bundle"];
       
       NSLog(@"[GlobalMenuTheme] Looking for bundle at: %@", path);
       
       bundle = [NSBundle bundleWithPath: path];
       if (bundle != nil)
         {
           NSLog(@"[GlobalMenuTheme] Found bundle: %@", bundle);
           if ((_menuRegistryClass = [bundle principalClass]) != Nil)
             {
               NSLog(@"[GlobalMenuTheme] Found principal class: %@", _menuRegistryClass);
               break;  
             }
           else
             {
               NSLog(@"[GlobalMenuTheme] Bundle has no principal class");
             }
         }
       else
         {
           NSLog(@"[GlobalMenuTheme] No bundle found at path");
         }
     }
     
  if (_menuRegistryClass == Nil)
    {
      NSLog(@"[GlobalMenuTheme] ERROR: Could not find DBusMenu registry class!");
    }
     
  return _menuRegistryClass;
}

- (id) initWithBundle: (NSBundle *)bundle
{
  NSLog(@"[GlobalMenuTheme] Initializing with bundle: %@", bundle);
  
  if((self = [super initWithBundle: bundle]) != nil)
    {
      NSLog(@"[GlobalMenuTheme] Super init successful, finding registry...");
      menuRegistry = [[self _findDBusMenuRegistryClass] new];
      
      if (menuRegistry != nil)
        {
          NSLog(@"[GlobalMenuTheme] Successfully created menu registry: %@", menuRegistry);
        }
      else
        {
          NSLog(@"[GlobalMenuTheme] ERROR: Failed to create menu registry!");
        }
      
      // Listen for Macintosh menu changes
      [[NSNotificationCenter defaultCenter] 
        addObserver: self
           selector: @selector(macintoshMenuDidChange:)
               name: @"NSMacintoshMenuDidChangeNotification"
             object: nil];
      
      NSLog(@"[GlobalMenuTheme] Registered for NSMacintoshMenuDidChangeNotification");
    }
  else
    {
      NSLog(@"[GlobalMenuTheme] ERROR: Super init failed!");
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
  NSLog(@"[GlobalMenuTheme] Received macintoshMenuDidChange for menu: %@", [menu title]);
  
  if (([NSApp mainMenu] == menu) && menuRegistry != nil)
    {
      NSWindow *keyWindow = [NSApp keyWindow];
      NSLog(@"[GlobalMenuTheme] Sending Macintosh menu to DBus for window: %@", keyWindow);
      if (keyWindow != nil)
        {
          [self setMenu: menu forWindow: keyWindow];
        }
    }
  else
    {
      NSLog(@"[GlobalMenuTheme] Skipping - not main menu or no registry. Main: %s, Registry: %@", 
            ([NSApp mainMenu] == menu) ? "YES" : "NO", menuRegistry);
    }
}

- (void)setMenu: (NSMenu*)m forWindow: (NSWindow*)w
{
  NSLog(@"[GlobalMenuTheme] setMenu:%@ forWindow:%@ called", [m title], w);
  NSLog(@"[GlobalMenuTheme] Menu has %ld items, registry: %@", 
        m ? [m numberOfItems] : -1, menuRegistry);
        
  if (nil != menuRegistry && m != nil && [m numberOfItems] > 0)
    {
      NSLog(@"[GlobalMenuTheme] Attempting to register menu '%@' with %ld items for window %@", 
            [m title], [m numberOfItems], w);
            
      @try 
        {
          [menuRegistry setMenu: m forWindow: w];
          NSLog(@"[GlobalMenuTheme] Successfully called setMenu:forWindow: on registry");
        }
      @catch (NSException *exception)
        {
          NSLog(@"[GlobalMenuTheme] ERROR calling setMenu:forWindow:: %@", exception);
        }
    }
  else if (nil == menuRegistry)
    {
      NSLog(@"[GlobalMenuTheme] No DBus menu registry available - falling back to normal menus");
      [super setMenu: m forWindow: w];
    }
  else
    {
      NSLog(@"[GlobalMenuTheme] Skipping menu registration - menu: %@, items: %ld", 
            m, m ? [m numberOfItems] : -1);
    }
}

// Only handle Windows95InterfaceStyle in updateAllWindowsWithMenu
- (void)updateAllWindowsWithMenu: (NSMenu*)menu
{
  NSInterfaceStyle style = NSInterfaceStyleForKey(@"NSMenuInterfaceStyle", nil);
  NSLog(@"[GlobalMenuTheme] updateAllWindowsWithMenu called with menu: %@ for style: %d", 
        [menu title], (int)style);
  
  if (style == NSWindows95InterfaceStyle)
    {
      // Handle Windows95 style - send to DBus AND do normal in-app embedding
      if (menu != nil && menuRegistry != nil)
        {
          NSWindow *keyWindow = [NSApp keyWindow];
          if (keyWindow != nil)
            {
              [self setMenu: menu forWindow: keyWindow];
            }
        }
      
      // Also do the normal Windows95 in-app embedding
      [super updateAllWindowsWithMenu: menu];
    }
  else
    {
      // For other styles, just do normal behavior
      [super updateAllWindowsWithMenu: menu];
    }
}

// Targeted override - only suppress Mac menu bar when using DBus
- (NSRect)modifyRect: (NSRect)rect forMenu: (NSMenu*)menu isHorizontal: (BOOL)horizontal
{
  NSInterfaceStyle style = NSInterfaceStyleForKey(@"NSMenuInterfaceStyle", nil);
  
  if (style == NSMacintoshInterfaceStyle && menuRegistry != nil && ([NSApp mainMenu] == menu))
    {
      NSLog(@"[GlobalMenuTheme] Suppressing Mac menu bar geometry for: %@", [menu title]);
      return NSZeroRect;  // Hide the Mac menu bar since we're using DBus
    }
  
  // For other cases, use default behavior
  return [super modifyRect: rect forMenu: menu isHorizontal: horizontal];
}

// Targeted override - only hide Mac menu bar when using DBus
- (BOOL)proposedVisibility: (BOOL)visibility forMenu: (NSMenu*)menu
{
  NSInterfaceStyle style = NSInterfaceStyleForKey(@"NSMenuInterfaceStyle", nil);
  
  if (style == NSMacintoshInterfaceStyle && menuRegistry != nil && ([NSApp mainMenu] == menu))
    {
      NSLog(@"[GlobalMenuTheme] Hiding Mac menu bar for: %@", [menu title]);
      return NO;  // Hide the Mac menu bar since we're using DBus
    }
  
  // For other menus (submenus, popups, etc.), use default behavior
  return [super proposedVisibility: visibility forMenu: menu];
}

@end
