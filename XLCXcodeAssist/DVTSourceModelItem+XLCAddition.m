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

- (BOOL)xlc_IsClassMethodDeclarator
{
    return [[self xlc_tokenString] hasSuffix:@".classmethod.declarator'"];
}

- (BOOL)xlc_isMethodDeclarator
{
    NSString *token = [self xlc_tokenString];
    return [token hasSuffix:@".method.declarator'"] || [token hasSuffix:@".classmethod.declarator'"];
}

- (BOOL)xlc_isMethodDefinition
{
    NSString *token = [self xlc_tokenString];
    return [token hasSuffix:@".method.definition'"];
}

- (BOOL)xlc_isImplementation
{
    return [[self xlc_tokenString] hasSuffix:@".implementation'"];
}

- (BOOL)xlc_isEndToken
{
    return [[self xlc_tokenString] hasSuffix:@"@end'"];
}

- (BOOL)xlc_isPartialName
{
    return [[self xlc_tokenString] hasSuffix:@".partialname'"];
}

- (BOOL)xlc_isMethodColon
{
    return [[self xlc_tokenString] hasSuffix:@".method.colon'"];
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

- (BOOL)xlc_preOrderTraverse:(void (^)(DVTSourceModelItem *item, BOOL *stop))block
{
    if (!block) {
        return NO;
    }
    BOOL stop = NO;
    block(self, &stop);
    if (stop) {
        return NO;
    }
    for (DVTSourceModelItem *item in self.children) {
        if (![item xlc_preOrderTraverse:block]) {
            return NO;
        }
    }
    return YES;
}

@end
