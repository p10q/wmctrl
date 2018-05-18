#include <stdlib.h>
#include <stdio.h>
#include <pthread.h>
#include <AvailabilityMacros.h>

#include <map>
#include <vector>
#include <iostream>
#include <cmath>


#include "common/accessibility/display.h"
#include "common/accessibility/application.h"
#include "common/accessibility/window.h"
#include "common/accessibility/element.h"
#include "common/accessibility/observer.h"
#include "common/dispatch/cgeventtap.h"
#include "common/config/tokenize.h"
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
#include "common/misc/carbon.cpp"
#include "common/misc/workspace.mm"
#include "common/border/border.mm"

#include "accessibility.h"
#include "args.h"

#define internal static
#define local_persist static

using namespace std;

static AXUIElementRef GetFocusedWindow() {
    AXUIElementRef applicationRef = AXLibGetFocusedApplication();
    if (!applicationRef)  {
      return NULL;
    }

    AXUIElementRef windowRef = AXLibGetFocusedWindow(applicationRef);
    if (!windowRef) {
      CFRelease(applicationRef);
      return NULL;
    }

    CFRelease(applicationRef);
    return windowRef;
}

static int GridCount = 12;
 
int getClampedLeftX(int x, int w) { return max(0, x); }
int getClampedRightX(int x, int w) { return min(x, GridCount - w); }
int getClampedTopY(int y, int h) { return max(0, y); }
int getClampedBottomY(int y, int h) { return min(y, GridCount - h); }

int getClampedX(int x, int w) { return getClampedLeftX(getClampedRightX(x, w), w); }
int getClampedY(int y, int h) { return getClampedTopY(getClampedBottomY(y, h), h); }

int getClampedMinW(int x, int w) { return max(1, w); }
int getClampedMinH(int y, int h) { return max(1, h); }
int getClampedMaxW(int x, int w) { return min(GridCount - x, w); }
int getClampedMaxH(int y, int h) { return min(GridCount - y, h); }

int getClampedW(int x, int w) { return getClampedMinW(x, getClampedMaxW(x, w)); }
int getClampedH(int y, int h) { return getClampedMinH(y, getClampedMaxH(y, h)); }

struct wmctrl_win_grid_info {
  int x, y, w, h;

  void setDisplayRect(CGRect rect, CGSize displayPixels) {
    int displayUnitX = displayPixels.width/GridCount;
    int displayUnitY = displayPixels.height/GridCount;
    x = (rect.origin.x + displayUnitX/2) / displayUnitX;
    y = (rect.origin.y + displayUnitY/2) / displayUnitY;
    w = (rect.size.width + displayUnitX/2) / displayUnitX;
    h = (rect.size.height + displayUnitY/2) / displayUnitY;
  }

  CGRect getDisplayRect(CGSize displayPixels) {
    int displayUnitX = displayPixels.width/GridCount;
    int displayUnitY = displayPixels.height/GridCount;
    CGRect out;
    out.origin.x = x * displayUnitX;
    out.origin.y = y * displayUnitY;
    out.size.width = w * displayUnitX;
    out.size.height = h * displayUnitY;
    return out;
  }


  void growFromLeftSide(int length) { int prevx = x; x = getClampedX(x - length, w); w += fabs(x - prevx); }
  void growFromRightSide(int length) { w = getClampedW(x, w + length); }
  void growFromTopSide(int length) { int prevy = y; y = getClampedY(y - length, h); h += fabs(y - prevy); }
  void growFromBottomSide(int length) { h = getClampedH(y, h + length); }

  void shrinkFromLeftSide(int length) { int prevx = x; x = getClampedX(x + length, w - length); w -= (x - prevx); }
  void shrinkFromRightSide(int length) { w = getClampedW(x, w - length); }
  void shrinkFromTopSide(int length) { int prevy = y; y = getClampedY(y + length, h - length); h -= (y - prevy); }
  void shrinkFromBottomSide(int length) { h = getClampedH(y + length, h - length); }

  bool atLeftWall() { return x == 0; }
  bool atRightWall() { return x+w == GridCount; }
  bool atTopWall() { return y == 0; }
  bool atBottomWall() { return y+h == GridCount; }

  void expandFullWidth() { x = 0; w = GridCount; }
  void expandFullHeight() { y = 0; h = GridCount; }
  
  void setLeftHalf() { x = 0; w = GridCount / 2; y = 0; h = GridCount; }
  void setRightHalf() { x = GridCount / 2; w = GridCount / 2; y = 0; h = GridCount; }
  
  void setTopHalf() { x = 0; w = GridCount; y = 0; h = GridCount / 2; }
  void setBottomHalf() { x = 0; w = GridCount; y = GridCount / 2; h = GridCount / 2; }

  void handleResizeLeft(int length) {
    if (atLeftWall() && atRightWall()) {
      shrinkFromRightSide(max(length / 2, 1));
    } else {
      setLeftHalf(); 
    }
  }
  void handleResizeRight(int length) {
    if (atLeftWall() && atRightWall()) {
      shrinkFromLeftSide(max(length / 2, 1));
    } else {
      setRightHalf(); 
    }
  }
  void handleResizeTop(int length) {
    if (atTopWall() && atBottomWall()) {
      shrinkFromBottomSide(max(length / 2, 1));
    } else {
      setTopHalf(); 
    }
  } 
  void handleResizeBottom(int length) {
    if (atTopWall() && atBottomWall()) {
      shrinkFromTopSide(max(length / 2, 1));
    } else {
      setBottomHalf(); 
    }
  }
};

struct wmctrl_app {
	static const char* help() {
		return "Program allows for controlling the focused window.";
	}
	char direction; // n (north), e (east), s (south), w (west), f (full)

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
		AXUIElementRef win = GetFocusedWindow();
		CGPoint wPos = AXLibGetWindowPosition(win);
		CGSize wSize = AXLibGetWindowSize(win);
    CGRect displayBounds = GetDisplayBoundsFor(win);
    
    wmctrl_win_grid_info gridInfo;
    gridInfo.setDisplayRect(CGRectMake(wPos.x, wPos.y, wSize.width, wSize.height), displayBounds.size);
    switch (direction) {
      case 'n': gridInfo.handleResizeTop(max(gridInfo.h, 1)); break;
      case 'e': gridInfo.handleResizeRight(max(gridInfo.w, 1)); break;
      case 's': gridInfo.handleResizeBottom(max(gridInfo.h, 1)); break;
      case 'w': gridInfo.handleResizeLeft(max(gridInfo.w, 1)); break;
      case 'f': gridInfo = {0, 0, GridCount, GridCount}; break;
    }
    CGRect dest = gridInfo.getDisplayRect(displayBounds.size);
    AXLibSetWindowPosition(win, dest.origin.x, dest.origin.y);
    AXLibSetWindowSize(win, dest.size.width, dest.size.height);
	}


  //
  // Display bounds overall of entire screen
  //
  CGRect GetDisplayBoundsFor(AXUIElementRef win) {
		CGPoint wPos = AXLibGetWindowPosition(win);
		CGSize wSize = AXLibGetWindowSize(win);
		CFStringRef DisplayRef = AXLibGetDisplayIdentifierFromWindowRect(wPos, wSize);
		CGRect bounds = AXLibGetDisplayBounds(DisplayRef);
    return bounds;
  }
};

int main(int argc, const char* argv[]) {
  args::parse<wmctrl_app>(argc, argv);
}
