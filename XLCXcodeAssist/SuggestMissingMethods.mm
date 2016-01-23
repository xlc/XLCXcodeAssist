//
//  SuggestMissingMethods.m
//  XLCXcodeAssist
//
//  Created by Xiliang Chen on 14/10/3.
//  Copyright (c) 2014年 Xiliang Chen. All rights reserved.
//

#import "SuggestMissingMethods.hh"

#import "XcodeHeaders.h"
#import "ClangHelpers.hh"
#import "DVTSourceModelItem+XLCAddition.h"
#import "XcodeHelpers.hh"

static DVTSourceModelItem *GetMethodDeclaratorItem(NSRange declRange, DVTTextDocumentLocation *declLoc, DVTTextStorage *headerText)
{
    __block DVTSourceModel *headerModel;
    dispatch_sync(dispatch_get_main_queue(), ^{
        headerModel = headerText.sourceModel;
    });
    DVTSourceModelItem *declItem = [headerModel enclosingItemAtLocation:declRange.location];
    return [declItem xlc_findMethodDeclaratorParent];
}

static NSString *GenerateMethodBody(NSRange declRange, DVTTextStorage *headerText, DVTSourceModelItem *declItem, NSString *declStr)
{
    NSString *returnType;
    for (DVTSourceModelItem *item in declItem.children) {
        if ([item xlc_isParenExpr]) {
            returnType = [[headerText.string substringWithRange:item.range] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            break;
        }
    }
    if (!returnType) {
        return nil;
    }
    
    NSString *returnStatement;
    NSString *realReturnType = [returnType stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"()"]];
    
    if ([realReturnType isEqualToString:@"void"]) {
        returnStatement = @"";
    } else if ([realReturnType hasSuffix:@"*"] || [realReturnType isEqualToString:@"id"] || [realReturnType isEqualToString:@"instancetype"]) {
        returnStatement = @"return <#nil#>;";
    } else {
        returnStatement = [NSString stringWithFormat:@"return <#%@#>;", returnType];
    }
    
    return [NSString stringWithFormat:@"%@\n{\n    %@\n}\n\n", declStr, returnStatement];
}

static NSString * GetDeclItemName(DVTSourceModelItem *declItem, NSString *bodyStr) {
    NSMutableString *str = [NSMutableString string];
    [declItem xlc_preOrderTraverse:^(DVTSourceModelItem *item, BOOL *stop) {
        if ([item xlc_isPartialName]) {
            [str appendString:[bodyStr substringWithRange:[item range]]];
        } else if ([item xlc_isMethodColon]) {
            [str appendString:@":"];
        }
    }];
    return str;
}

static BOOL IsMatchingItem(DVTSourceModelItem *declItem, DVTSourceModelItem *defItem, NSString *headerStr, NSString *bodyStr)
{
    DVTSourceModelItem *declItem2;
    for (DVTSourceModelItem *item in defItem.children) {
        if ([item xlc_isMethodDeclarator]) {
            declItem2 = item;
            break;
        }
    }
    if (!declItem2) {
        return NO;
    }
    
    if ([declItem xlc_IsClassMethodDeclarator] != [declItem2 xlc_IsClassMethodDeclarator]) {
        return NO;
    }
    
    return [GetDeclItemName(declItem, headerStr) isEqualToString:GetDeclItemName(declItem2, bodyStr)];
}

static DVTSourceModelItem *SearchAppropriateBodyItem(IDESourceCodeDocument *bodyDoc, DVTTextDocumentLocation *bodyLoc, DVTSourceModelItem *declItem, IDESourceCodeDocument *headerDoc)
{
    DVTTextStorage *bodyText = bodyDoc.textStorage;
    
    __block DVTSourceModel *bodyModel;
    dispatch_sync(dispatch_get_main_queue(), ^{
        bodyModel = bodyText.sourceModel;
    });
    
    NSRange bodyPosRange = bodyLoc.characterRange;
    
    DVTSourceModelItem *bodyItem = [bodyModel enclosingItemAtLocation:bodyPosRange.location + bodyPosRange.length];
    DVTSourceModelItem *bodyItem2 = bodyItem;
    while (![bodyItem xlc_isImplementation] && bodyItem) {
        bodyItem = bodyItem.parent;
    }
    if (!bodyItem) {
        // try again with siblings
        bodyItem = bodyItem2;
        while (![bodyItem xlc_isImplementation] && bodyItem) {
            for (DVTSourceModelItem *sibling in bodyItem.parent.children) {
                if ([sibling xlc_isEndToken]) {
                    return sibling;
                }
            }
            bodyItem = bodyItem.parent;
        }
    }
    
    if (!bodyItem) {
        return nil;
    }
    
    BOOL before = YES;
    DVTSourceModelItem *prevDeclItem;
    DVTSourceModelItem *nextDeclItem;
    
    for (DVTSourceModelItem *item in declItem.parent.parent.children) {
        DVTSourceModelItem *item2 = item.children.count ? item.children[0] : nil;
        if (item2 == declItem) {
            before = NO;
            continue;
        }
        if ([item2 xlc_isMethodDeclarator]) {
            if (before) {
                prevDeclItem = item2;
            } else {
                nextDeclItem = item2;
                break;
            }
        }
    }
    
    DVTSourceModelItem *prevItem = [bodyItem.children lastObject];
    DVTSourceModelItem *beforeNextItem = nil;
    NSString *headerStr = headerDoc.textStorage.string;
    NSString *bodyStr = bodyDoc.textStorage.string;
    for (DVTSourceModelItem *item in bodyItem.children) {
        if (IsMatchingItem(prevDeclItem, item, headerStr, bodyStr)) {
            return [item nextItem];
        }
        if (IsMatchingItem(nextDeclItem, item, headerStr, bodyStr)) {
            beforeNextItem = [prevItem nextItem];
        }
        prevItem = item;
    }
    
    return beforeNextItem ?: [bodyItem.children lastObject];
}

