#include <stdlib.h>
#include <stdio.h>
#include <pthread.h>
#include <AvailabilityMacros.h>

#include <map>
#include <vector>
#include <iostream>


#include "common/accessibility/display.h"
#include "common/accessibility/application.h"
#include "common/accessibility/window.h"
#include "common/accessibility/element.h"
#include "common/accessibility/observer.h"
#include "common/dispatch/cgeventtap.h"
#include "common/config/tokenize.h"
#include "common/ipc/daemon.h"
#include "common/misc/carbon.h"
#include "common/misc/workspace.h"
#include "common/misc/assert.h"
#include "common/border/border.h"

#include "common/accessibility/display.mm"
#include "common/accessibility/application.cpp"
#include "common/accessibility/window.cpp"
#include "common/accessibility/element.cpp"
#include "common/accessibility/observer.cpp"
#include "common/dispatch/cgeventtap.cpp"
#include "common/config/tokenize.cpp"
#include "common/ipc/daemon.cpp"
#include "common/misc/carbon.cpp"
#include "common/misc/workspace.mm"
#include "common/border/border.mm"

#include "accessibility.h"
#include "args.h"

#define internal static
#define local_persist static

using namespace std;

typedef std::map<pid_t, macos_application *> macos_application_map;
typedef macos_application_map::iterator macos_application_map_it;

typedef std::map<uint32_t, macos_window *> macos_window_map;
typedef macos_window_map::iterator macos_window_map_it;


internal macos_application_map Applications;
internal macos_window_map Windows;
internal pthread_mutex_t WindowsLock;

macos_window_map CopyWindowCache()
{
    pthread_mutex_lock(&WindowsLock);
    macos_window_map Copy = Windows;
    pthread_mutex_unlock(&WindowsLock);
    return Copy;
}

/*
 * NOTE(koekeishiya): We need a way to retrieve AXUIElementRef from a CGWindowID.
 * There is no way to do this, without caching AXUIElementRef references.
 * Here we perform a lookup of macos_window structs.
 */
internal inline macos_window *
_GetWindowByID(uint32_t Id)
{
    macos_window_map_it It = Windows.find(Id);
    return It != Windows.end() ? It->second : NULL;
}

macos_window *GetWindowByID(uint32_t Id)
{
    pthread_mutex_lock(&WindowsLock);
    macos_window *Result = _GetWindowByID(Id);
    pthread_mutex_unlock(&WindowsLock);
    return Result;
}

internal AXUIElementRef
GetFocusedWindow()
{
    AXUIElementRef ApplicationRef = NULL, WindowRef = NULL;
    ApplicationRef = AXLibGetFocusedApplication();
    if (!ApplicationRef) goto out;

    WindowRef = AXLibGetFocusedWindow(ApplicationRef);
    if (!WindowRef) goto err;

err:
    CFRelease(ApplicationRef);

out:
    return WindowRef;
}

struct wmctrl_app {
	static const char* help() {
		return "Program allows for controlling the focused window.";
	}
	std::string direction;

	wmctrl_app() {}

	template<class F>
	void parse(F f) {
		f(direction, "--direction", "-d", args::help("direction to move or move focus or resize"), args::required());
	}

	void run() {
		if (!CheckAccessibilityPrivileges())  {
			cout << "CheckAccessibilityPrivileges failed" << endl;
		}

		NSApplicationLoad();
		AXUIElementSetMessagingTimeout(SystemWideElement(), 1.0);
		AXUIElementRef w = GetFocusedWindow(); 
		cout << w << endl;
		cout << AXLibGetWindowTitle(w) << endl;

		CGPoint wPos = AXLibGetWindowPosition(w);
		CGSize wSize = AXLibGetWindowSize(w);

		CFStringRef DisplayRef = AXLibGetDisplayIdentifierFromWindowRect(wPos, wSize);
		ASSERT(DisplayRef);
		CGRect displayBounds = AXLibGetDisplayBounds(DisplayRef);

		cout << wPos.x << endl;
		cout << wPos.y << endl;
		cout << wSize.width << endl;
		cout << wSize.height << endl;
		cout << displayBounds.origin.x << endl;
		cout << displayBounds.origin.y << endl;
		cout << displayBounds.size.width << endl;
		cout << displayBounds.size.height << endl;
	}
};

int main(int argc, const char* argv[]) {
  args::parse<wmctrl_app>(argc, argv);
}
