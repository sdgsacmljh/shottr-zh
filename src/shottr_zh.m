// shottr_zh.m — Shottr 运行时中文翻译动态库
// 原理：swizzle AppKit 的标题设置方法，在设置前查词典翻译
// 编译必须加 -fobjc-arc（静态指针持有 autorelease 对象会悬垂崩溃）
#import <AppKit/AppKit.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>

static NSDictionary *exactDict;   // 精确匹配词典
static NSDictionary *prefixDict;  // 前缀匹配词典（处理带变量的标题）
static NSDictionary *lowerDict;   // 小写匹配词典（兜底）
static NSMutableSet *missSeen;    // 已记录的未翻译字符串

// 记录未翻译的字符串到日志，便于补充词典
static void logMiss(NSString *s) {
    if (!s || s.length == 0 || s.length > 200) return;
    static NSString *logPath = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        missSeen = [NSMutableSet set];
        logPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/shottr_zh.log"];
    });
    @synchronized (missSeen) {
        if (!missSeen) missSeen = [NSMutableSet set]; // 防御
        if ([missSeen containsObject:s]) return;
        [missSeen addObject:s];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
        if (!fh) {
            [@"" writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
            fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
        }
        if (!fh) return;
        [fh seekToEndOfFile];
        NSData *d = [[s stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
        [fh writeData:d];
        [fh closeFile];
    }
}

static NSString *tz(NSString *s) {
    if (!s || s.length == 0) return s;
    NSString *t = exactDict[s];
    if (t) return t;
    for (NSString *p in prefixDict) {
        if ([s hasPrefix:p]) {
            return [prefixDict[p] stringByAppendingString:[s substringFromIndex:p.length]];
        }
    }
    t = lowerDict[[s lowercaseString]];
    if (t) return t;
    logMiss(s);
    return s;
}

static void swizzle(Class c, SEL o, SEL n) {
    Method m1 = class_getInstanceMethod(c, o);
    Method m2 = class_getInstanceMethod(c, n);
    if (m1 && m2) method_exchangeImplementations(m1, m2);
}

static void swizzleClassMethod(Class c, SEL o, SEL n) {
    Method m1 = class_getClassMethod(c, o);
    Method m2 = class_getClassMethod(c, n);
    if (m1 && m2) method_exchangeImplementations(m1, m2);
}

#pragma mark - NSMenuItem

@implementation NSMenuItem (TZ)
- (void)tz_setTitle:(NSString *)title { [self tz_setTitle:tz(title)]; }
- (instancetype)tz_initWithTitle:(NSString *)title action:(SEL)action keyEquivalent:(NSString *)k {
    return [self tz_initWithTitle:tz(title) action:action keyEquivalent:k];
}
@end

#pragma mark - NSMenu

@implementation NSMenu (TZ)
- (instancetype)tz_initWithTitle:(NSString *)title {
    return [self tz_initWithTitle:tz(title)];
}
- (NSMenuItem *)tz_addItemWithTitle:(NSString *)title action:(SEL)action keyEquivalent:(NSString *)k {
    return [self tz_addItemWithTitle:tz(title) action:action keyEquivalent:k];
}
@end

#pragma mark - NSWindow

@implementation NSWindow (TZ)
- (void)tz_setTitle:(NSString *)title { [self tz_setTitle:tz(title)]; }
@end

#pragma mark - NSButton

@implementation NSButton (TZ)
- (void)tz_setTitle:(NSString *)title { [self tz_setTitle:tz(title)]; }
- (instancetype)tz_initWithTitle:(NSString *)title target:(id)t action:(SEL)a {
    return [self tz_initWithTitle:tz(title) target:t action:a];
}
@end

#pragma mark - NSControl（偏好设置的复选框/标签值）

@implementation NSControl (TZ)
- (void)tz_setStringValue:(NSString *)s { [self tz_setStringValue:tz(s)]; }
@end

#pragma mark - NSTextField（Swift 常用类构造器：设置窗口标签）

@implementation NSTextField (TZ)
+ (instancetype)tz_labelWithString:(NSString *)s {
    id f = [self tz_labelWithString:s];
    [f setStringValue:tz(s)];
    return f;
}
+ (instancetype)tz_textFieldWithString:(NSString *)s {
    id f = [self tz_textFieldWithString:s];
    [f setStringValue:tz(s)];
    return f;
}
+ (instancetype)tz_wrappingLabelWithString:(NSString *)s {
    id f = [self tz_wrappingLabelWithString:s];
    [f setStringValue:tz(s)];
    return f;
}
@end

#pragma mark - NSBox（偏好设置分组标题）

@implementation NSBox (TZ)
- (void)tz_setTitle:(NSString *)title { [self tz_setTitle:tz(title)]; }
@end

#pragma mark - NSTabViewItem（设置窗口标签页）

@implementation NSTabViewItem (TZ)
- (void)tz_setLabel:(NSString *)label { [self tz_setLabel:tz(label)]; }
@end

#pragma mark - NSSegmentedControl（编辑器工具栏）

@implementation NSSegmentedControl (TZ)
- (void)tz_setLabel:(NSString *)label forSegment:(NSInteger)seg {
    [self tz_setLabel:tz(label) forSegment:seg];
}
@end

#pragma mark - NSPopUpButton

@implementation NSPopUpButton (TZ)
- (void)tz_addItemWithTitle:(NSString *)title { [self tz_addItemWithTitle:tz(title)]; }
- (void)tz_addItemsWithTitles:(NSArray<NSString *> *)titles {
    NSMutableArray *a = [NSMutableArray array];
    for (NSString *t in titles) [a addObject:tz(t)];
    [self tz_addItemsWithTitles:a];
}
@end

#pragma mark - 通知内容

@implementation UNMutableNotificationContent (TZ)
- (void)tz_setTitle:(NSString *)title { [self tz_setTitle:tz(title)]; }
- (void)tz_setBody:(NSString *)body { [self tz_setBody:tz(body)]; }
@end

#pragma mark - 视图树遍历（兜底：捕获 nib 直接解码、不经 setter 的文本）

static void walkView(NSView *v);

static void walkControl(NSControl *c) {
    @try {
        if (![c isKindOfClass:[NSSlider class]] && ![c isKindOfClass:[NSImageView class]]) {
            NSString *sv = [c stringValue];
            if (sv.length > 0) {
                NSString *t = tz(sv);
                if (![t isEqualToString:sv]) [c setStringValue:t]; // 会经过 swizzle，幂等
            }
        }
        if ([c isKindOfClass:[NSButton class]]) {
            NSString *title = [(NSButton *)c title];
            if (title.length > 0) {
                NSString *t = tz(title);
                if (![t isEqualToString:title]) [(NSButton *)c setTitle:t];
            }
        }
        if ([c isKindOfClass:[NSPopUpButton class]]) {
            for (NSMenuItem *item in [(NSPopUpButton *)c itemArray]) {
                if (item.title.length > 0) item.title = tz(item.title);
            }
        }
        if ([c isKindOfClass:[NSSegmentedControl class]]) {
            NSSegmentedControl *seg = (NSSegmentedControl *)c;
            for (NSInteger i = 0; i < seg.segmentCount; i++) {
                NSString *l = [seg labelForSegment:i];
                if (l.length > 0) [seg setLabel:tz(l) forSegment:i];
            }
        }
    } @catch (NSException *e) { }
}

static void walkView(NSView *v) {
    if (!v) return;
    if ([v isKindOfClass:[NSControl class]]) {
        walkControl((NSControl *)v);
    } else if ([v isKindOfClass:[NSBox class]]) {
        NSString *t = [(NSBox *)v title];
        if (t.length > 0) [(NSBox *)v setTitle:tz(t)];
    } else if ([v isKindOfClass:[NSTabView class]]) {
        for (NSTabViewItem *item in [(NSTabView *)v tabViewItems]) {
            if (item.label.length > 0) item.label = tz(item.label);
            walkView(item.view);
        }
    }
    for (NSView *s in [v.subviews copy]) walkView(s);
}

// 合并短时间内多次触发，避免频繁遍历；启动完成前不遍历，避免干扰主菜单构建
static void scheduleWindowWalk(NSWindow *w) {
    if (!w) return;
    static CFAbsoluteTime start = 0;
    if (start == 0) start = CFAbsoluteTimeGetCurrent();
    if (CFAbsoluteTimeGetCurrent() - start < 1.5) return; // 启动初期跳过
    static BOOL pending = NO;
    if (pending) return;
    pending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        pending = NO;
        if (!w.contentView) return;
        @try {
            walkView(w.contentView);
            if (w.title.length > 0) w.title = tz(w.title);
        } @catch (NSException *e) { }
    });
}

