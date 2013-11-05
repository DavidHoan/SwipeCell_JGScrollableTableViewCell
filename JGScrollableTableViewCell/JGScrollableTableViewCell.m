//
//  JGScrollableTableViewCell.m
//  ProTube 2
//
//  Created by Jonas Gessner on 03.11.13.
//  Copyright (c) 2013 Jonas Gessner. All rights reserved.
//

#import "JGScrollableTableViewCell.h"

@protocol JGTouchForwarder <NSObject>

- (void)forwardTouchesBegan:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)forwardTouchesMoved:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)forwardTouchesEnded:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)forwardTouchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event;

@end

@protocol JGViewProvider <NSObject>

- (UIView *)requestedView;

@end

@interface JGScrollableTableViewCellScrollView : UIScrollView

@property (nonatomic, weak) id <JGTouchForwarder> forwarder;
@property (nonatomic, weak) id <JGViewProvider> viewProvider;

@end

@implementation JGScrollableTableViewCellScrollView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self) {
        return nil;
    }
    else {
        return hit;
    }
}

- (NSArray *)subviews {
    UIView *v = [self.viewProvider requestedView];
    if (v) {
        return @[v];
    }
    else {
        return nil;
    }
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    [self.forwarder forwardTouchesBegan:touches withEvent:event];
    [super touchesBegan:touches withEvent:event];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    [self.forwarder forwardTouchesMoved:touches withEvent:event];
    [super touchesMoved:touches withEvent:event];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    [self.forwarder forwardTouchesEnded:touches withEvent:event];
    [super touchesEnded:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    [self.forwarder forwardTouchesCancelled:touches withEvent:event];
    [super touchesCancelled:touches withEvent:event];
}

@end



@interface JGScrollableTableViewCellManager ()

+ (void)referenceCell:(JGScrollableTableViewCell *)cell inTableView:(UITableView *)host;
+ (void)removeCellReference:(JGScrollableTableViewCell *)cell inTableView:(UITableView *)host;

+ (NSSet *)allCellsInTableView:(UITableView *)host;


@end

@implementation JGScrollableTableViewCellManager

static NSMutableDictionary *_refs;

+ (void)closeAllCellsWithExceptionOf:(JGScrollableTableViewCell *)cell stopAfterFirst:(BOOL)stop {
    UITableView *host = (UITableView *)cell.superview;
    NSSet *cells = [self allCellsInTableView:host];
    
    for (JGScrollableTableViewCell *otherCell in cells) {
        if (otherCell != cell && (otherCell.scrolling || otherCell.optionViewVisible)) {
            [otherCell setOptionViewVisible:NO animated:YES];
            if (stop) {
                break;
            }
        }
    }
}

+ (void)removeCellReference:(JGScrollableTableViewCell *)cell inTableView:(UITableView *)host {
    NSAssert([NSThread isMainThread], @"JGScrollableTableViewCellManager should only be used on the main thread");
    
    NSValue *key = [NSValue valueWithNonretainedObject:host];
    
    NSMutableSet *hostCells = _refs[key];
    
    [hostCells removeObject:cell];
    
    if (hostCells.count) {
        _refs[key] = hostCells;
    }
    else {
        [_refs removeObjectForKey:key];
    }
}

+ (void)referenceCell:(JGScrollableTableViewCell *)cell inTableView:(UITableView *)host {
    NSAssert([NSThread isMainThread], @"JGScrollableTableViewCellManager should only be used on the main thread");
    
    if (!_refs) {
        _refs = [NSMutableDictionary dictionary];
    }
    
    NSValue *key = [NSValue valueWithNonretainedObject:host];
    
    NSMutableSet *hostCells = _refs[key];
    if (!hostCells) {
        hostCells = [NSMutableSet set];
    }
    
    [hostCells addObject:cell];
    
    _refs[key] = hostCells;
}

+ (NSSet *)allCellsInTableView:(UITableView *)host {
    NSAssert([NSThread isMainThread], @"JGScrollableTableViewCellManager should only be used on the main thread");
    NSValue *key = [NSValue valueWithNonretainedObject:host];
    return [_refs[key] copy];
}

@end


#define kJGScrollableTableViewCellAnimationDuration 0.3

@interface JGScrollableTableViewCell () <JGTouchForwarder, JGViewProvider, UIScrollViewDelegate> {
    JGScrollableTableViewCellScrollView *_scrollView;
    UIView *_scrollViewCoverView;
    JGScrollableTableViewCellSide _side;
    BOOL _forceRelayout;
    BOOL _cancelCurrentForwardedGesture;
    
    __weak UITableView *_hostingTableView;
}

@end

@implementation JGScrollableTableViewCell


#pragma mark - Initialization

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _scrollView = [[JGScrollableTableViewCellScrollView alloc] init];
        _scrollView.backgroundColor = [UIColor clearColor];
        _scrollView.showsHorizontalScrollIndicator = NO;
        _scrollView.forwarder = self;
        _scrollView.delegate = self;
        _scrollView.pagingEnabled = YES;
        _scrollView.viewProvider = self;
        
        _scrollViewCoverView = [[UIView alloc] init];
        [_scrollView addSubview:_scrollViewCoverView];
        
        [self.contentView addSubview:_scrollView];
    }
    return self;
}

