//
//  FriendsTimelineController.m
//  TwitterFon
//
//  Created by kaz on 10/29/08.
//  Copyright 2008 naan studio. All rights reserved.
//

#import "FriendsTimelineController.h"
#import "FriendsTimelineDataSource.h"
#import "TwitterFonAppDelegate.h"
#import "ColorUtils.h"

@interface FriendsTimelineController (Private)
- (void)scrollToFirstUnread:(NSTimer*)timer;
- (void)didLeaveTab:(UINavigationController*)navigationController;
@end


@implementation FriendsTimelineController

//
// UIViewController methods
//
- (void)viewDidLoad
{
    if (!isLoaded) {
        [self loadTimeline];
    }
    self.tableView.dataSource = currentDataSource;
    self.tableView.delegate   = currentDataSource;
}

- (void) dealloc
{
    [super dealloc];
}

- (void)viewWillAppear:(BOOL)animated 
{
    [super viewWillAppear:animated];
    
    [self.tableView setContentOffset:contentOffset animated:false];
    [self.tableView reloadData];
    self.navigationController.navigationBar.tintColor = [UIColor navigationColorForTab:tab];
    self.tableView.separatorColor = [UIColor lightGrayColor]; 
  
}

- (void)viewDidAppear:(BOOL)animated
{
    if (firstTimeToAppear) {
        firstTimeToAppear = false;
        [self scrollToFirstUnread:nil];
    }
	[super viewDidAppear:animated];
    if (stopwatch) {
        LAP(stopwatch, @"viewDidAppear");
        [stopwatch release];
        stopwatch = nil;
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    contentOffset = self.tableView.contentOffset;
}

- (void)viewDidDisappear:(BOOL)animated 
{
}

- (void)didReceiveMemoryWarning 
{
    TwitterFonAppDelegate *appDelegate = (TwitterFonAppDelegate*)[UIApplication sharedApplication].delegate;
    if (appDelegate.selectedTab != [self navigationController].tabBarItem.tag) {
        [super didReceiveMemoryWarning];
    }
}

//
// Public methods
//
- (void)loadTimeline
{
    NSString *username = [[NSUserDefaults standardUserDefaults] stringForKey:@"username"];
    NSString *password = [[NSUserDefaults standardUserDefaults] stringForKey:@"password"];
    if (!(username == nil || password == nil ||
          [username length] == 0 || [password length] == 0)) {
        self.navigationItem.leftBarButtonItem.enabled = false;
        [currentDataSource getTimeline];
    }
    isLoaded = true;
}

- (void)restoreAndLoadTimeline:(BOOL)load
{
    firstTimeToAppear = true;
    stopwatch = [[Stopwatch alloc] init];
    tab       = [self navigationController].tabBarItem.tag;
    timelineDataSource = [[FriendsTimelineDataSource alloc] initWithController:self messageType:tab];
    currentDataSource = timelineDataSource;
    if (load) [self loadTimeline];

}

- (IBAction) reload: (id) sender
{
    self.navigationItem.leftBarButtonItem.enabled = false;
    [currentDataSource getTimeline];
}

- (IBAction) segmentDidChange:(id)sender
{
    UISegmentedControl* control = (UISegmentedControl*)sender;
    currentDataSource.contentOffset = self.tableView.contentOffset;
    if (control.selectedSegmentIndex == 0) {
        currentDataSource         = timelineDataSource;
        self.tableView.dataSource = timelineDataSource;
        self.tableView.delegate   = timelineDataSource;
    }
    else {
        if (sentMessageDataSource == nil) {
            sentMessageDataSource = [[FriendsTimelineDataSource alloc] initWithController:self messageType:MSG_TYPE_SENT];
            [sentMessageDataSource getTimeline];
        }
        currentDataSource         = sentMessageDataSource;
        self.tableView.dataSource = sentMessageDataSource;
        self.tableView.delegate   = sentMessageDataSource;
    }
    [self.tableView setContentOffset:currentDataSource.contentOffset animated:false];
    [self didLeaveTab:self.navigationController];
    [self.tableView reloadData];
    [self.tableView flashScrollIndicators];
}

- (void)postViewAnimationDidFinish
{
    if (self.navigationController.topViewController != self) return;
    
    
    if (tab == TAB_FRIENDS || (tab == TAB_MESSAGES && sentMessageDataSource == currentDataSource)) {
        //
        // Do animation if the controller displays friends timeline or sent direct messages.
        //
        NSArray *indexPaths = [NSArray arrayWithObjects:[NSIndexPath indexPathForRow:0 inSection:0], nil];
        [self.tableView beginUpdates];
        [self.tableView insertRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationTop];
        [self.tableView endUpdates];
    }
        
}

- (void)postTweetDidSucceed:(NSDictionary*)dic
{
    Message *message;
    if (tab == TAB_FRIENDS) {
        message = [Message messageWithJsonDictionary:dic type:MSG_TYPE_FRIENDS];
        [currentDataSource.timeline insertMessage:message atIndex:0];
    }
    else if (tab == TAB_MESSAGES && sentMessageDataSource) {
        message = [Message messageWithJsonDictionary:dic type:MSG_TYPE_SENT];
        [sentMessageDataSource.timeline insertMessage:message atIndex:0];
    }
    [message insertDB];
}


//
// TwitterFonApPDelegate delegate
//
- (void)didLeaveTab:(UINavigationController*)navigationController
{
    navigationController.tabBarItem.badgeValue = nil;
    for (int i = 0; i < [currentDataSource.timeline countMessages]; ++i) {
        Message* m = [currentDataSource.timeline messageAtIndex:i];
        m.unread = false;
    }
    unread = 0;
}


- (void) removeMessage:(Message*)message
{
    [currentDataSource.timeline removeMessage:message];
    [self.tableView reloadData];
}

- (void) updateFavorite:(Message*)message
{
    [currentDataSource.timeline updateFavorite:message];
}

- (void)scrollToFirstUnread:(NSTimer*)timer
{
    if (unread) {
        if (unread < [currentDataSource.timeline countMessages]) {
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:unread inSection:0];
            [self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition: UITableViewScrollPositionBottom animated:true];
        }
    }
}

