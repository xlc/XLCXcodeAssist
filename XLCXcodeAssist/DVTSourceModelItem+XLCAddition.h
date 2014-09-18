//
//  DVTSourceModelItem+XLCAddition.h
//  XLCXcodeAssist
//
//  Created by Xiliang Chen on 14/9/17.
//  Copyright (c) 2014年 Xiliang Chen. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "XcodeHeaders.h"

@interface DVTSourceModelItem (XLCAddition)

- (NSString *)xlc_tokenString;
- (BOOL)xlc_isParenExpr;
- (BOOL)xlc_isBlock;
- (BOOL)xlc_isMethodDeclarator;
- (BOOL)xlc_isImplementation;
- (BOOL)xlc_isEndToken;

- (DVTSourceModelItem *)xlc_findMethodDeclaratorParent;
- (DVTSourceModelItem *)xlc_findBlockParent;

- (DVTSourceModelItem *)xlc_searchSwitchChildAfterLocation:(NSUInteger)loc;

@end