#pragma mark - Delegates

- (UIView *)requestedView {
    return _scrollViewCoverView;
}

- (void)forwardTouchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    if (!self.scrolling && !self.optionViewVisible) {
        if (self.grabberView && CGRectContainsPoint(self.grabberView.bounds, [touches.anyObject locationInView:self.grabberView])) {
            _cancelCurrentForwardedGesture = YES;
        }
        else {
            _cancelCurrentForwardedGesture = NO;
            [self touchesBegan:touches withEvent:event];
        }
    }
}

- (void)forwardTouchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    if (!self.scrolling && !self.optionViewVisible && !_cancelCurrentForwardedGesture) {
        [self touchesCancelled:touches withEvent:event];
    }
}

- (void)forwardTouchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    if (!self.scrolling && !self.optionViewVisible && !_cancelCurrentForwardedGesture) {
        [self touchesEnded:touches withEvent:event];
    }
    else if (self.optionViewVisible) {
        __weak __typeof(self) weakSelf = self;
        
        [self setOptionViewVisible:NO animationDuration:kJGScrollableTableViewCellAnimationDuration completion:^{
            if ([weakSelf.scrollDelegate respondsToSelector:@selector(cellDidEndScrolling:)]) {
                [weakSelf.scrollDelegate cellDidEndScrolling:weakSelf];
            }
        }];
    }
}

- (void)forwardTouchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    if (!self.scrolling && !self.optionViewVisible && !_cancelCurrentForwardedGesture) {
        [self touchesCancelled:touches withEvent:event];
    }
}


