//
//  DVTSourceModelItem+XLCAddition.m
//  XLCXcodeAssist
//
//  Created by Xiliang Chen on 14/9/17.
//  Copyright (c) 2014年 Xiliang Chen. All rights reserved.
//

#import "DVTSourceModelItem+XLCAddition.h"

#import <dlfcn.h>

@implementation DVTSourceModelItem (XLCAddition)

- (NSString *)xlc_tokenString
{
    static id (*tokenStringFunc)(long long);
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        tokenStringFunc = (id (*)(long long))dlsym(RTLD_DEFAULT, "_tokenString");
    });
    
    return tokenStringFunc ? tokenStringFunc(self.token) : nil;
}

- (BOOL)xlc_isParenExpr
{
    return [[self xlc_tokenString] hasSuffix:@".parenexpr'"];
}

- (BOOL)xlc_isBlock
{
    return [[self xlc_tokenString] hasSuffix:@".block'"];
}

- (BOOL)xlc_isMethodDeclarator
{
    NSString *token = [self xlc_tokenString];
    return [token hasSuffix:@".method.declarator'"] || [token hasSuffix:@".classmethod.declarator'"];
}

- (BOOL)xlc_isImplementation
{
    return [[self xlc_tokenString] hasSuffix:@".implementation'"];
}

- (BOOL)xlc_isEndToken
{
    return [[self xlc_tokenString] hasSuffix:@"@end'"];
}

- (DVTSourceModelItem *)xlc_findMethodDeclaratorParent
{
    DVTSourceModelItem *item = self;
    while (item && ![item xlc_isMethodDeclarator]) {
        item = item.parent;
    };
    return item;
}

- (DVTSourceModelItem *)xlc_findBlockParent
{
    DVTSourceModelItem *item = self;
    while (item && ![item xlc_isBlock]) {
        item = item.parent;
    };
    return item;
}

- (DVTSourceModelItem *)xlc_searchSwitchChildAfterLocation:(NSUInteger)loc
{
    BOOL foundSwitchItem = NO;
    DVTSourceModelItem *switchBlockItem;
    for (DVTSourceModelItem *item in self.children) {
        if (foundSwitchItem) {
            if ([item xlc_isBlock]) {
                if (item.range.location >= loc) {
                    switchBlockItem = item;
                    break;
                } else {
                    foundSwitchItem = NO;
                }
            }
        }
        if ([[item xlc_tokenString] isEqualToString:@"'switch'"]) {
            foundSwitchItem = YES;
        }
    }
    return switchBlockItem;
}

@end
