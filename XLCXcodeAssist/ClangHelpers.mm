//
//  ClangHelpers.m
//  XLCXcodeAssist
//
//  Created by Xiliang Chen on 14/9/17.
//  Copyright (c) 2014年 Xiliang Chen. All rights reserved.
//

#import "ClangHelpers.hh"

namespace xlc {
    namespace clang {
        
        unsigned equalCursors(CXCursor X, CXCursor Y) {
            X.data[0] = NULL; // clear parent
            Y.data[0] = NULL;
            return clang_equalCursors(X, Y);
        }
        
        std::shared_ptr<Node> buildCursorTreeAndFind(CXCursor currentCursor, bool customEqual, std::shared_ptr<Node> &root)
        {
            auto compareCursors = customEqual ? equalCursors : clang_equalCursors;
            
            CXCursor rootCursor = clang_getCursorSemanticParent(currentCursor);
            
            root = std::make_shared<Node>();
            root->cursor = rootCursor;
            __block std::shared_ptr<Node> currentCursorNode;
            __block auto current = root;
            
            //        NSLog(@"%@ - %@ | %@", NSStringFromCXString(clang_getCursorKindSpelling(currentCursor.kind)), NSStringFromCXString(clang_getCursorSpelling(currentCursor)), NSStringFromCXString(clang_getCursorUSR(currentCursor)));
            
            clang_visitChildrenWithBlock(rootCursor, ^enum CXChildVisitResult(CXCursor cursor, CXCursor parent) {
                if (!compareCursors(parent, current->cursor)) { // parent changed
                    if (!current->children.empty() && compareCursors(current->children.back()->cursor, parent)) {
                        current = current->children.back(); // move in
                    } else {
                        while (current && current->parent.lock() && !compareCursors(current->parent.lock()->cursor, parent)) {
                            current = current->parent.lock();
                        }
                        current = current->parent.lock();
                    }
                }
                current->children.emplace_back(new Node);
                current->children.back()->cursor = cursor;
                current->children.back()->parent = current;
                if (xlc::clang::equalCursors(cursor, currentCursor)) {
                    currentCursorNode = current->children.back();
                }
                return CXChildVisit_Recurse;
            });
            
            return currentCursorNode;
        }
        
        void Node::print(int level) const
        {
            NSLog(@"%*s%@ - %@ %@", level * 4, "", NSStringFromCXString(clang_getCursorKindSpelling(cursor.kind)), NSStringFromCXString(clang_getCursorSpelling(cursor)), NSStringFromCXString(clang_getCursorUSR(cursor)));
            for (auto const &child : children) {
                child->print(level+1);
            }
        }
        
        std::shared_ptr<Node> Node::search(CXCursor cursor)
        {
            if (clang_equalCursors(this->cursor, cursor)) {
                return shared_from_this();
            }
            for (auto & child : children) {
                if (auto result = child->search(cursor)) {
                    return result;
                }
            }
            return nullptr;
        }
    }
}