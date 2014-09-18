//
//  XLCXcodeAssist.m
//  XLCXcodeAssist
//
//  Created by Xiliang Chen on 14-5-12.
//  Copyright (c) 2014年 Xiliang Chen. All rights reserved.
//

#import "XLCXcodeAssist.h"

#include <deque>
#include <utility>
#include <memory>
#include <functional>

#import <objc/runtime.h>

#import "XcodeHeaders.h"
#import "ClangHelpers.hh"
#import "DVTSourceModelItem+XLCAddition.h"

@interface XLCXcodeAssist ()

- (void)installDiagnosticsHelper;
- (void)installSourceTextViewHelper;

- (void)processMethodDefinitionNotFoundMessage:(IDEDiagnosticActivityLogMessage *)message;
- (void)processSwitchCaseMessage:(IDEDiagnosticActivityLogMessage *)message withIndex:(IDEIndex *)index queryProvider:(IDEIndexClangQueryProvider *)provider;

- (NSRange)rangeOfBeginningOfLineAtRange:(NSRange)range view:(DVTSourceTextView *)view;

@end

@implementation XLCXcodeAssist

+ (void)pluginDidLoad:(NSBundle *)plugin
{
    if ([self shouldLoadPlugin]) {
        [self sharedPlugin];
    }
}

+ (instancetype)sharedPlugin
{
    static id sharedPlugin = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sharedPlugin = [[self alloc] init];
	});
    
    return sharedPlugin;
}

+ (BOOL)shouldLoadPlugin
{
    NSString *bundleIdentifier = [[NSBundle mainBundle] bundleIdentifier];
    
    return bundleIdentifier && [bundleIdentifier caseInsensitiveCompare:@"com.apple.dt.Xcode"] == NSOrderedSame;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self installDiagnosticsHelper];
        [self installSourceTextViewHelper];
    }
    
    return self;
}

#pragma mark -

- (void)installDiagnosticsHelper
{
    SEL sel = sel_getUid("codeDiagnosticsAtLocation:withCurrentFileContentDictionary:forIndex:");
    Class IDEIndexClangQueryProviderClass = NSClassFromString(@"IDEIndexClangQueryProvider");
    
    Method method = class_getInstanceMethod(IDEIndexClangQueryProviderClass, sel);
    IMP originalImp = method_getImplementation(method);
    
    IMP imp = imp_implementationWithBlock(^id(id me, id loc, id dict, IDEIndex *idx) {
        id ret = ((id (*)(id,SEL,id,id,id))originalImp)(me, sel, loc, dict, idx);
        
        try {
            @try {
                for (IDEDiagnosticActivityLogMessage * message in ret) {
                    [self processMethodDefinitionNotFoundMessage:message];
                    [self processSwitchCaseMessage:message withIndex:idx queryProvider:me];
                }
            }
            @catch (id exception) {
                // something wrong... but I don't want to crash Xcode
                NSLog(@"%s:%d - %@", __PRETTY_FUNCTION__, __LINE__, exception);
            }
        }
        catch(std::exception &e) {
            NSLog(@"%s:%d - %s", __PRETTY_FUNCTION__, __LINE__, e.what());
        }
        catch (...) {
            NSLog(@"%s:%d - unknown exception", __PRETTY_FUNCTION__, __LINE__);
        }
        
        return ret;
    });
    
    method_setImplementation(method, imp);
}