@implementation NSWindow (TZWalk)
- (void)tz_makeKeyAndOrderFront:(id)sender {
    [self tz_makeKeyAndOrderFront:sender];
    scheduleWindowWalk(self);
}
- (void)tz_orderFront:(id)sender {
    [self tz_orderFront:sender];
    scheduleWindowWalk(self);
}
@end

#pragma mark - 初始化

__attribute__((constructor))
static void tz_init(void) {
    @try {
        NSString *path = [[NSBundle mainBundle] pathForResource:@"zh_dict" ofType:@"plist"];
        if (!path) return;
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:path];
        exactDict = [d[@"exact"] copy];
        prefixDict = [d[@"prefix"] copy];
        NSMutableDictionary *ld = [NSMutableDictionary dictionary];
        [exactDict enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) {
            ld[k.lowercaseString] = v;
        }];
        lowerDict = ld;

        swizzle([NSMenuItem class], @selector(setTitle:), @selector(tz_setTitle:));
        swizzle([NSMenuItem class], @selector(initWithTitle:action:keyEquivalent:), @selector(tz_initWithTitle:action:keyEquivalent:));
        swizzle([NSMenu class], @selector(initWithTitle:), @selector(tz_initWithTitle:));
        swizzle([NSMenu class], @selector(addItemWithTitle:action:keyEquivalent:), @selector(tz_addItemWithTitle:action:keyEquivalent:));
        swizzle([NSWindow class], @selector(setTitle:), @selector(tz_setTitle:));
        swizzle([NSButton class], @selector(setTitle:), @selector(tz_setTitle:));
        swizzle([NSButton class], @selector(initWithTitle:target:action:), @selector(tz_initWithTitle:target:action:));
        swizzle([NSControl class], @selector(setStringValue:), @selector(tz_setStringValue:));
        swizzleClassMethod([NSTextField class], @selector(labelWithString:), @selector(tz_labelWithString:));
        swizzleClassMethod([NSTextField class], @selector(textFieldWithString:), @selector(tz_textFieldWithString:));
        swizzleClassMethod([NSTextField class], @selector(wrappingLabelWithString:), @selector(tz_wrappingLabelWithString:));
        swizzle([NSBox class], @selector(setTitle:), @selector(tz_setTitle:));
        swizzle([NSTabViewItem class], @selector(setLabel:), @selector(tz_setLabel:));
        swizzle([NSSegmentedControl class], @selector(setLabel:forSegment:), @selector(tz_setLabel:forSegment:));
        swizzle([NSPopUpButton class], @selector(addItemWithTitle:), @selector(tz_addItemWithTitle:));
        swizzle([NSPopUpButton class], @selector(addItemsWithTitles:), @selector(tz_addItemsWithTitles:));
        swizzle([UNMutableNotificationContent class], @selector(setTitle:), @selector(tz_setTitle:));
        swizzle([UNMutableNotificationContent class], @selector(setBody:), @selector(tz_setBody:));
        // 视图树兜底遍历
        swizzle([NSWindow class], @selector(makeKeyAndOrderFront:), @selector(tz_makeKeyAndOrderFront:));
        swizzle([NSWindow class], @selector(orderFront:), @selector(tz_orderFront:));
    } @catch (NSException *e) {
        // 出错时静默，不影响应用
    }
}
