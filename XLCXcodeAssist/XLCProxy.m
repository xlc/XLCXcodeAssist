//
//  XLCProxy.m
//  XLCXcodeAssist
//
//  Created by Xiliang Chen on 14-5-12.
//  Copyright (c) 2014年 Xiliang Chen. All rights reserved.
//

#import <objc/runtime.h>

@interface XLCProxy : NSProxy

+ (id)proxyWithObject:(id)obj;

@end

@implementation XLCProxy
{
    id _obj;
}

+ (void)load
{
//    {
//        Class cls = NSClassFromString(@"IDEEditorDocument");
//        id metacls = object_getClass(cls);
//        IMP imp = class_getMethodImplementation(metacls, @selector(allocWithZone:));
//        IMP newimp = imp_implementationWithBlock(^id(id me, SEL cmd, NSZone *zone) {
//            id obj = ((id (*)(id,SEL,NSZone*))(imp))(me, cmd, zone);
//            return [XLCProxy proxyWithObject:obj];
//        });
//        BOOL success = class_addMethod(metacls, @selector(allocWithZone:), newimp, [[NSString stringWithFormat:@"@@:%s", @encode(NSZone*)] UTF8String]);
//        if (!success) {
//            NSLog(@"Add method failed");
//        }
//    }
    
//    {
//        Class cls = NSClassFromString(@"IDEIndexClangTranslationUnit");
//        id metacls = object_getClass(cls);
//        IMP imp = class_getMethodImplementation(metacls, @selector(allocWithZone:));
//        IMP newimp = imp_implementationWithBlock(^id(id me, SEL cmd, NSZone *zone) {
//            id obj = ((id (*)(id,SEL,NSZone*))(imp))(me, cmd, zone);
//            return [XLCProxy proxyWithObject:obj];
//        });
//        BOOL success = class_addMethod(metacls, @selector(allocWithZone:), newimp, [[NSString stringWithFormat:@"@@:%s", @encode(NSZone*)] UTF8String]);
//        if (!success) {
//            NSLog(@"Add method failed");
//        }
//    }
    
//    {
//        SEL sel = sel_getUid("sharedDocumentController");
//        Class cls = NSClassFromString(@"IDEDocumentController");
//        
//        Method method = class_getClassMethod(cls, sel);
//        IMP originalImp = method_getImplementation(method);
//        
//        IMP imp = imp_implementationWithBlock(^id(id me, SEL cmd) {
//            id obj = ((id (*)(id,SEL))originalImp)(me, cmd);
//            return [XLCProxy proxyWithObject:obj];
//        });
//        
//        method_setImplementation(method, imp);
//    }
}

+ (id)proxyWithObject:(id)obj
{
    XLCProxy *proxy = [self alloc];
    proxy->_obj = obj;
    return proxy;
}

//- (id)typeSymbolForSymbol:(id)arg1 withCurrentFileContentDictionary:(id)arg2;

- (void)forwardInvocation:(NSInvocation *)invocation
{
    const char *selname = sel_getName([invocation selector]);
    
    [invocation setTarget:_obj];
    [invocation invoke];
    
    if ([@(selname) hasPrefix:@"init"] && [[invocation methodSignature] methodReturnType][0] == '@') {
        const void * ret;
        [invocation getReturnValue:&ret];
        ret = CFBridgingRetain([XLCProxy proxyWithObject:_obj]);
        [invocation setReturnValue:&ret];
    }
    
    NSLog(@"%@ %s", [_obj class], selname);
    
    if ([@(selname) rangeOfString:@"addDocument"].location != NSNotFound) {
        NSLog(@"%@", [invocation debugDescription]);
    }
    
//    if ([@(selname) rangeOfString:@"symbolsOccurrencesInContext:withCurrentFileContentDictionary"].location != NSNotFound) {
//        
//    }
    
//    if ([[invocation methodSignature] methodReturnType][0] == '@') {
//        NSObject __unsafe_unretained * obj;
//        [invocation getReturnValue:&obj];
//        NSLog(@"%@", obj);
//    }
}

-(NSMethodSignature *)methodSignatureForSelector:(SEL)sel
{
    return [_obj methodSignatureForSelector:sel];
}

- (Class)class
{
    return [_obj class];
}

@end