- (void)processMethodDefinitionNotFoundMessage:(IDEDiagnosticActivityLogMessage *)message
{

    static NSRegularExpression *messageRegex;
    static NSRegularExpression *subMessageRegex;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        messageRegex = [NSRegularExpression regularExpressionWithPattern:@"Method definition for '(.*)' not found" options:0 error:NULL];
        subMessageRegex = [NSRegularExpression regularExpressionWithPattern:@"Method '.*' declared here" options:0 error:NULL];
    });
    
    NSString *title = message.title;
    
    NSTextCheckingResult *result = [messageRegex firstMatchInString:title options:0 range:NSMakeRange(0, title.length)];
    if (result && [result range].location != NSNotFound) {
        // found
        
        //NSString *selname = [title substringWithRange:[result rangeAtIndex:1]];
        DVTTextDocumentLocation *bodyLoc = message.location;
        
        for (IDEDiagnosticActivityLogMessage *submsg in message.submessages) {
            NSString *title = submsg.title;
            if ([subMessageRegex rangeOfFirstMatchInString:title options:0 range:NSMakeRange(0, title.length)].location != NSNotFound) {
                DVTTextDocumentLocation * declLoc = submsg.location;
                
                IDESourceCodeDocument *headerDoc = [[IDEDocumentController sharedDocumentController] documentForURL:declLoc.documentURL];
                IDESourceCodeDocument *bodyDoc = [[IDEDocumentController sharedDocumentController] documentForURL:bodyLoc.documentURL];
                
                if (!headerDoc || !bodyDoc) {
                    continue;
                }
                
                DVTTextStorage *headerText = headerDoc.textStorage;
                DVTTextStorage *bodyText = bodyDoc.textStorage;
                
                NSRange declRange = [headerText methodDefinitionRangeAtIndex:declLoc.characterRange.location];
                if (declRange.location == NSNotFound) {
                    continue;
                }
                NSString *declStr = [headerText.string substringWithRange:declRange];
                
                __block DVTSourceModel *headerModel;
                dispatch_sync(dispatch_get_main_queue(), ^{
                    headerModel = headerText.sourceModel;
                });
                DVTSourceModelItem *declItem = [headerModel enclosingItemAtLocation:declRange.location];
                declItem = [declItem xlc_findMethodDeclaratorParent];
                if (!declItem) {
                    continue;
                }
                
                NSString *returnType;
                for (DVTSourceModelItem *item in declItem.children) {
                    if ([item xlc_isParenExpr]) {
                        returnType = [[headerText.string substringWithRange:item.range] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                        break;
                    }
                }
                if (!returnType) {
                    continue;
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
                
                NSString *str = [NSString stringWithFormat:@"%@\n{\n    %@\n}\n\n", declStr, returnStatement];
                NSRange bodyPosRange = bodyLoc.characterRange;
                
                __block DVTSourceModel *bodyModel;
                dispatch_sync(dispatch_get_main_queue(), ^{
                    bodyModel = bodyText.sourceModel;
                });
                
                
                DVTSourceModelItem *bodyItem = (^DVTSourceModelItem *{
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
                    return [bodyItem.children lastObject];
                })();
                if (!bodyItem) {
                    continue;
                }
                
                NSRange replaceRange = {NSNotFound, 0};
                
                replaceRange.location = bodyItem.range.location;
                
                DVTTextDocumentLocation *replaceLocation = [[DVTTextDocumentLocation alloc] initWithDocumentURL:bodyLoc.documentURL timestamp:bodyLoc.timestamp characterRange:replaceRange];
                
                IDEDiagnosticFixItItem * item = [[IDEDiagnosticFixItItem alloc] initWithFixItString:str replacementLocation:replaceLocation];
                
                item.diagnosticItem = message;
                [message.mutableDiagnosticFixItItems addObject:item];
                
                break;
            }
        }
    }
}

- (void)processSwitchCaseMessage:(IDEDiagnosticActivityLogMessage *)message withIndex:(IDEIndex *)index queryProvider:(IDEIndexClangQueryProvider *)provider
{
    static NSRegularExpression *messageRegex;
    static NSRegularExpression *messageRegex2;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        messageRegex = [NSRegularExpression regularExpressionWithPattern:@".* enumeration values not handled in switch:(.*)" options:0 error:NULL];
        messageRegex2 = [NSRegularExpression regularExpressionWithPattern:@"Enumeration values? ('.*') not handled in switch" options:0 error:NULL];
    });

    NSString *title = message.title;
    
    BOOL found = NO;
    
    NSTextCheckingResult *result = [messageRegex firstMatchInString:title options:0 range:NSMakeRange(0, title.length)];
    if (result && [result range].location != NSNotFound) {
        found = YES;
    } else {
        result = [messageRegex2 firstMatchInString:title options:0 range:NSMakeRange(0, title.length)];
        if (result && [result range].location != NSNotFound) {
            found = YES;
        }
    }
    if (found) {
        DVTTextDocumentLocation *loc = message.location;
        IDESourceCodeDocument *doc = [[IDEDocumentController sharedDocumentController] documentForURL:loc.documentURL];
        DVTTextStorage *textStorage = doc.textStorage;
        __block DVTSourceModel *model;
        dispatch_sync(dispatch_get_main_queue(), ^{
            model = textStorage.sourceModel;
        });
        
        DVTSourceModelItem *blockItem = [model enclosingItemAtLocation:loc.characterRange.location];
        blockItem = [blockItem xlc_findBlockParent];
        if (!blockItem) {
            return;
        }
        
        DVTSourceModelItem *switchBlockItem = [blockItem xlc_searchSwitchChildAfterLocation:loc.characterRange.location];
        if (!switchBlockItem) {
            return;
        }
        
        NSMutableArray *valuesArr = [NSMutableArray array];
        
        [provider performClang:^{
            CXTranslationUnit tu = provider->_cxTU;
            CXFile file = clang_getFile(tu, [[loc.documentURL path] UTF8String]);
            CXSourceLocation sloc = clang_getLocationForOffset(tu, file, (unsigned int)loc.characterRange.location);
            CXCursor currentCursor = clang_getCursor(tu, sloc);
            
            using Node = xlc::clang::Node;
            
            NSMutableArray *existingValeusArray = [NSMutableArray array];
            CXCursor switchExprCursor;
            
            {
                std::shared_ptr<Node> root;
                auto currentCursorNode = xlc::clang::buildCursorTreeAndFind(currentCursor, true, root);
                
                while (currentCursorNode && clang_getCursorKind(currentCursorNode->cursor) != CXCursor_SwitchStmt) {
                    currentCursorNode = currentCursorNode->parent.lock();
                }
                
                if (!currentCursorNode) {
                    return;
                }
                
                if (currentCursorNode->children.size() < 2) {
                    return;
                }
                
                if (currentCursorNode->children[0]->children.size() < 1) {
                    return;
                }
                
                switchExprCursor = clang_getCanonicalCursor(currentCursorNode->children[0]->children[0]->cursor);
                if (clang_isInvalid(clang_getCursorKind(switchExprCursor))) {
                    return;
                }
                
                auto compoundStmtNode = currentCursorNode->children[1];
                for (auto &castStmtNode : compoundStmtNode->children) {
                    if (clang_getCursorKind(castStmtNode->cursor) == CXCursor_CaseStmt) {
                        if (castStmtNode->children.empty()) {
                            continue;
                        }
                        auto exprNode = castStmtNode->children[0];
                        NSString *val = NSStringFromCXString(clang_getCursorSpelling(exprNode->cursor));
                        [existingValeusArray addObject:val];
                    }
                }
            }
            
            CXType switchExprType = clang_getCursorType(switchExprCursor);
            
            CXCursor declCursor = clang_getCursorDefinition(clang_getTypeDeclaration(switchExprType));
            if (clang_Cursor_isNull(declCursor)) {
                return;
            }
            {
                std::shared_ptr<Node> root;
                auto currentCursorNode = xlc::clang::buildCursorTreeAndFind(declCursor, false, root);
                
                while (currentCursorNode && currentCursorNode->cursor.kind != CXCursor_EnumDecl) {
                    if (currentCursorNode->cursor.kind == CXCursor_TypeRef) {
                        currentCursorNode = root->search(clang_getCursorDefinition(currentCursorNode->cursor));
                    } else if (!currentCursorNode->children.empty()) {
                        currentCursorNode = currentCursorNode->children[0];
                    } else {
                        currentCursorNode = nullptr;
                    }
                }
                
                if (!currentCursorNode) {
                    return;
                }
                
                for (auto &child : currentCursorNode->children) {
                    NSString *val = child->cursorSpelling();
                    if (![existingValeusArray containsObject:val]) {
                        [valuesArr addObject:val];
                    }
                }
            }
            
        }];
        
        if ([valuesArr count] == 0) {
            return;
        }
        
        NSRange replaceRange = switchBlockItem.range;
        replaceRange.location += replaceRange.length - 1;
        replaceRange.length = 0;
        
        NSMutableString *fixStr = [NSMutableString string];
        NSUInteger indent = [model indentForItem:switchBlockItem];
        NSUInteger indentWidth = textStorage.indentWidth;
//        NSString *indentStr = [NSString stringWithFormat:@"%*s", (int)indent, ""];
        NSString *indentStr2 = [NSString stringWithFormat:@"%*s", (int)(indent + indentWidth), ""];
        NSString *indentStr3 = [NSString stringWithFormat:@"%*s", (int)(indent + indentWidth * 2), ""];
        for (NSString *val in valuesArr) {
            [fixStr appendFormat:@"\n%@case %@:\n%@break;\n%@", indentStr2, val, indentStr3, indentStr2];
        }
        [fixStr appendString:@"\n"];
//        [fixStr appendString:indentStr];
        
        NSString *wholeText = [textStorage string];
        NSRange lineRange = [wholeText lineRangeForRange:NSMakeRange(replaceRange.location, 0)]; // current line
        lineRange = [wholeText lineRangeForRange:NSMakeRange(lineRange.location - 1, 0)]; // previous line
        
        NSString *s = [wholeText substringWithRange:lineRange];
        if ([[s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] == 0) {
            replaceRange = lineRange; // replace the empty line
        }
        
        DVTTextDocumentLocation *replaceLocation = [[DVTTextDocumentLocation alloc] initWithDocumentURL:loc.documentURL timestamp:loc.timestamp characterRange:replaceRange];
        
        IDEDiagnosticFixItItem * item = [[IDEDiagnosticFixItItem alloc] initWithFixItString:fixStr replacementLocation:replaceLocation];
        
        item.diagnosticItem = message;
        [message.mutableDiagnosticFixItItems addObject:item];
    }
    
}