static BOOL XLCHandleMethodDefinitionNotFoundMessage(IDEDiagnosticActivityLogMessage *message, IDEDiagnosticActivityLogMessage *submsg)
{
    DVTTextDocumentLocation *bodyLoc = message.location;
    DVTTextDocumentLocation *declLoc = submsg.location;
    
    IDESourceCodeDocument *headerDoc = XLCGetSourceCodeDocument(declLoc, @"public.c-header");
    IDESourceCodeDocument *bodyDoc = XLCGetSourceCodeDocument(bodyLoc, @"public.c-header");
    
    if (!headerDoc || !bodyDoc) {
        return NO;
    }
    
    DVTTextStorage *headerText = headerDoc.textStorage;
    
    __block NSRange declRange;
    dispatch_sync(dispatch_get_main_queue(), ^{
        declRange = [headerText methodDefinitionRangeAtIndex:declLoc.characterRange.location];
    });
    if (declRange.location == NSNotFound) {
        return NO;
    }
    
    DVTSourceModelItem *declItem = GetMethodDeclaratorItem(declRange, declLoc, headerText);
    if (!declItem) {
        return NO;
    }
    
    NSString *declStr = [headerText.string substringWithRange:declRange];
    
    NSString *str = GenerateMethodBody(declRange, headerText, declItem, declStr);
    if (!str) {
        return NO;
    }
    
    DVTSourceModelItem *bodyItem = SearchAppropriateBodyItem(bodyDoc, bodyLoc, declItem, headerDoc);
    if (!bodyItem) {
        return NO;
    }
    
    NSRange replaceRange = {NSNotFound, 0};
    
    replaceRange.location = bodyItem.range.location;
    
    DVTTextDocumentLocation *replaceLocation = [[DVTTextDocumentLocation alloc] initWithDocumentURL:bodyLoc.documentURL timestamp:bodyLoc.timestamp characterRange:replaceRange];
    
    IDEDiagnosticFixItItem * item = [[IDEDiagnosticFixItItem alloc] initWithFixItString:str replacementLocation:replaceLocation];
    
    item.diagnosticItem = message;
    [message.mutableDiagnosticFixItItems addObject:item];
    
    return YES;
}

void XLCSuggestMissingMethods(IDEDiagnosticActivityLogMessage *message)
{
    static NSRegularExpression *messageRegex;
    static NSRegularExpression *protocolMessageRegex;
    static NSRegularExpression *subMessageRegex;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        messageRegex = [NSRegularExpression regularExpressionWithPattern:@"Method definition for '(.*)' not found" options:0 error:NULL];
        protocolMessageRegex = [NSRegularExpression regularExpressionWithPattern:@"Method '(.*)' in protocol '(.*)' not implemented" options:0 error:NULL];
        subMessageRegex = [NSRegularExpression regularExpressionWithPattern:@"Method '.*' declared here" options:0 error:NULL];
    });
    
    NSString *title = message.title;
    
    BOOL found = NO;
    NSTextCheckingResult *result = [messageRegex firstMatchInString:title options:0 range:NSMakeRange(0, title.length)];
    found = result && [result range].location != NSNotFound;
    if (!found) {
        result = [protocolMessageRegex firstMatchInString:title options:0 range:NSMakeRange(0, title.length)];
        found = result && [result range].location != NSNotFound;
    }
    if (found) {
        for (IDEDiagnosticActivityLogMessage *submsg in message.submessages) {
            NSString *title = submsg.title;
            if ([subMessageRegex rangeOfFirstMatchInString:title options:0 range:NSMakeRange(0, title.length)].location != NSNotFound) {
                if (XLCHandleMethodDefinitionNotFoundMessage(message, submsg)) {
                    break;
                }
            }
        }
    }
}