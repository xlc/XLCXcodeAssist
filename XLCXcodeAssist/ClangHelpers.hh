//
//  ClangHelpers.h
//  XLCXcodeAssist
//
//  Created by Xiliang Chen on 14/9/17.
//  Copyright (c) 2014年 Xiliang Chen. All rights reserved.
//

#import <Foundation/Foundation.h>

#include <memory>
#include <deque>

#import "Index.h"

static inline NSString *NSStringFromCXString(CXString str) {
    NSString *s = @(clang_getCString(str));
    clang_disposeString(str);
    return s;
}

namespace xlc {
    namespace clang {
        struct Node : std::enable_shared_from_this<Node> {
            CXCursor cursor;
            std::deque<std::shared_ptr<Node>> children;
            std::weak_ptr<Node> parent;
            
            void print(int level = 0) const;
            std::shared_ptr<Node> search(CXCursor cursor);
            
            NSString *cursorSpelling() { return NSStringFromCXString(clang_getCursorSpelling(cursor)); }
        };
        
        unsigned equalCursors(CXCursor X, CXCursor Y);
        
        std::shared_ptr<Node> buildCursorTreeAndFind(CXCursor currentCursor, bool customEqual, std::shared_ptr<Node> &root);
    }
}