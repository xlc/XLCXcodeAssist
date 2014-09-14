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
#import <dlfcn.h>
#import "Index.h"

#import "XcodeHeaders.h"

@interface XLCXcodeAssist ()

- (void)installDiagnosticsHelper;
- (void)installSourceTextViewHelper;

- (void)processMethodDefinitionNotFoundMessage:(IDEDiagnosticActivityLogMessage *)message;
- (void)processSwitchCaseMessage:(IDEDiagnosticActivityLogMessage *)message withIndex:(IDEIndex *)index queryProvider:(IDEIndexClangQueryProvider *)provider;

- (NSString *)itemTokenString:(DVTSourceModelItem *)item;
- (BOOL)itemIsParenExpr:(DVTSourceModelItem *)item;
- (BOOL)itemIsBlock:(DVTSourceModelItem *)item;
- (BOOL)itemIsMethodDeclarator:(DVTSourceModelItem *)item;
- (BOOL)itemIsImplementation:(DVTSourceModelItem *)item;
- (BOOL)itemIsEndToken:(DVTSourceModelItem *)item;

- (NSRange)rangeOfBeginningOfLineAtRange:(NSRange)range view:(DVTSourceTextView *)view;

@end

static NSString *NSStringFromCXString(CXString str) {
    NSString *s = @(clang_getCString(str));
    clang_disposeString(str);
    return s;
}

