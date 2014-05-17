//
//  XLCXcodeAssist.h
//  XLCXcodeAssist
//
//  Created by Xiliang Chen on 14-5-12.
//  Copyright (c) 2014年 Xiliang Chen. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface XLCXcodeAssist : NSObject

+ (instancetype)sharedPlugin;
+ (BOOL)shouldLoadPlugin;

@end
