XLCXcodeAssist
==============

Xcode plug-in to provide some handy features:

- Suggest implementation for missing Objective-C methods

![method](https://raw.githubusercontent.com/xlc/XLCXcodeAssist/master/images/method.png)

- Suggest missing switch case statements

![switch](https://raw.githubusercontent.com/xlc/XLCXcodeAssist/master/images/switch.png)

- Smarter `⌘`+`←` and `⌘` + `⇧` + `←`
	- Move/Select cursor to position before first non-white space character instead of very beginning of the line

## Requirements

Xcode 5.1.1 

## Install

Clone and build the project, then restart Xcode.

## Uninstall

Run `rm -r ~/Library/Application\ Support/Developer/Shared/Xcode/Plug-ins/XLCXcodeAssist.xcplugin/`
