//
//  XLCXcodeAssist.m
//  XLCXcodeAssist
//
//  Created by Xiliang Chen on 14-5-12.
//  Copyright (c) 2014年 Xiliang Chen. All rights reserved.
//

#import "XLCXcodeAssist.h"

#import <objc/runtime.h>

#import "XcodeHeaders.h"

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

        SEL sel = sel_getUid("codeDiagnosticsAtLocation:withCurrentFileContentDictionary:forIndex:");
        Class IDEIndexClangQueryProviderClass = NSClassFromString(@"IDEIndexClangQueryProvider");
        Class IDESourceCodeDocumentClass = NSClassFromString(@"IDESourceCodeDocument");
        
        Method method = class_getInstanceMethod(IDEIndexClangQueryProviderClass, sel);
        IMP originalImp = method_getImplementation(method);
        
        NSRegularExpression *messageRegex = [NSRegularExpression regularExpressionWithPattern:@"Method definition for '(.*)' not found" options:0 error:NULL];
        NSRegularExpression *subMessageRegex = [NSRegularExpression regularExpressionWithPattern:@"Method '.*' declared here" options:0 error:NULL];
        
        IMP imp = imp_implementationWithBlock(^id(id me, id loc, id dict, id idx) {
            id ret = ((id (*)(id,SEL,id,id,id))originalImp)(me, sel, loc, dict, idx);
            
            for (IDEDiagnosticActivityLogMessage * message in ret) {
                NSString *title = message.title;
                
                NSTextCheckingResult *result = [messageRegex firstMatchInString:title options:0 range:NSMakeRange(0, title.length)];
                if ([result range].location != NSNotFound) {
                    // found
                    
                    //NSString *selname = [title substringWithRange:[result rangeAtIndex:1]];
                    DVTTextDocumentLocation *bodyLoc = message.location;
                    
                    for (IDEDiagnosticActivityLogMessage *submsg in message.submessages) {
                        NSString *title = submsg.title;
                        if ([subMessageRegex rangeOfFirstMatchInString:title options:0 range:NSMakeRange(0, title.length)].location != NSNotFound) {
                            DVTTextDocumentLocation * declLoc = submsg.location;
                            
                            NSError *error;
                            
                            IDESourceCodeDocument *headerDoc = [[IDESourceCodeDocumentClass alloc] initWithContentsOfURL:declLoc.documentURL ofType:@"public.objective-c-source" error:&error];
                            if (error) {
                                continue;
                            }
                            
                            IDESourceCodeDocument *bodyDoc;
                            if ([declLoc.documentURL isEqual:bodyLoc.documentURL]) {
                                bodyDoc = headerDoc;
                            } else {
                                bodyDoc = [[IDESourceCodeDocumentClass alloc] initWithContentsOfURL:bodyLoc.documentURL ofType:@"public.objective-c-source" error:&error];
                                if (error) {
                                    continue;
                                }
                            }
                            
                            DVTTextStorage *headerText = headerDoc.textStorage;
                            DVTTextStorage *bodyText = bodyDoc.textStorage;
                            
                            NSRange declRange = [headerText methodDefinitionRangeAtIndex:declLoc.characterRange.location];
                            NSString *declStr = [headerText.string substringWithRange:declRange];
                            
                            DVTSourceModel *headerModel = headerText.sourceModel;
                            DVTSourceModelItem *declItem = [headerModel enclosingItemAtLocation:declRange.location];
                            while (declItem.nodeType != XLCNodeMethodDeclarator && declItem) {
                                declItem = declItem.parent;
                            }
                            if (!declItem) {
                                continue;
                            }
                            
                            NSString *returnType;
                            for (DVTSourceModelItem *item in declItem.children) {
                                if (item.nodeType == XLCNodePlain && item.token == XLCTokenParenExpr) {
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
                            } else if ([realReturnType hasSuffix:@"*"] || [realReturnType isEqualToString:@"id"]) {
                                returnStatement = @"return <#nil#>;";
                            } else {
                                returnStatement = [NSString stringWithFormat:@"return <#%@#>;", returnType];
                            }
                            
                            NSString *str = [NSString stringWithFormat:@"%@\n{\n    %@\n}\n\n", declStr, returnStatement];
                            NSRange bodyPosRange = bodyLoc.characterRange;
                            
                            DVTSourceModel *bodyModel = bodyText.sourceModel;
                            
                            DVTSourceModelItem *bodyItem = [bodyModel enclosingItemAtLocation:bodyPosRange.location + bodyPosRange.length];
                            while (bodyItem.nodeType != XLCNodeImplementation && bodyItem) {
                                bodyItem = bodyItem.parent;
                            }
                            if (!bodyItem) {
                                continue;
                            }
                            
                            NSRange replaceRange = {NSNotFound, 0};
                            
                            DVTSourceModelItem *endBodyItem = [bodyItem.children lastObject];
                            replaceRange.location = endBodyItem.range.location;
                            
                            DVTTextDocumentLocation *replaceLocation = [[DVTTextDocumentLocation alloc] initWithDocumentURL:bodyLoc.documentURL timestamp:bodyLoc.timestamp characterRange:replaceRange];
                            
                            IDEDiagnosticFixItItem * item = [[IDEDiagnosticFixItItem alloc] initWithFixItString:str replacementLocation:replaceLocation];
                            
                            item.diagnosticItem = message;
                            [message.mutableDiagnosticFixItItems addObject:item];
                            
                            [headerDoc close];
                            if (bodyDoc != headerDoc) {
                                [bodyDoc close];
                            }
                            
                            break;
                        }
                    }
                }
            }
            
            return ret;
        });
        
        method_setImplementation(method, imp);
    }
    
    return self;
}

@end

