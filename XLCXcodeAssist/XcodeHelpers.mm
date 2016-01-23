//
//  XcodeHelpers.m
//  XLCXcodeAssist
//
//  Created by Xiliang Chen on 16/1/17.
//  Copyright © 2016年 Xiliang Chen. All rights reserved.
//

#import "XcodeHelpers.hh"

#import "XcodeHeaders.h"
#import "ClangHelpers.hh"
#import "DVTSourceModelItem+XLCAddition.h"

IDESourceCodeDocument *XLCGetSourceCodeDocument(DVTTextDocumentLocation *loc, NSString *type) {
    IDESourceCodeDocument *doc = [[IDEDocumentController sharedDocumentController] documentForURL:loc.documentURL];
    if (!doc) {
        NSError *err;
        doc = [[NSClassFromString(@"IDESourceCodeDocument") alloc] initWithContentsOfURL:loc.documentURL ofType:type error:&err];
        if (err) {
            NSLog(@"Failed to load document at URL: %@ with error: %@", loc.documentURL, err);
        }
    }
    return doc;
}