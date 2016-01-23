//
//  XcodeHelpers.h
//  XLCXcodeAssist
//
//  Created by Xiliang Chen on 16/1/17.
//  Copyright © 2016年 Xiliang Chen. All rights reserved.
//

#import <Foundation/Foundation.h>

@class IDESourceCodeDocument;
@class DVTTextDocumentLocation;

IDESourceCodeDocument *XLCGetSourceCodeDocument(DVTTextDocumentLocation *loc, NSString *type);