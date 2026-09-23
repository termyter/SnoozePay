// TEMPORARY measurement for #814 — removed before the PR is ready.
//
// Prints, key names only (never values), how the app's persistent defaults
// domain moves across the test run:
//   #814 DEFAULTS <point> keys=[...]            full set, at the anchor points
//   #814 DEFAULTS <point> +[added] -[removed] ~[changed]   only when it moved
//
// Objective-C because `+load` is the only hook that runs when the test bundle
// is loaded without an `NSPrincipalClass` key in the (generated) Info.plist:
// the snapshot there precedes everything, including the host app's launch.

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

@interface DefaultsDomainCensus814 : NSObject <XCTestObservation>
@property (nonatomic, copy) NSDictionary<NSString *, id> *last;
@end

static DefaultsDomainCensus814 *census814;

@implementation DefaultsDomainCensus814

+ (void)load {
    census814 = [DefaultsDomainCensus814 new];
    census814.last = @{};
    [census814 report:@"<bundle +load>" full:YES];
    [[XCTestObservationCenter sharedTestObservationCenter] addTestObserver:census814];
}

- (NSString *)domainName {
    NSString *identifier = [[NSBundle mainBundle] bundleIdentifier];
    return identifier.length > 0 ? identifier : @"io.mobilife.SnoozePay";
}

- (NSString *)joined:(NSArray<NSString *> *)keys {
    return [NSString stringWithFormat:@"[%@]",
            [[keys sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@", "]];
}

- (void)report:(NSString *)point full:(BOOL)full {
    NSDictionary<NSString *, id> *now =
        [[NSUserDefaults standardUserDefaults] persistentDomainForName:[self domainName]] ?: @{};
    NSMutableArray<NSString *> *added = [NSMutableArray array];
    NSMutableArray<NSString *> *removed = [NSMutableArray array];
    NSMutableArray<NSString *> *changed = [NSMutableArray array];
    for (NSString *key in now) {
        id old = self.last[key];
        if (old == nil) {
            [added addObject:key];
        } else if (![old isEqual:now[key]]) {
            [changed addObject:key];
        }
    }
    for (NSString *key in self.last) {
        if (now[key] == nil) {
            [removed addObject:key];
        }
    }
    self.last = now;
    NSString *line = nil;
    if (full) {
        line = [NSString stringWithFormat:@"#814 DEFAULTS %@ domain=%@ keys=%@ +%@ -%@ ~%@",
                point, [self domainName], [self joined:now.allKeys],
                [self joined:added], [self joined:removed], [self joined:changed]];
    } else if (added.count > 0 || removed.count > 0 || changed.count > 0) {
        line = [NSString stringWithFormat:@"#814 DEFAULTS %@ +%@ -%@ ~%@",
                point, [self joined:added], [self joined:removed], [self joined:changed]];
    }
    if (line != nil) {
        printf("%s\n", line.UTF8String);
        fflush(stdout);
    }
}

- (void)testBundleWillStart:(NSBundle *)testBundle {
    [self report:@"<testBundleWillStart>" full:YES];
}

- (void)testBundleDidFinish:(NSBundle *)testBundle {
    [self report:@"<testBundleDidFinish>" full:YES];
}

- (void)testSuiteWillStart:(XCTestSuite *)testSuite {
    [self report:[NSString stringWithFormat:@"<suiteWillStart %@>", testSuite.name] full:NO];
}

- (void)testSuiteDidFinish:(XCTestSuite *)testSuite {
    [self report:[NSString stringWithFormat:@"<suiteDidFinish %@>", testSuite.name] full:NO];
}

- (void)testCaseWillStart:(XCTestCase *)testCase {
    [self report:[NSString stringWithFormat:@"<before %@>", testCase.name] full:NO];
}

- (void)testCaseDidFinish:(XCTestCase *)testCase {
    [self report:testCase.name full:NO];
}

@end
