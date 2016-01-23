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

@interface DVTSourceModelItem : NSObject

@property(retain) NSArray * children;
@property long long token;

- (DVTSourceModelItem *)parent;
- (short)nodeType;
- (NSRange)range;
- (id)nextItem;

- (NSString *)simpleDescription;

@end

@interface DVTSourceModel : NSObject

- (DVTSourceModelItem *)enclosingItemAtLocation:(unsigned long long)arg1;
- (long long)indentForItem:(DVTSourceModelItem *)arg1;

@end

@interface DVTSourceLandmarkItem : NSObject

@property DVTSourceLandmarkItem * parent;
@property(readonly) NSArray * children;
@property(copy) NSString * name;
@property(readonly) int type;
@property(copy,readonly) NSString * typeName;
@property NSRange range;
@property NSRange nameRange;

@end

@interface DVTTextStorage : NSTextStorage

@property(readonly) DVTSourceModel * sourceModel;
@property unsigned long long indentWidth;
@property(readonly) DVTSourceLandmarkItem * topSourceLandmark;

- (NSRange)methodDefinitionRangeAtIndex:(unsigned long long)arg1;
- (NSRange)functionOrMethodBodyRangeAtIndex:(unsigned long long)arg1;
- (NSRange)characterRangeForLineRange:(NSRange)arg1;
- (NSRange)characterRangeFromDocumentLocation:(id)arg1;
- (id)sourceLandmarkAtCharacterIndex:(unsigned long long)arg1;
- (long long)getIndentForLine:(long long)arg1;
- (NSRange)lineRangeForCharacterRange:(NSRange)arg1;

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
- (void)performClang:(id)arg1;

@end

@interface DVTCompletingTextView : NSTextView

@end

@interface DVTSourceTextView : DVTCompletingTextView

@end


@interface IDESourceLanguageServiceSwiftDiagnosticItems : NSObject

@property(copy,readonly) NSArray<IDEDiagnosticActivityLogMessage *> * diagnosticItems;

@end