- (void)scrollViewDidScroll:(UIScrollView *)__unused scrollView {
    if (!_scrolling) {
        if (self.selected || self.highlighted || (self.grabberView && !self.optionViewVisible && !CGRectContainsPoint(self.grabberView.bounds, [_scrollView.panGestureRecognizer locationInView:self.grabberView]))) {
            _scrollView.panGestureRecognizer.enabled = NO;
            _scrollView.panGestureRecognizer.enabled = YES;
        }
        else {
            _scrolling = YES;
            if ([self.scrollDelegate respondsToSelector:@selector(cellDidBeginScrolling:)]) {
                [self.scrollDelegate cellDidBeginScrolling:self];
            }
        }
    }
    else {
        if ([self.scrollDelegate respondsToSelector:@selector(cellDidScroll:)]) {
            [self.scrollDelegate cellDidScroll:self];
        }
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)__unused scrollView {
    _scrolling = NO;
    
    _optionViewVisible = (_side == JGScrollableTableViewCellSideRight ? (_scrollView.contentOffset.x != 0.0f) : (_scrollView.contentOffset.x == 0.0f));
    
    if ([self.scrollDelegate respondsToSelector:@selector(cellDidEndScrolling:)]) {
        [self.scrollDelegate cellDidEndScrolling:self];
    }
}


#pragma mark - Overrides

- (void)willMoveToSuperview:(UIView *)newSuperview {
    [super willMoveToSuperview:newSuperview];
    
    _hostingTableView = (UITableView *)newSuperview;
    [JGScrollableTableViewCellManager referenceCell:self inTableView:_hostingTableView];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    CGRect scrollViewFrame = UIEdgeInsetsInsetRect(self.contentView.bounds, self.scrollViewInsets);
    
    _scrollView.delegate = nil;
    
    _scrollView.frame = scrollViewFrame;
    
    _scrollView.delegate = self;
    
    _scrollView.contentSize = (CGSize){scrollViewFrame.size.width+self.optionView.frame.size.width, scrollViewFrame.size.height};
    
    _scrollViewCoverView.frame = (CGRect){{(_side == JGScrollableTableViewCellSideLeft ? self.optionView.frame.size.width : 0.0f), 0.0f}, scrollViewFrame.size};
    
    if (self.grabberView) {
        CGSize grabberSize = self.grabberView.frame.size;
        
        self.grabberView.frame = (CGRect){{(_side == JGScrollableTableViewCellSideLeft ? 0.0f : scrollViewFrame.size.width-grabberSize.width), (scrollViewFrame.size.height-grabberSize.height)/2.0f}, grabberSize};
    }
    
    if (_side == JGScrollableTableViewCellSideRight) {
        CGSize size = (CGSize){self.optionView.frame.size.width, scrollViewFrame.size.height};
        
        self.optionView.frame = (CGRect){{CGRectGetMaxX(scrollViewFrame)-self.optionView.frame.size.width, 0.0f}, size};
    }
    else {
        CGSize size = (CGSize){self.optionView.frame.size.width, scrollViewFrame.size.height};
        
        self.optionView.frame = (CGRect){{self.scrollViewInsets.left, self.scrollViewInsets.top}, size};
    }
    
    _forceRelayout = YES; //enusres that next call is actually executed
    [self setOptionViewVisible:self.optionViewVisible]; //sets correct contentOffset
    _forceRelayout = NO;
}

#pragma mark - Setters

- (void)setOptionViewVisible:(BOOL)optionViewVisible animated:(BOOL)animated {
    [self setOptionViewVisible:optionViewVisible animationDuration:(animated ? kJGScrollableTableViewCellAnimationDuration : 0.0) completion:NULL];
}

- (void)setOptionViewVisible:(BOOL)optionViewVisible animationDuration:(NSTimeInterval)duration completion:(void (^)(void))completion {
    if (!_forceRelayout && _optionViewVisible == optionViewVisible && !self.scrolling) {
        return;
    }
    
    _scrolling = NO;
    _optionViewVisible = optionViewVisible;
    
    _scrollView.delegate = nil;
    
    CGPoint scrollDestination;
    
    if (_side == JGScrollableTableViewCellSideLeft) {
        scrollDestination = (CGPoint){(_optionViewVisible ? 0.0f : _scrollView.contentSize.width-1.0f), 0.0f};
    }
    else  {
        scrollDestination = (CGPoint){(_optionViewVisible ? _scrollView.contentSize.width-1.0f : 0.0f), 0.0f};
    }
    
    [UIView animateWithDuration:duration delay:0.0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionBeginFromCurrentState animations:^{
        [_scrollView.panGestureRecognizer setEnabled:NO];
        [_scrollView scrollRectToVisible:(CGRect){scrollDestination, {1.0f, 1.0f}} animated:NO];
    } completion:^(__unused BOOL finished) {
        [_scrollView.panGestureRecognizer setEnabled:YES];
        _scrollView.delegate = self;
        if (completion) {
            completion();
        }
    }];
}

- (void)setOptionViewVisible:(BOOL)optionViewVisible {
    [self setOptionViewVisible:optionViewVisible animated:NO];
}

- (void)setGrabberView:(UIView *)grabberView {
    [self.grabberView removeFromSuperview];
    
    _grabberView = grabberView;
    
    if (self.grabberView) {
        [_scrollView addSubview:self.grabberView];
        
        [self setNeedsLayout];
        [self layoutIfNeeded];
    }
}

- (void)setOptionView:(UIView *)view side:(JGScrollableTableViewCellSide)side {
    _side = side;
    
    [self.optionView removeFromSuperview];
    
    _optionView = view;
    
    [self.contentView insertSubview:self.optionView belowSubview:_scrollView];
    
    [self setNeedsLayout];
    [self layoutIfNeeded];
}

- (void)setScrollViewBackgroundColor:(UIColor *)scrollViewBackgroundColor {
    _scrollViewCoverView.backgroundColor = scrollViewBackgroundColor;
}

- (void)setScrollViewInsets:(UIEdgeInsets)scrollViewInsets {
    _scrollViewInsets = scrollViewInsets;
    
    [self setNeedsLayout];
    [self layoutIfNeeded];
}

- (void)addContentView:(UIView *)view {
    [_scrollViewCoverView addSubview:view];
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated {
    void (^actions)(BOOL select) = ^(BOOL select) {
        _optionView.hidden = select;
        _scrollView.scrollEnabled = !select;
    };
    
    if (highlighted) {
        actions(highlighted);
    }
    
    id previousBlock = [CATransaction completionBlock];
    
    [CATransaction setCompletionBlock:^{
        actions(highlighted);
    }];
    
    [super setHighlighted:highlighted animated:animated];
    
    [CATransaction setCompletionBlock:previousBlock];
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    void (^actions)(BOOL select) = ^(BOOL select) {
        _optionView.hidden = select;
        _scrollView.scrollEnabled = !select;
    };
    
    if (selected) {
        actions(selected);
    }
    
    id previousBlock = [CATransaction completionBlock];
    
    [CATransaction setCompletionBlock:^{
        actions(selected);
    }];
    
    [super setSelected:selected animated:animated];
    
    [CATransaction setCompletionBlock:previousBlock];
}

#pragma mark - Dealloc

- (void)dealloc {
    [JGScrollableTableViewCellManager removeCellReference:self inTableView:_hostingTableView];
}

@end