#pragma mark -

- (void)installSourceTextViewHelper
{
    SEL sel = sel_getUid("setSelectedRange:affinity:stillSelecting:");
    Class DVTSourceTextViewClass = NSClassFromString(@"DVTSourceTextView");
    
    Method method = class_getInstanceMethod(DVTSourceTextViewClass, sel);
    IMP originalImp = method_getImplementation(method);
    
    IMP imp = imp_implementationWithBlock(^void(DVTSourceTextView * view, NSRange range, NSSelectionAffinity affinity, BOOL stillSelecting) {
        if (!stillSelecting) {
            try {
                @try {
                    NSString *caller = [NSThread callStackSymbols][1];
                    if ([caller rangeOfString:@"moveToBeginningOfLine"].location != NSNotFound) {
                        NSRange newrange = [self rangeOfBeginningOfLineAtRange:range view:view];
                        NSRange oldrange = view.selectedRange;
                        if (newrange.location < oldrange.location) {
                            range = newrange;
                        }
                    }
                }
                @catch (id exception) {
                    // something wrong... but I don't want to crash Xcode
                    NSLog(@"%s:%d - %@", __PRETTY_FUNCTION__, __LINE__, exception);
                }
            }
            catch(std::exception &e) {
                NSLog(@"%s:%d - %s", __PRETTY_FUNCTION__, __LINE__, e.what());
            }
            catch (...) {
                NSLog(@"%s:%d - unknown exception", __PRETTY_FUNCTION__, __LINE__);
            }
        }
        
        ((void (*)(id,SEL,NSRange,NSSelectionAffinity,BOOL))originalImp)(view, sel, range, affinity, stillSelecting);
    });
    
    method_setImplementation(method, imp);
}

- (NSRange)rangeOfBeginningOfLineAtRange:(NSRange)range view:(DVTSourceTextView *)view
{
    NSTextStorage *textStorage = view.textStorage;
    
    NSUInteger loc = range.location;
    NSString *str = textStorage.string;
    
    // find first non-whitespace character in this line
    NSCharacterSet *whitespaceSet = [NSCharacterSet whitespaceCharacterSet];
    NSCharacterSet *newlineSet = [NSCharacterSet newlineCharacterSet];
    while (loc < str.length) {
        unichar c = [str characterAtIndex:loc];
        if (![whitespaceSet characterIsMember:c]) {
            break;
        }
        if ([newlineSet characterIsMember:c]) {
            return range;
        }
        ++loc;
    }
    if (loc >= str.length) {
        return range;
    }
    
    NSInteger indent = loc - range.location;
    
    range.location += indent;
    if (range.length >= indent) {
        range.length -= indent;
    } else {
        range.length = 0;
    }
    
    return range;
}

@end