@implementation XLCXcodeAssist {
    id (*_tokenStringFunc)(long long);
}

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
    _tokenStringFunc = (id (*)(long long))dlsym(RTLD_DEFAULT, "_tokenString");
    
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
                while (![self itemIsMethodDeclarator:declItem] && declItem) {
                    declItem = declItem.parent;
                }
                if (!declItem) {
                    continue;
                }
                
                NSString *returnType;
                for (DVTSourceModelItem *item in declItem.children) {
                    if ([self itemIsParenExpr:item]) {
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
                    while (![self itemIsImplementation:bodyItem] && bodyItem) {
                        bodyItem = bodyItem.parent;
                    }
                    if (!bodyItem) {
                        // try again with siblings
                        bodyItem = bodyItem2;
                        while (![self itemIsImplementation:bodyItem] && bodyItem) {
                            for (DVTSourceModelItem *sibling in bodyItem.parent.children) {
                                if ([self itemIsEndToken:sibling]) {
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

static unsigned my_equalCursors(CXCursor X, CXCursor Y) {
    X.data[0] = NULL; // clear parent
    Y.data[0] = NULL;
    return clang_equalCursors(X, Y);
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

        while (blockItem && ![self itemIsBlock:blockItem]) {
            blockItem = blockItem.parent;
        }
        if (!blockItem) {
            return;
        }
        
        BOOL foundSwitchItem = NO;
        DVTSourceModelItem *switchBlockItem;
        for (DVTSourceModelItem *item in blockItem.children) {
            if (foundSwitchItem) {
                if ([self itemIsBlock:item]) {
                    if (item.range.location >= loc.characterRange.location) {
                        switchBlockItem = item;
                        break;
                    } else {
                        foundSwitchItem = NO;
                    }
                }
            }
            if ([[self itemTokenString:item] isEqualToString:@"'switch'"]) {
                foundSwitchItem = YES;
            }
        }
        
        if (!switchBlockItem) {
            return;
        }
        
        NSMutableArray *valuesArr = [NSMutableArray array];
        
        [provider performClang:^{
            CXTranslationUnit tu = provider->_cxTU;
            CXFile file = clang_getFile(tu, [[loc.documentURL path] UTF8String]);
            CXSourceLocation sloc = clang_getLocationForOffset(tu, file, (unsigned int)loc.characterRange.location);
            CXCursor currentCursor = clang_getCursor(tu, sloc);
            
            struct Node {
                CXCursor cursor;
                std::deque<std::shared_ptr<Node>> children;
                std::shared_ptr<Node> parent;
            };
            
            NSMutableArray *existingValeusArray = [NSMutableArray array];
            CXCursor switchExprCursor;
            
            {
                CXCursor rootCursor = clang_getCursorSemanticParent(currentCursor);
                
                auto root = std::make_shared<Node>();
                root->cursor = rootCursor;
                __block std::shared_ptr<Node> currentCursorNode;
                __block auto current = root;
                
                //        NSLog(@"%@ - %@ | %@", NSStringFromCXString(clang_getCursorKindSpelling(currentCursor.kind)), NSStringFromCXString(clang_getCursorSpelling(currentCursor)), NSStringFromCXString(clang_getCursorUSR(currentCursor)));
                
                clang_visitChildrenWithBlock(rootCursor, ^enum CXChildVisitResult(CXCursor cursor, CXCursor parent) {
                    if (!my_equalCursors(parent, current->cursor)) { // parent changed
                        if (!current->children.empty() && my_equalCursors(current->children.back()->cursor, parent)) {
                            current = current->children.back(); // move in
                        } else {
                            while (current && current->parent && !my_equalCursors(current->parent->cursor, parent)) {
                                current = current->parent;
                            }
                            current = current->parent;
                        }
                    }
                    current->children.emplace_back(new Node);
                    current->children.back()->cursor = cursor;
                    current->children.back()->parent = current;
                    if (my_equalCursors(cursor, currentCursor)) {
                        currentCursorNode = current->children.back();
                    }
                    return CXChildVisit_Recurse;
                });
                
                std::function<void(std::shared_ptr<Node>, int)> print = [&](std::shared_ptr<Node> node, int level) {
                    if (!node) {
                        return;
                    }
                    NSLog(@"%*s%@ - %@ %@", level * 4, "", NSStringFromCXString(clang_getCursorKindSpelling(node->cursor.kind)), NSStringFromCXString(clang_getCursorSpelling(node->cursor)), NSStringFromCXString(clang_getCursorUSR(node->cursor)));
                    for (auto &child : node->children) {
                        print(child, level+1);
                    }
                };
                
                //print(root, 0);
                
                while (currentCursorNode && clang_getCursorKind(currentCursorNode->cursor) != CXCursor_SwitchStmt) {
                    currentCursorNode = currentCursorNode->parent;
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
                auto currentCursor = declCursor;
                auto rootCursor = clang_getCursorSemanticParent(currentCursor);
                auto root = std::make_shared<Node>();
                root->cursor = rootCursor;
                __block std::shared_ptr<Node> currentCursorNode;
                __block auto current = root;
                
                clang_visitChildrenWithBlock(rootCursor, ^enum CXChildVisitResult(CXCursor cursor, CXCursor parent) {
                    if (!clang_equalCursors(parent, current->cursor)) { // parent changed
                        if (!current->children.empty() && clang_equalCursors(current->children.back()->cursor, parent)) {
                            current = current->children.back(); // move in
                        } else {
                            while (current && current->parent && !clang_equalCursors(current->parent->cursor, parent)) {
                                current = current->parent;
                            }
                            current = current->parent;
                        }
                    }
                    current->children.emplace_back(new Node);
                    current->children.back()->cursor = cursor;
                    current->children.back()->parent = current;
                    if (clang_equalCursors(cursor, currentCursor)) {
                        currentCursorNode = current->children.back();
                    }
                    return CXChildVisit_Recurse;
                });
                
                //print(root, 0);
                
                std::function<std::shared_ptr<Node>(std::shared_ptr<Node> const &, CXCursor)> search = [&](std::shared_ptr<Node> const &node, CXCursor cursor) -> std::shared_ptr<Node> {
                    if (!node) {
                        return nullptr;
                    }
                    if (clang_equalCursors(node->cursor, cursor)) {
                        return node;
                    }
                    for (auto & child : node->children) {
                        if (auto result = search(child, cursor)) {
                            return result;
                        }
                    }
                    return nullptr;
                };
                
                while (currentCursorNode && currentCursorNode->cursor.kind != CXCursor_EnumDecl) {
                    if (currentCursorNode->cursor.kind == CXCursor_TypeRef) {
                        currentCursorNode = search(root, clang_getCursorDefinition(currentCursorNode->cursor));
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
                    NSString *val = NSStringFromCXString(clang_getCursorSpelling(child->cursor));
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

- (NSString *)itemTokenString:(DVTSourceModelItem *)item
{
    return _tokenStringFunc(item.token);
}

- (BOOL)itemIsParenExpr:(DVTSourceModelItem *)item
{
    NSString *token = [self itemTokenString:item];
    return [token hasSuffix:@".parenexpr'"];
}

- (BOOL)itemIsBlock:(DVTSourceModelItem *)item
{
    NSString *token = [self itemTokenString:item];
    return [token hasSuffix:@".block'"];
}

- (BOOL)itemIsMethodDeclarator:(DVTSourceModelItem *)item
{
    NSString *token = [self itemTokenString:item];
    return [token hasSuffix:@".method.declarator'"] || [token hasSuffix:@".classmethod.declarator'"];
}

- (BOOL)itemIsImplementation:(DVTSourceModelItem *)item
{
    NSString *token = [self itemTokenString:item];
    return [token hasSuffix:@".implementation'"];
}

- (BOOL)itemIsEndToken:(DVTSourceModelItem *)item
{
    NSString *token = [self itemTokenString:item];
    return [token hasSuffix:@"@end'"];
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
