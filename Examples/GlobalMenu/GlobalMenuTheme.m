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
    }
  else
    {
      NSLog(@"[GlobalMenuTheme] ERROR: Super init failed!");
    }
  return self;
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

- (void)updateAllWindowsWithMenu: (NSMenu*)menu
{
  NSLog(@"[GlobalMenuTheme] updateAllWindowsWithMenu called with menu: %@", [menu title]);
  
  // Send to DBus but DON'T call super - this prevents Mac menubar display
  if (menu != nil && menuRegistry != nil)
    {
      NSWindow *keyWindow = [NSApp keyWindow];
      NSLog(@"[GlobalMenuTheme] Registering with key window: %@", keyWindow);
      if (keyWindow != nil)
        {
          [self setMenu: menu forWindow: keyWindow];
        }
    }
  
  // IMPORTANT: DON'T call [super updateAllWindowsWithMenu: menu]
  // This prevents the Mac menubar from being displayed
}

// Override to prevent Mac menubar geometry setup
- (NSRect)modifyRect: (NSRect)rect forMenu: (NSMenu*)menu isHorizontal: (BOOL)horizontal
{
  NSLog(@"[GlobalMenuTheme] Suppressing menu geometry for: %@", [menu title]);
  // Return zero rect to prevent menu display
  return NSZeroRect;
}

// Override to always hide menus
- (BOOL)proposedVisibility: (BOOL)visibility forMenu: (NSMenu*)menu
{
  NSLog(@"[GlobalMenuTheme] Suppressing visibility for menu: %@", [menu title]);
  // Always return NO to hide all menus
  return NO;
}

@end
