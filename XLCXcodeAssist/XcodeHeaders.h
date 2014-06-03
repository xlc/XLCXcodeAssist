//
//  XcodeHeaders.h
//  XLCXcodeAssist
//
//  Created by Xiliang Chen on 14-5-17.
//  Copyright (c) 2014年 Xiliang Chen. All rights reserved.
//

#import <Foundation/Foundation.h>

#include "Index.h"

@interface DVTTextDocumentLocation : NSObject

@property(readonly) NSURL * documentURL;
@property(readonly) NSNumber * timestamp;

@property(readonly) long long startingColumnNumber;
@property(readonly) long long endingColumnNumber;
@property(readonly) long long startingLineNumber;
@property(readonly) long long endingLineNumber;
@property(readonly) NSRange lineRange;
@property(readonly) NSRange characterRange;

- (id)initWithDocumentURL:(id)arg1 timestamp:(id)arg2 lineRange:(NSRange)arg3;
- (id)initWithDocumentURL:(id)arg1 timestamp:(id)arg2 characterRange:(NSRange)arg3;

@end

@interface IDEDiagnosticActivityLogMessage : NSObject

@property(readonly) NSString * title;
@property(readonly) NSMutableArray * mutableDiagnosticFixItItems;
@property(readonly) NSArray * submessages;
@property(readonly) DVTTextDocumentLocation * location;

@end

@interface IDEDiagnosticFixItItem : NSObject

@property IDEDiagnosticActivityLogMessage * diagnosticItem;
@property(readonly) NSString * fixItString;
@property(readonly) DVTTextDocumentLocation * replacementLocation;

- (id)initWithFixItString:(NSString *)arg1 replacementLocation:(DVTTextDocumentLocation *)arg2;

@end

@interface IDEEditorDocument : NSDocument

- (id)initWithContentsOfURL:(id)arg1 ofType:(id)arg2 error:(id*)arg3;
- (id)initForURL:(id)arg1 withContentsOfURL:(id)arg2 ofType:(id)arg3 error:(id*)arg4;

@end

// ------- node type -------
// xcode.syntax.plain = 0
// xcode.syntax.keyword = 7
// xcode.syntax.identifier = 24
// xcode.syntax.method.declarator = 42
// xcode.syntax.definition.objc.implementation = 45
// ------- token -------
// c.block = 131370
// cpp.block = 131401
// objc.block = 131468
// objcpp.block = 131573
// @end = 131196
// objc.parenexpr = 131431
// objc.method.declarator = 131443
// objc.implementation = 131470
// objcpp.parenexpr = 131529
// switch = 131169


typedef NS_ENUM(short, XLCNodeType) {
    XLCNodeMethodDeclarator = 42,
    XLCNodeImplementation = 45,
};

@interface DVTSourceModelItem : NSObject

@property(retain) NSArray * children;
@property long long token;

- (DVTSourceModelItem *)parent;
- (XLCNodeType)nodeType;
- (NSRange)range;

- (NSString *)simpleDescription;

@end

@interface DVTSourceModel : NSObject

- (DVTSourceModelItem *)enclosingItemAtLocation:(unsigned long long)arg1;
- (long long)indentForItem:(DVTSourceModelItem *)arg1;

@end

@interface DVTTextStorage : NSTextStorage

@property(readonly) DVTSourceModel * sourceModel;
@property unsigned long long indentWidth;

- (NSRange)methodDefinitionRangeAtIndex:(unsigned long long)arg1;

@end

@interface IDESourceCodeDocument : IDEEditorDocument

@property(readonly) DVTTextStorage * textStorage;

@end

@interface IDEDocumentController : NSDocumentController

+ (IDEDocumentController *)sharedDocumentController;
- (id)documentForURL:(id)arg1;

@end

@interface IDEIndexCollection : NSObject <NSFastEnumeration>

- (NSArray *)allObjects;

@end

@interface IDEIndexContainerSymbol : NSObject

- (IDEIndexCollection *)children;

@end

@interface DVTSourceCodeSymbolKind : NSObject

@property(getter=isContainer,readonly) BOOL container;

+ (id)enumConstantSymbolKind;
+ (id)enumSymbolKind;

@end

@interface IDEIndexCompletionItem : NSObject

@property(readonly) NSString * displayText;
@property(readonly) NSString * displayType;
@property double priority;

@end

@interface IDEIndex : NSObject

- (IDEIndexCollection *)allSymbolsMatchingName:(NSString *)arg1 kind:(id)arg2;
- (IDEIndexCollection *)codeCompletionsAtLocation:(DVTTextDocumentLocation *)arg1 withCurrentFileContentDictionary:(NSMutableDictionary *)arg2 completionContext:(id*)arg3;

@end

@class IDEIndexDatabase;
@class DVTFilePath;
@class DVTDispatchLock;

@interface IDEIndexGenericQueryProvider : NSObject {
    IDEIndexDatabase *_db;
    NSDictionary *_settings;
    DVTFilePath *_mainFilePath;
    NSString *_target;
    NSDictionary *_coveredFiles;
    double _lastAccess;
}

@end

@interface IDEIndexClangQueryProvider : IDEIndexGenericQueryProvider  {
@public
    DVTDispatchLock *_clangLock;
    void *_cxIndex;
    struct CXTranslationUnitImpl { } *_cxTU;
    long long _filePurgeCount;
    NSArray *_astArgs;
    NSString *_workingDirectory;
    struct { unsigned int x1[4]; void *x2; } *_tokens;
    struct { int x1; int x2; void *x3[3]; } *_cursors;
    DVTTextDocumentLocation *_processedLocation;
    DVTDispatchLock *_completionLock;
    
    id _completionBlock;
    
    unsigned int _numTokens;
    BOOL _throwOutCache;
}

- (id)typeSymbolForCXType:(CXType)arg1;

@end
