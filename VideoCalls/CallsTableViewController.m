//
//  CallsTableViewController.m
//  VideoCalls
//
//  Created by Ivan Sein on 27.06.17.
//  Copyright © 2017 struktur AG. All rights reserved.
//

#import "CallsTableViewController.h"

#import "AFNetworking.h"
#import "AuthenticationViewController.h"
#import "LoginViewController.h"
#import "NCAPIController.h"
#import "NCConnectionController.h"
#import "NCSettingsController.h"

@interface CallsTableViewController ()
{
    NSMutableArray *_rooms;
    BOOL _networkDisconnectedRetry;
    UIRefreshControl *_refreshControl;
}

@end

@implementation CallsTableViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    _rooms = [[NSMutableArray alloc] init];
    _networkDisconnectedRetry = NO;
    
    [self createRefreshControl];
    
    UIImage *image = [UIImage imageNamed:@"navigationLogo"];
    self.navigationItem.titleView = [[UIImageView alloc] initWithImage:image];
    self.navigationController.navigationBar.barTintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    self.tabBarController.tabBar.tintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loginHasBeenCompleted:) name:NCLoginCompletedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(networkReachabilityHasChanged:) name:NCNetworkReachabilityHasChangedNotification object:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidAppear:(BOOL)animated
{
    [self checkConnectionState];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Notifications

- (void)loginHasBeenCompleted:(NSNotification *)notification
{
    if ([notification.userInfo objectForKey:kNCTokenKey]) {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)networkReachabilityHasChanged:(NSNotification *)notification
{
    AFNetworkReachabilityStatus status = [[notification.userInfo objectForKey:kNCNetworkReachabilityKey] intValue];
    NSLog(@"Network Status:%ld", (long)status);
}

#pragma mark - Refresh Control

- (void)createRefreshControl
{
    _refreshControl = [UIRefreshControl new];
    _refreshControl.tintColor = [UIColor colorWithRed:0.00 green:0.51 blue:0.79 alpha:1.0]; //#0082C9
    _refreshControl.backgroundColor = [UIColor colorWithRed:235.0/255.0 green:235.0/255.0 blue:235.0/255.0 alpha:1.0];
    [_refreshControl addTarget:self action:@selector(refreshControlTarget) forControlEvents:UIControlEventValueChanged];
    [self setRefreshControl:_refreshControl];
}

- (void)deleteRefreshControl
{
    [_refreshControl endRefreshing];
    self.refreshControl = nil;
}

- (void)refreshControlTarget
{
    [self getRooms];
    
    // Actuate `Peek` feedback (weak boom)
    AudioServicesPlaySystemSound(1519);
}

#pragma mark - Rooms

- (void)checkConnectionState
{
    ConnectionState connectionState = [[NCConnectionController sharedInstance] connectionState];
    
    switch (connectionState) {
        case kConnectionStateNotServerProvided:
        {
            LoginViewController *loginVC = [[LoginViewController alloc] init];
            [self presentViewController:loginVC animated:YES completion:nil];
        }
            break;
        case kConnectionStateAuthenticationNeeded:
        {
            AuthenticationViewController *authVC = [[AuthenticationViewController alloc] init];
            [self presentViewController:authVC animated:YES completion:nil];
        }
            break;
            
        case kConnectionStateNetworkDisconnected:
        {
            NSLog(@"No network connection!");
            if (!_networkDisconnectedRetry) {
                _networkDisconnectedRetry = YES;
                double delayInSeconds = 1.0;
                dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
                dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
                    [self checkConnectionState];
                });
            }
        }
            break;
            
        default:
        {
            [self getRooms];
            _networkDisconnectedRetry = NO;
        }
            break;
    }
}

- (void)getRooms
{
    [[NCAPIController sharedInstance] getRoomsWithCompletionBlock:^(NSMutableArray *rooms, NSError *error, NSInteger errorCode) {
        if (!error) {
            _rooms = rooms;
            [self.tableView reloadData];
            NSLog(@"Rooms updated");
        } else {
            NSLog(@"Error while trying to get rooms: %@", error);
        }
        
        [_refreshControl endRefreshing];
    }];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return _rooms.count;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return UITableViewCellEditingStyleDelete;
}

- (NSString *)tableView:(UITableView *)tableView titleForSwipeAccessoryButtonForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *moreButtonText = @"More";
    return moreButtonText;
}

- (void)tableView:(UITableView *)tableView swipeAccessoryButtonPushedForRowAtIndexPath:(NSIndexPath *)indexPath
{
    // Show more options for that room.
}

- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *deleteButtonText = @"Leave";
    return deleteButtonText;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NCRoom *room = [_rooms objectAtIndex:indexPath.row];
        [[NCAPIController sharedInstance] removeSelfFromRoom:room.token withCompletionBlock:^(NSError *error, NSInteger errorCode) {
            if (error) {
                // Show alert
            }
        }];
        
        [_rooms removeObjectAtIndex:indexPath.row];
        [tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationFade];
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoom *room = [_rooms objectAtIndex:indexPath.row];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RoomCellIdentifier"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"RoomCellIdentifier"];
        cell.textLabel.text = room.displayName;
    }
    
    return cell;
}


@end
