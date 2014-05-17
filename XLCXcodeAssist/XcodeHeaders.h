//
//  XcodeHeaders.h
//  XLCXcodeAssist
//
//  Created by Xiliang Chen on 14-5-17.
//  Copyright (c) 2014年 Xiliang Chen. All rights reserved.
//

#import <Foundation/Foundation.h>

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
// xcode.syntax.identifier = 7
// xcode.syntax.method.declarator = 42
// xcode.syntax.definition.objc.implementation = 45
// ------- token -------
// @end = 131196
// objc.parenexpr = 131431
// objc.method.declarator = 131443
// objc.implementation = 131470


typedef NS_ENUM(short, XLCNodeType) {
    XLCNodePlain = 0,
    XLCNodeIdentifier = 7,
    XLCNodeMethodDeclarator = 42,
    XLCNodeImplementation = 45,
};

typedef NS_ENUM(long long, XLCTokenType) {
    XLCTokenEnd = 131196,
    XLCTokenParenExpr = 131431,
};

@interface DVTSourceModelItem : NSObject

@property(retain) NSArray * children;
@property XLCTokenType token;

- (DVTSourceModelItem *)parent;
- (XLCNodeType)nodeType;
- (NSRange)range;

@end

@interface DVTSourceModel : NSObject

- (DVTSourceModelItem *)enclosingItemAtLocation:(unsigned long long)arg1;

@end

@interface DVTTextStorage : NSTextStorage

@property(readonly) DVTSourceModel * sourceModel;

- (NSRange)methodDefinitionRangeAtIndex:(unsigned long long)arg1;

@end

@interface IDESourceCodeDocument : IDEEditorDocument

@property(readonly) DVTTextStorage * textStorage;

@end

