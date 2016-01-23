//
//  SuggestSwiftMissingMethods.m
//  XLCXcodeAssist
//
//  Created by Xiliang Chen on 16/1/17.
//  Copyright © 2016年 Xiliang Chen. All rights reserved.
//

#import "SuggestSwiftMissingMethods.hh"

#import "XcodeHeaders.h"
#import "ClangHelpers.hh"
#import "DVTSourceModelItem+XLCAddition.h"
#import "XcodeHelpers.hh"

static NSInteger GetTypeBreakpoint(NSString *type) {
    NSInteger count = 0;
    NSInteger idx = 0;
    for (; idx < [type length]; ++idx) {
        unichar c = [type characterAtIndex:idx];
        switch (c) {
            case '(':
                count++;
                break;
            case ')':
                count--;
                if (count == 0) {
                    return idx;
                }
            default:
                break;
        }
    }
    
    return -1;
}

static NSString *GenerateMethodBody(NSString *funcName, NSString *funcType, NSInteger indentLevel)
{
    NSInteger bp = GetTypeBreakpoint(funcType);
    if (bp == -1) {
        return nil;
    }
    NSString *para = [funcType substringToIndex:bp];
    NSString *rettype = [funcType substringFromIndex:bp];
    
    NSRange range = [funcName rangeOfString:@"("];
    if (range.location != NSNotFound) {
        funcName = [funcName substringToIndex:range.location];
    }
    
    NSString *body = [NSString stringWithFormat:@"\nfunc %@%@ %@ {\n\n}", funcName, para, rettype];
    return [[body stringByReplacingOccurrencesOfString:@"\n" withString:[NSString stringWithFormat:@"\n%*c", (int)indentLevel, ' ']] stringByAppendingString:@"\n"];
}

static BOOL XLCHandleMethodDefinitionNotFoundMessage(IDEDiagnosticActivityLogMessage *message, NSString *funcName, NSString *funcType)
{
    DVTTextDocumentLocation *bodyLoc = message.location;
    
    IDESourceCodeDocument *bodyDoc = XLCGetSourceCodeDocument(bodyLoc, @"public.swift-source");
    
    if (!bodyDoc) {
        return NO;
    }
    
    NSRange characterRange = [bodyDoc.textStorage characterRangeFromDocumentLocation: bodyLoc];
    DVTSourceLandmarkItem *landmark = [bodyDoc.textStorage sourceLandmarkAtCharacterIndex:characterRange.location];
    
    NSRange landmarkRange = landmark.range;
    
    NSRange replaceRange = { landmarkRange.location + landmarkRange.length - 1, 0 };
    
    NSString *contnet = bodyDoc.textStorage.string;
    
    while (replaceRange.location) {
        unichar c = [[contnet substringWithRange:NSMakeRange(replaceRange.location, 1)] characterAtIndex:0];
        if ([[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember: c]) {
            replaceRange.location--;
        } else {
            break;
        }
    }
    
    NSRange lineRange = [bodyDoc.textStorage lineRangeForCharacterRange:replaceRange];
    
    NSInteger indent = [bodyDoc.textStorage getIndentForLine:lineRange.location] + 1;
    
    indent *= bodyDoc.textStorage.indentWidth;
    
    NSString *str = GenerateMethodBody(funcName, funcType, indent);
    if (!str) {
        return NO;
    }
    
    DVTTextDocumentLocation *replaceLocation = [[DVTTextDocumentLocation alloc] initWithDocumentURL:bodyLoc.documentURL timestamp:bodyLoc.timestamp characterRange:replaceRange];
    
    IDEDiagnosticFixItItem * item = [[IDEDiagnosticFixItItem alloc] initWithFixItString:str replacementLocation:replaceLocation];
    
    item.diagnosticItem = message;
    [message.mutableDiagnosticFixItItems addObject:item];
    
    return YES;
}

void XLCSuggestSwiftMissingMethods(IDEDiagnosticActivityLogMessage *message)
{
    static NSRegularExpression *protocolMessageRegex;
    static NSRegularExpression *subMessageRegex;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        protocolMessageRegex = [NSRegularExpression regularExpressionWithPattern:@"Type '(.*)' does not conform to protocol '(.*)'" options:0 error:NULL];
        subMessageRegex = [NSRegularExpression regularExpressionWithPattern:@"Protocol requires function '(.*)' with type '(.*)'" options:0 error:NULL];
    });
    
    NSString *title = message.title;
    
    BOOL found = NO;
    NSTextCheckingResult *result = [protocolMessageRegex firstMatchInString:title options:0 range:NSMakeRange(0, title.length)];
    found = result && [result range].location != NSNotFound;
    if (found) {
        for (IDEDiagnosticActivityLogMessage *submsg in message.submessages) {
            NSString *title = submsg.title;
            NSTextCheckingResult *result = [subMessageRegex firstMatchInString:title options:0 range:NSMakeRange(0, title.length)];
            if (result && [result range].location != NSNotFound) {
                NSString *funcName = [title substringWithRange:[result rangeAtIndex:1]];
                NSString *funcType = [title substringWithRange:[result rangeAtIndex:2]];
                if (XLCHandleMethodDefinitionNotFoundMessage(message, funcName, funcType)) {
                    break;
                }
            }
        }
    }
}