//
// TimelineDelegate
//
- (void)timelineDidUpdate:(FriendsTimelineDataSource*)sender count:(int)count insertAt:(int)position
{
    self.navigationItem.leftBarButtonItem.enabled = true;

    if (self.navigationController.tabBarController.selectedIndex == tab &&
        self.navigationController.topViewController == self &&
        sender == currentDataSource) {

        [self.tableView beginUpdates];
        if (position) {
            NSMutableArray *deletion = [[[NSMutableArray alloc] init] autorelease];
            [deletion addObject:[NSIndexPath indexPathForRow:position inSection:0]];
            [self.tableView deleteRowsAtIndexPaths:deletion withRowAnimation:UITableViewRowAnimationBottom];
        }
        if (count != 0) {
            NSMutableArray *insertion = [[[NSMutableArray alloc] init] autorelease];
            
            int numInsert = count;
            // Avoid to create too many table cell.
            if (numInsert > 8) numInsert = 8;
            for (int i = 0; i < numInsert; ++i) {
                [insertion addObject:[NSIndexPath indexPathForRow:position + i inSection:0]];
            }        
            [self.tableView insertRowsAtIndexPaths:insertion withRowAnimation:UITableViewRowAnimationTop];
        }
        [self.tableView endUpdates];

        if (position == 0 && unread == 0) {
            [NSTimer scheduledTimerWithTimeInterval:0.4 target:self selector:@selector(scrollToFirstUnread:) userInfo:nil repeats:false];
        }
    }
    if (count) {
        unread += count;
        [self navigationController].tabBarItem.badgeValue = [NSString stringWithFormat:@"%d", unread];
    }

}

- (void)timelineDidFailToUpdate:(FriendsTimelineDataSource*)sender position:(int)position
{
    self.navigationItem.leftBarButtonItem.enabled = true;
}
@end
