/**
 * @copyright Copyright (c) 2020 Ivan Sein <ivan@nextcloud.com>
 *
 * @author Ivan Sein <ivan@nextcloud.com>
 *
 * @license GNU GPL version 3 or any later version
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#import "RoomInfoTableViewController.h"

#import <QuickLook/QuickLook.h>

#import "UIImageView+AFNetworking.h"
#import "UIImageView+Letters.h"
#import "UIView+Toast.h"

#import "AddParticipantsTableViewController.h"
#import "ContactsTableViewCell.h"
#import "HeaderWithButton.h"
#import "NCAPIController.h"
#import "NCAppBranding.h"
#import "NCChatFileController.h"
#import "NCDatabaseManager.h"
#import "NCNavigationController.h"
#import "NCRoomsManager.h"
#import "NCRoomParticipant.h"
#import "NCSettingsController.h"
#import "NCUserInterfaceController.h"
#import "NCUtils.h"
#import "RoomNameTableViewCell.h"

typedef enum RoomInfoSection {
    kRoomInfoSectionName = 0,
    kRoomInfoSectionActions,
    kRoomInfoSectionPublic,
    kRoomInfoSectionWebinar,
    kRoomInfoSectionParticipants,
    kRoomInfoSectionDestructive,
    kRoomInfoSectionFile
} RoomInfoSection;

typedef enum RoomAction {
    kRoomActionFavorite = 0,
    kRoomActionNotifications,
    kRoomActionSendLink
} RoomAction;

typedef enum PublicAction {
    kPublicActionPublicToggle = 0,
    kPublicActionPassword,
    kPublicActionResendInvitations
} PublicAction;

typedef enum WebinarAction {
    kWebinarActionLobby = 0,
    kWebinarActionLobbyTimer
} WebinarAction;

typedef enum DestructiveAction {
    kDestructiveActionLeave = 0,
    kDestructiveActionDelete
} DestructiveAction;

typedef enum ModificationError {
    kModificationErrorRename = 0,
    kModificationErrorFavorite,
    kModificationErrorNotifications,
    kModificationErrorShare,
    kModificationErrorPassword,
    kModificationErrorResendInvitations,
    kModificationErrorLobby,
    kModificationErrorModeration,
    kModificationErrorRemove,
    kModificationErrorLeave,
    kModificationErrorLeaveModeration,
    kModificationErrorDelete
} ModificationError;

typedef enum FileAction {
    kFileActionPreview = 0,
    kFileActionOpenInFilesApp
} FileAction;

#define k_set_password_textfield_tag    98

@interface RoomInfoTableViewController () <UITextFieldDelegate, UIGestureRecognizerDelegate, AddParticipantsTableViewControllerDelegate, NCChatFileControllerDelegate, QLPreviewControllerDelegate, QLPreviewControllerDataSource>

@property (nonatomic, strong) NCRoom *room;
@property (nonatomic, strong) NCChatViewController *chatViewController;
@property (nonatomic, strong) NSString *roomName;
@property (nonatomic, strong) NSMutableArray *roomParticipants;
@property (nonatomic, strong) UITextField *roomNameTextField;
@property (nonatomic, strong) UISwitch *publicSwtich;
@property (nonatomic, strong) UISwitch *lobbySwtich;
@property (nonatomic, strong) UIDatePicker *lobbyDatePicker;
@property (nonatomic, strong) UITextField *lobbyDateTextField;
@property (nonatomic, strong) UIActivityIndicatorView *modifyingRoomView;
@property (nonatomic, strong) HeaderWithButton *headerView;
@property (nonatomic, strong) UIAlertAction *setPasswordAction;
@property (nonatomic, strong) UIActivityIndicatorView *fileDownloadIndicator;
@property (nonatomic, strong) NSString *previewControllerFilePath;

@end

@implementation RoomInfoTableViewController

- (instancetype)initForRoom:(NCRoom *)room
{
    return [self initForRoom:room fromChatViewController:nil];
}

- (instancetype)initForRoom:(NCRoom *)room fromChatViewController:(NCChatViewController *)chatViewController
{
    self = [super init];
    if (self) {
        _room = room;
        _chatViewController = chatViewController;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.navigationItem.title = NSLocalizedString(@"Conversation info", nil);
    [self.navigationController.navigationBar setTitleTextAttributes:
     @{NSForegroundColorAttributeName:[NCAppBranding themeTextColor]}];
    self.navigationController.navigationBar.tintColor = [NCAppBranding themeTextColor];
    self.navigationController.navigationBar.translucent = NO;
    self.navigationController.navigationBar.barTintColor = [NCAppBranding themeColor];
    
    if (@available(iOS 13.0, *)) {
        UIColor *themeColor = [NCAppBranding themeColor];
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = themeColor;
        appearance.titleTextAttributes = @{NSForegroundColorAttributeName:[NCAppBranding themeTextColor]};
        self.navigationItem.standardAppearance = appearance;
        self.navigationItem.compactAppearance = appearance;
        self.navigationItem.scrollEdgeAppearance = appearance;
    }
    
    _roomParticipants = [[NSMutableArray alloc] init];
    
    _publicSwtich = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_publicSwtich addTarget: self action: @selector(publicValueChanged:) forControlEvents:UIControlEventValueChanged];
    
    _lobbySwtich = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_lobbySwtich addTarget: self action: @selector(lobbyValueChanged:) forControlEvents:UIControlEventValueChanged];
    
    _lobbyDatePicker = [[UIDatePicker alloc] init];
    _lobbyDatePicker.datePickerMode = UIDatePickerModeDateAndTime;
    _lobbyDateTextField = [[UITextField alloc] initWithFrame:CGRectMake(0, 00, 150, 30)];
    _lobbyDateTextField.textAlignment = NSTextAlignmentRight;
    _lobbyDateTextField.placeholder = NSLocalizedString(@"Manual", nil);
    _lobbyDateTextField.adjustsFontSizeToFitWidth = YES;
    _lobbyDateTextField.minimumFontSize = 9;
    [_lobbyDateTextField setInputView:_lobbyDatePicker];
    [self setupLobbyDatePicker];
    
    _modifyingRoomView = [[UIActivityIndicatorView alloc] init];
    _modifyingRoomView.color = [NCAppBranding themeTextColor];
    
    _headerView = [[HeaderWithButton alloc] init];
    [_headerView.button setTitle:NSLocalizedString(@"Add", nil) forState:UIControlStateNormal];
    [_headerView.button addTarget:self action:@selector(addParticipantsButtonPressed) forControlEvents:UIControlEventTouchUpInside];
    
    [self.tableView registerNib:[UINib nibWithNibName:kContactsTableCellNibName bundle:nil] forCellReuseIdentifier:kContactCellIdentifier];
    [self.tableView registerNib:[UINib nibWithNibName:kRoomNameTableCellNibName bundle:nil] forCellReuseIdentifier:kRoomNameCellIdentifier];
    
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tap.delegate = self;
    [self.view addGestureRecognizer:tap];
    
    if (!_chatViewController) {
        UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                      target:self action:@selector(cancelButtonPressed)];
        self.navigationController.navigationBar.topItem.leftBarButtonItem = cancelButton;
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didUpdateRoom:) name:NCRoomsManagerDidUpdateRoomNotification object:nil];
}

- (void)viewDidAppear:(BOOL)animated
{
    [[NCRoomsManager sharedInstance] updateRoom:_room.token];
    [self getRoomParticipants];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)dismissKeyboard
{
    [_roomNameTextField resignFirstResponder];
}

- (void)cancelButtonPressed
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Utils

- (void)getRoomParticipants
{
    [[NCAPIController sharedInstance] getParticipantsFromRoom:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSMutableArray *participants, NSError *error) {
        self->_roomParticipants = participants;
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange([self getSectionForRoomInfoSection:kRoomInfoSectionParticipants], 1)] withRowAnimation:UITableViewRowAnimationNone];
        [self removeModifyingRoomUI];
    }];
}

- (NSArray *)getRoomInfoSections
{
    NSMutableArray *sections = [[NSMutableArray alloc] init];
    // Room name section
    [sections addObject:[NSNumber numberWithInt:kRoomInfoSectionName]];
    // Room actions section
    [sections addObject:[NSNumber numberWithInt:kRoomInfoSectionActions]];
    // File actions section
    if ([_room.objectType isEqualToString:NCRoomObjectTypeFile]) {
        [sections addObject:[NSNumber numberWithInt:kRoomInfoSectionFile]];
    }
    // Moderator sections
    if (_room.canModerate) {
        // Public room section
        [sections addObject:[NSNumber numberWithInt:kRoomInfoSectionPublic]];
        // Webinar section
        if (_room.type != kNCRoomTypeOneToOne && [[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityWebinaryLobby]) {
            [sections addObject:[NSNumber numberWithInt:kRoomInfoSectionWebinar]];
        }
    }
    // Participants section
    [sections addObject:[NSNumber numberWithInt:kRoomInfoSectionParticipants]];
    // Destructive actions section
    if (!_chatViewController || !_chatViewController.presentedInCall) {
        // Do not show destructive actions when chat is presented during a call
        [sections addObject:[NSNumber numberWithInt:kRoomInfoSectionDestructive]];
    }
    return [NSArray arrayWithArray:sections];
}

- (NSInteger)getSectionForRoomInfoSection:(RoomInfoSection)section
{
    NSInteger sectionNumber = [[self getRoomInfoSections] indexOfObject:[NSNumber numberWithInt:section]];
    if(NSNotFound != sectionNumber) {
        return sectionNumber;
    }
    return 0;
}

- (NSArray *)getRoomActions
{
    NSMutableArray *actions = [[NSMutableArray alloc] init];
    // Favorite action
    [actions addObject:[NSNumber numberWithInt:kRoomActionFavorite]];
    // Notification levels action
    if ([[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilityNotificationLevels]) {
        [actions addObject:[NSNumber numberWithInt:kRoomActionNotifications]];
    }
    // Public room actions
    if (_room.isPublic) {
        [actions addObject:[NSNumber numberWithInt:kRoomActionSendLink]];
    }
    
    return [NSArray arrayWithArray:actions];
}

- (NSIndexPath *)getIndexPathForRoomAction:(RoomAction)action
{
    NSInteger section = [self getSectionForRoomInfoSection:kRoomInfoSectionActions];
    NSIndexPath *actionIndexPath = [NSIndexPath indexPathForRow:0 inSection:section];
    NSInteger actionRow = [[self getRoomActions] indexOfObject:[NSNumber numberWithInt:action]];
    if(NSNotFound != actionRow) {
        actionIndexPath = [NSIndexPath indexPathForRow:actionRow inSection:section];
    }
    return actionIndexPath;
}

- (NSArray *)getFileActions
{
    NSMutableArray *actions = [[NSMutableArray alloc] init];
    // File preview
    [actions addObject:[NSNumber numberWithInt:kFileActionPreview]];
    // Open file in nextcloud app
    [actions addObject:[NSNumber numberWithInt:kFileActionOpenInFilesApp]];
    
    return [NSArray arrayWithArray:actions];
}

- (NSArray *)getPublicActions
{
    NSMutableArray *actions = [[NSMutableArray alloc] init];
    // Public room toggle
    [actions addObject:[NSNumber numberWithInt:kPublicActionPublicToggle]];
    // Password protection
    if (_room.isPublic) {
        [actions addObject:[NSNumber numberWithInt:kPublicActionPassword]];
    }
    // Resend invitations
    if (_room.isPublic && [[NCDatabaseManager sharedInstance] serverHasTalkCapability:kCapabilitySIPSupport]) {
        [actions addObject:[NSNumber numberWithInt:kPublicActionResendInvitations]];
    }
    return [NSArray arrayWithArray:actions];
}

- (NSArray *)getWebinarActions
{
    NSMutableArray *actions = [[NSMutableArray alloc] init];
    // Lobby toggle
    [actions addObject:[NSNumber numberWithInt:kWebinarActionLobby]];
    // Lobby timer
    if (_room.lobbyState == NCRoomLobbyStateModeratorsOnly) {
        [actions addObject:[NSNumber numberWithInt:kWebinarActionLobbyTimer]];
    }
    return [NSArray arrayWithArray:actions];
}

- (NSArray *)getRoomDestructiveActions
{
    NSMutableArray *actions = [[NSMutableArray alloc] init];
    // Leave room
    if (_room.isLeavable) {
        [actions addObject:[NSNumber numberWithInt:kDestructiveActionLeave]];
    }
    // Delete room
    if (_room.canModerate) {
        [actions addObject:[NSNumber numberWithInt:kDestructiveActionDelete]];
    }
    return [NSArray arrayWithArray:actions];
}

- (BOOL)isAppUser:(NCRoomParticipant *)participant
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    if ([participant.participantId isEqualToString:activeAccount.userId]) {
        return YES;
    }
    return NO;
}

- (void)setModifyingRoomUI
{
    [_modifyingRoomView startAnimating];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:_modifyingRoomView];
    self.tableView.userInteractionEnabled = NO;
}

- (void)removeModifyingRoomUI
{
    [_modifyingRoomView stopAnimating];
    self.navigationItem.rightBarButtonItem = nil;
    self.tableView.userInteractionEnabled = YES;
}

- (void)showRoomModificationError:(ModificationError)error
{
    [self removeModifyingRoomUI];
    NSString *errorDescription = @"";
    switch (error) {
        case kModificationErrorRename:
            errorDescription = NSLocalizedString(@"Could not rename the conversation", nil);
            break;
            
        case kModificationErrorFavorite:
            errorDescription = NSLocalizedString(@"Could not change favorite setting", nil);
            break;
            
        case kModificationErrorNotifications:
            errorDescription = NSLocalizedString(@"Could not change notifications setting", nil);
            break;
            
        case kModificationErrorShare:
            errorDescription = NSLocalizedString(@"Could not change sharing permissions of the conversation", nil);
            break;
            
        case kModificationErrorPassword:
            errorDescription = NSLocalizedString(@"Could not change password protection settings", nil);
            break;
            
        case kModificationErrorResendInvitations:
            errorDescription = NSLocalizedString(@"Could not resend email invitations", nil);
            break;
            
        case kModificationErrorLobby:
            errorDescription = NSLocalizedString(@"Could not change lobby state of the conversation", nil);
            break;
            
        case kModificationErrorModeration:
            errorDescription = NSLocalizedString(@"Could not change moderation permissions of the participant", nil);
            break;
            
        case kModificationErrorRemove:
            errorDescription = NSLocalizedString(@"Could not remove participant", nil);
            break;
        
        case kModificationErrorLeave:
            errorDescription = NSLocalizedString(@"Could not leave conversation", nil);
            break;
            
        case kModificationErrorLeaveModeration:
            errorDescription = NSLocalizedString(@"You need to promote a new moderator before you can leave this conversation", nil);
            break;
            
        case kModificationErrorDelete:
            errorDescription = NSLocalizedString(@"Could not delete conversation", nil);
            break;
            
        default:
            break;
    }
    
    UIAlertController *renameDialog =
    [UIAlertController alertControllerWithTitle:errorDescription
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:UIAlertActionStyleDefault handler:nil];
    [renameDialog addAction:okAction];
    [self presentViewController:renameDialog animated:YES completion:nil];
}

- (void)showConfirmationDialogForDestructiveAction:(DestructiveAction)action
{
    NSString *title = @"";
    NSString *message = @"";
    UIAlertAction *confirmAction = nil;
    
    switch (action) {
        case kDestructiveActionLeave:
        {
            title = NSLocalizedString(@"Leave conversation", nil);
            message = NSLocalizedString(@"Do you really want to leave this conversation?", nil);
            confirmAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Leave", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
                [self leaveRoom];
            }];
        }
            break;
        case kDestructiveActionDelete:
        {
            title = NSLocalizedString(@"Delete conversation", nil);
            message = _room.deletionMessage;
            confirmAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Delete", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
                [self deleteRoom];
            }];
        }
            break;
    }
    
    UIAlertController *confirmDialog =
    [UIAlertController alertControllerWithTitle:title
                                        message:message
                                 preferredStyle:UIAlertControllerStyleAlert];
    [confirmDialog addAction:confirmAction];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil];
    [confirmDialog addAction:cancelAction];
    [self presentViewController:confirmDialog animated:YES completion:nil];
}

- (void)presentNotificationLevelSelector
{
    UIAlertController *optionsActionSheet =
    [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Notifications", nil)
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleActionSheet];
    [optionsActionSheet addAction:[self actionForNotificationLevel:kNCRoomNotificationLevelAlways]];
    [optionsActionSheet addAction:[self actionForNotificationLevel:kNCRoomNotificationLevelMention]];
    [optionsActionSheet addAction:[self actionForNotificationLevel:kNCRoomNotificationLevelNever]];
    [optionsActionSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    
    // Presentation on iPads
    optionsActionSheet.popoverPresentationController.sourceView = self.tableView;
    optionsActionSheet.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:[self getIndexPathForRoomAction:kRoomActionNotifications]];
    
    [self presentViewController:optionsActionSheet animated:YES completion:nil];
}

- (UIAlertAction *)actionForNotificationLevel:(NCRoomNotificationLevel)level
{
    UIAlertAction *action = [UIAlertAction actionWithTitle:[_room stringForNotificationLevel:level]
                                                     style:UIAlertActionStyleDefault
                                                   handler:^void (UIAlertAction *action) {
                                                       [self setNotificationLevel:level];
                                                   }];
    if (_room.notificationLevel == level) {
        [action setValue:[[UIImage imageNamed:@"checkmark"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
    }
    return action;
}

#pragma mark - Room Manager notifications

- (void)didUpdateRoom:(NSNotification *)notification
{
    [self removeModifyingRoomUI];
    
    NCRoom *room = [notification.userInfo objectForKey:@"room"];
    if (!room || ![room.token isEqualToString:_room.token]) {
        return;
    }
    
    _room = room;
    [self setupLobbyDatePicker];
    [self.tableView reloadData];
}

#pragma mark - Room options

- (void)renameRoom
{
    NSString *newRoomName = [_roomNameTextField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([newRoomName isEqualToString:_room.name]) {
        return;
    }
    if ([newRoomName isEqualToString:@""]) {
        _roomNameTextField.text = _room.name;
        return;
    }
    [self setModifyingRoomUI];
    [[NCAPIController sharedInstance] renameRoom:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withName:newRoomName andCompletionBlock:^(NSError *error) {
        if (!error) {
            [[NCRoomsManager sharedInstance] updateRoom:self->_room.token];
        } else {
            NSLog(@"Error renaming the room: %@", error.description);
            [self.tableView reloadData];
            [self showRoomModificationError:kModificationErrorRename];
        }
    }];
}

- (void)addRoomToFavorites
{
    [self setModifyingRoomUI];
    [[NCAPIController sharedInstance] addRoomToFavorites:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
        if (!error) {
            [[NCRoomsManager sharedInstance] updateRoom:self->_room.token];
        } else {
            NSLog(@"Error adding the room to favorites: %@", error.description);
            [self.tableView reloadData];
            [self showRoomModificationError:kModificationErrorFavorite];
        }
    }];
}

- (void)removeRoomFromFavorites
{
    [self setModifyingRoomUI];
    [[NCAPIController sharedInstance] removeRoomFromFavorites:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
        if (!error) {
            [[NCRoomsManager sharedInstance] updateRoom:self->_room.token];
        } else {
            NSLog(@"Error removing the room from favorites: %@", error.description);
            [self.tableView reloadData];
            [self showRoomModificationError:kModificationErrorFavorite];
        }
    }];
}

- (void)setNotificationLevel:(NCRoomNotificationLevel)level
{
    if (level == _room.notificationLevel) {
        return;
    }
    [self setModifyingRoomUI];
    [[NCAPIController sharedInstance] setNotificationLevel:level forRoom:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
        if (!error) {
            [[NCRoomsManager sharedInstance] updateRoom:self->_room.token];
        } else {
            NSLog(@"Error setting room notification level: %@", error.description);
            [self.tableView reloadData];
            [self showRoomModificationError:kModificationErrorNotifications];
        }
    }];
}

- (void)showPasswordOptions
{
    NSString *alertTitle = _room.hasPassword ? NSLocalizedString(@"Set new password:", nil) : NSLocalizedString(@"Set password:", nil);
    UIAlertController *passwordDialog =
    [UIAlertController alertControllerWithTitle:alertTitle
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    __weak typeof(self) weakSelf = self;
    [passwordDialog addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = NSLocalizedString(@"Password", nil);
        textField.secureTextEntry = YES;
        textField.delegate = weakSelf;
        textField.tag = k_set_password_textfield_tag;
    }];
    
    NSString *actionTitle = _room.hasPassword ? NSLocalizedString(@"Change password", nil) : NSLocalizedString(@"OK", nil);
    _setPasswordAction = [UIAlertAction actionWithTitle:actionTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *password = [[passwordDialog textFields][0] text];
        NSString *trimmedPassword = [password stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        [self setModifyingRoomUI];
        [[NCAPIController sharedInstance] setPassword:trimmedPassword toRoom:self->_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
            if (!error) {
                [[NCRoomsManager sharedInstance] updateRoom:self->_room.token];
            } else {
                NSLog(@"Error setting room password: %@", error.description);
                [self.tableView reloadData];
                [self showRoomModificationError:kModificationErrorPassword];
            }
        }];
    }];
    _setPasswordAction.enabled = NO;
    [passwordDialog addAction:_setPasswordAction];
    
    if (_room.hasPassword) {
        UIAlertAction *removePasswordAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Remove password", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            [self setModifyingRoomUI];
            [[NCAPIController sharedInstance] setPassword:@"" toRoom:self->_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
                if (!error) {
                    [[NCRoomsManager sharedInstance] updateRoom:self->_room.token];
                } else {
                    NSLog(@"Error changing room password: %@", error.description);
                    [self.tableView reloadData];
                    [self showRoomModificationError:kModificationErrorPassword];
                }
            }];
        }];
        [passwordDialog addAction:removePasswordAction];
    }
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil];
    [passwordDialog addAction:cancelAction];
    
    [self presentViewController:passwordDialog animated:YES completion:nil];
}

- (void)resendInvitations
{
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:kPublicActionResendInvitations inSection:kRoomInfoSectionPublic];
    [self resendInvitationToParticipant:nil fromIndexPath:indexPath];
}

- (void)resendInvitationToParticipant:(NSString *)participant fromIndexPath:(NSIndexPath *)indexPath
{
    [self setModifyingRoomUI];
    [[NCAPIController sharedInstance] resendInvitationToParticipant:participant inRoom:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
        if (!error) {
            [[NCRoomsManager sharedInstance] updateRoom:self->_room.token];
            NSString *toastText = participant ? NSLocalizedString(@"Invitation resent", nil) : NSLocalizedString(@"Invitations resent", nil);
            UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
            CGPoint toastPosition = CGPointMake(cell.center.x, cell.center.y);
            [self.view makeToast:toastText duration:1.5 position:@(toastPosition)];
        } else {
            NSLog(@"Error resending email invitations: %@", error.description);
            [self.tableView reloadData];
            [self showRoomModificationError:kModificationErrorResendInvitations];
        }
    }];
}

- (void)makeRoomPublic
{
    [self setModifyingRoomUI];
    [[NCAPIController sharedInstance] makeRoomPublic:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
        if (!error) {
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:kPublicActionPublicToggle inSection:[self getSectionForRoomInfoSection:kRoomInfoSectionPublic]];
            [self shareRoomLinkFromIndexPath:indexPath];
            [[NCRoomsManager sharedInstance] updateRoom:self->_room.token];
        } else {
            NSLog(@"Error making public the room: %@", error.description);
            [self.tableView reloadData];
            [self showRoomModificationError:kModificationErrorShare];
        }
        self->_publicSwtich.enabled = YES;
    }];
}

- (void)makeRoomPrivate
{
    [self setModifyingRoomUI];
    [[NCAPIController sharedInstance] makeRoomPrivate:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
        if (!error) {
            [[NCRoomsManager sharedInstance] updateRoom:self->_room.token];
        } else {
            NSLog(@"Error making private the room: %@", error.description);
            [self.tableView reloadData];
            [self showRoomModificationError:kModificationErrorShare];
        }
        self->_publicSwtich.enabled = YES;
    }];
}

- (void)shareRoomLinkFromIndexPath:(NSIndexPath *)indexPath
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    NSString *joinConversationString = NSLocalizedString(@"Join the conversation at", nil);
    if (_room.name && ![_room.name isEqualToString:@""]) {
        joinConversationString = [NSString stringWithFormat:NSLocalizedString(@"Join the conversation %@ at", nil), [NSString stringWithFormat:@"\"%@\"", _room.name]];
    }
    NSString *shareMessage = [NSString stringWithFormat:@"%@ %@/index.php/call/%@", joinConversationString, activeAccount.server, _room.token];
    NSArray *items = @[shareMessage];
    UIActivityViewController *controller = [[UIActivityViewController alloc]initWithActivityItems:items applicationActivities:nil];
    
    NSString *appDisplayName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDisplayName"];
    NSString *emailSubject = [NSString stringWithFormat:NSLocalizedString(@"%@ invitation", nil), appDisplayName];
    [controller setValue:emailSubject forKey:@"subject"];
    
    // Presentation on iPads
    controller.popoverPresentationController.sourceView = self.tableView;
    controller.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:indexPath];
    
    [self presentViewController:controller animated:YES completion:nil];
    
    controller.completionWithItemsHandler = ^(NSString *activityType,
                                              BOOL completed,
                                              NSArray *returnedItems,
                                              NSError *error) {
        if (error) {
            NSLog(@"An Error occured sharing room: %@, %@", error.localizedDescription, error.localizedFailureReason);
        }
    };
}

- (void)previewRoomFile:(NSIndexPath *)indexPath
{
    if (_fileDownloadIndicator) {
        // Already downloading a file
        return;
    }
    
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    _fileDownloadIndicator = [[UIActivityIndicatorView alloc] initWithFrame:CGRectMake(0, 0, 24, 24)];
    
    [_fileDownloadIndicator startAnimating];
    [cell setAccessoryView:_fileDownloadIndicator];
    
    NCChatFileController *downloader = [[NCChatFileController alloc] init];
    downloader.delegate = self;
    [downloader downloadFileWithFileId:_room.objectId];
}

- (void)openRoomFileInFilesApp:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    UIActivityIndicatorView *activityIndicator = [[UIActivityIndicatorView alloc] initWithFrame:CGRectMake(0, 0, 24, 24)];
    
    [activityIndicator startAnimating];
    [cell setAccessoryView:activityIndicator];
    
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    
    [[NCAPIController sharedInstance] getFileByFileId:activeAccount fileId:_room.objectId withCompletionBlock:^(NCCommunicationFile *file, NSInteger error, NSString *errorDescription) {

        dispatch_async(dispatch_get_main_queue(), ^{
            [activityIndicator stopAnimating];
            [cell setAccessoryView:nil];
        });
        
        if (file) {
            NSString *remoteDavPrefix = [NSString stringWithFormat:@"/remote.php/dav/files/%@/", activeAccount.userId];
            NSString *directoryPath = [file.path componentsSeparatedByString:remoteDavPrefix].lastObject;
            
            NSString *filePath = [NSString stringWithFormat:@"%@%@", directoryPath, file.fileName];
            NSString *fileLink = [NSString stringWithFormat:@"%@/index.php/f/%@", activeAccount.server, self->_room.objectId];
            
            NSLog(@"File path: %@ fileLink: %@", filePath, fileLink);

            [NCUtils openFileInNextcloudAppOrBrowser:filePath withFileLink:fileLink];
        } else {
            NSLog(@"An error occurred while getting file with fileId %@: %@", self->_room.objectId, errorDescription);
            
            UIAlertController * alert = [UIAlertController
                                         alertControllerWithTitle:NSLocalizedString(@"Unable to open file", nil)
                                         message:[NSString stringWithFormat:NSLocalizedString(@"An error occurred while opening the file %@", nil), self->_room.name]
                                         preferredStyle:UIAlertControllerStyleAlert];
            
            UIAlertAction* okButton = [UIAlertAction
                                       actionWithTitle:NSLocalizedString(@"OK", nil)
                                       style:UIAlertActionStyleDefault
                                       handler:nil];
            
            [alert addAction:okButton];
            
            [[NCUserInterfaceController sharedInstance] presentAlertViewController:alert];
        }
    }];
}

- (void)leaveRoom
{
    [[NCAPIController sharedInstance] removeSelfFromRoom:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSInteger errorCode, NSError *error) {
        if (!error) {
            if (self->_chatViewController) {
                [self->_chatViewController leaveChat];
            }
            [[NCUserInterfaceController sharedInstance] presentConversationsList];
        } else if (errorCode == 400) {
            [self showRoomModificationError:kModificationErrorLeaveModeration];
        } else {
            NSLog(@"Error leaving the room: %@", error.description);
            [self showRoomModificationError:kModificationErrorLeave];
        }
    }];
}

- (void)deleteRoom
{
    [[NCAPIController sharedInstance] deleteRoom:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
        if (!error) {
            if (self->_chatViewController) {
                [self->_chatViewController leaveChat];
            }
            [[NCUserInterfaceController sharedInstance] presentConversationsList];
        } else {
            NSLog(@"Error deleting the room: %@", error.description);
            [self showRoomModificationError:kModificationErrorDelete];
        }
    }];
}

#pragma mark - Webinar options

- (void)enableLobby
{
    [self setLobbyState:NCRoomLobbyStateModeratorsOnly withTimer:0];
}

- (void)disableLobby
{
    [self setLobbyState:NCRoomLobbyStateAllParticipants withTimer:0];
}

- (void)setLobbyState:(NCRoomLobbyState)lobbyState withTimer:(NSInteger)timer
{
    [self setModifyingRoomUI];
    [[NCAPIController sharedInstance] setLobbyState:lobbyState withTimer:timer forRoom:_room.token forAccount:[[NCDatabaseManager sharedInstance] activeAccount] withCompletionBlock:^(NSError *error) {
        if (!error) {
            [[NCRoomsManager sharedInstance] updateRoom:self->_room.token];
        } else {
            NSLog(@"Error changing lobby state in room: %@", error.description);
            [self.tableView reloadData];
            [self showRoomModificationError:kModificationErrorLobby];
        }
        self->_lobbySwtich.enabled = YES;
    }];
}

- (void)setLobbyDate
{
    NSInteger lobbyTimer = _lobbyDatePicker.date.timeIntervalSince1970;
    [self setLobbyState:NCRoomLobbyStateModeratorsOnly withTimer:lobbyTimer];
    
    NSString *lobbyTimerReadable = [NCUtils readableDateFromDate:_lobbyDatePicker.date];
    _lobbyDateTextField.text = [NSString stringWithFormat:@"%@",lobbyTimerReadable];
    [self dismissLobbyDatePicker];
}

- (void)removeLobbyDate
{
    [self setLobbyState:NCRoomLobbyStateModeratorsOnly withTimer:0];
    [self dismissLobbyDatePicker];
}

- (void)dismissLobbyDatePicker
{
    [_lobbyDateTextField resignFirstResponder];
}

- (void)setupLobbyDatePicker
{
    [_lobbyDatePicker setMinimumDate:[NSDate new]];
    // Round up default lobby timer to next hour
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSDateComponents *components = [calendar components: NSCalendarUnitEra|NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay|NSCalendarUnitHour fromDate: [NSDate new]];
    [components setHour: [components hour] + 1];
    [_lobbyDatePicker setDate:[calendar dateFromComponents:components]];
    
    UIToolbar *toolBar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
    UIBarButtonItem *cancelButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(dismissLobbyDatePicker)];
    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(setLobbyDate)];
    UIBarButtonItem *space = [[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    [toolBar setItems:[NSArray arrayWithObjects:cancelButton, space,doneButton, nil]];
    [_lobbyDateTextField setInputAccessoryView:toolBar];
    
    if (_room.lobbyTimer > 0) {
        NSDate *date = [[NSDate alloc] initWithTimeIntervalSince1970:_room.lobbyTimer];
        UIBarButtonItem *clearButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Remove", nil) style:UIBarButtonItemStylePlain target:self action:@selector(removeLobbyDate)];
        [clearButton setTintColor:[UIColor redColor]];
        [toolBar setItems:[NSArray arrayWithObjects:clearButton, space, doneButton, nil]];
        [_lobbyDatePicker setDate:date];
    }
}

#pragma mark - Participant options

- (void)addParticipantsButtonPressed
{
    AddParticipantsTableViewController *addParticipantsVC = [[AddParticipantsTableViewController alloc] initForRoom:_room];
    addParticipantsVC.delegate = self;
    NCNavigationController *navigationController = [[NCNavigationController alloc] initWithRootViewController:addParticipantsVC];
    [self presentViewController:navigationController animated:YES completion:nil];
}

- (void)addParticipantsTableViewControllerDidFinish:(AddParticipantsTableViewController *)viewController
{
    [self getRoomParticipants];
}

- (void)showModerationOptionsForParticipantAtIndexPath:(NSIndexPath *)indexPath
{
    NCRoomParticipant *participant = [_roomParticipants objectAtIndex:indexPath.row];
    
    UIAlertController *optionsActionSheet =
    [UIAlertController alertControllerWithTitle:participant.displayName
                                        message:nil
                                 preferredStyle:UIAlertControllerStyleActionSheet];
    
    if (participant.participantType == kNCParticipantTypeModerator) {
        UIAlertAction *demoteFromModerator = [UIAlertAction actionWithTitle:NSLocalizedString(@"Demote from moderator", nil)
                                                                      style:UIAlertActionStyleDefault
                                                                    handler:^void (UIAlertAction *action) {
                                                                        [self demoteFromModerator:participant];
                                                                    }];
        [demoteFromModerator setValue:[[UIImage imageNamed:@"rename-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
        [optionsActionSheet addAction:demoteFromModerator];
    } else if (participant.participantType == kNCParticipantTypeUser) {
        UIAlertAction *promoteToModerator = [UIAlertAction actionWithTitle:NSLocalizedString(@"Promote to moderator", nil)
                                                                     style:UIAlertActionStyleDefault
                                                                   handler:^void (UIAlertAction *action) {
                                                                       [self promoteToModerator:participant];
                                                                   }];
        [promoteToModerator setValue:[[UIImage imageNamed:@"rename-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
        [optionsActionSheet addAction:promoteToModerator];
    }
    
    if ([participant.actorType isEqualToString:NCAttendeeTypeEmail]) {
        UIAlertAction *resendInvitation = [UIAlertAction actionWithTitle:NSLocalizedString(@"Resend invitation", nil)
                                                                   style:UIAlertActionStyleDefault
                                                                 handler:^void (UIAlertAction *action) {
                                                                    [self resendInvitationToParticipant:[NSString stringWithFormat:@"%ld", (long)participant.attendeeId] fromIndexPath:indexPath];
                                                                }];
        [resendInvitation setValue:[[UIImage imageNamed:@"mail"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forKey:@"image"];
        [optionsActionSheet addAction:resendInvitation];
    }
    
    // Remove participant
    NSString *title = participant.isGroup ? NSLocalizedString(@"Remove group and members", nil) : NSLocalizedString(@"Remove participant", nil);
    UIAlertAction *removeParticipant = [UIAlertAction actionWithTitle:title
                                                                style:UIAlertActionStyleDestructive
                                                              handler:^void (UIAlertAction *action) {
                                                                  [self removeParticipant:participant];
                                                              }];
    [removeParticipant setValue:[[UIImage imageNamed:@"delete-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] forKey:@"image"];
    [optionsActionSheet addAction:removeParticipant];
    
    
    [optionsActionSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
    
    // Presentation on iPads
    optionsActionSheet.popoverPresentationController.sourceView = self.tableView;
    optionsActionSheet.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:indexPath];
    
    [self presentViewController:optionsActionSheet animated:YES completion:nil];
}

- (void)promoteToModerator:(NCRoomParticipant *)participant
{
    [self setModifyingRoomUI];
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    NSString *participantId = participant.participantId;
    if ([[NCAPIController sharedInstance] conversationAPIVersionForAccount:activeAccount] >= APIv3) {
        participantId = [NSString stringWithFormat:@"%ld", (long)participant.attendeeId];
    }
    [[NCAPIController sharedInstance] promoteParticipant:participantId toModeratorOfRoom:_room.token forAccount:activeAccount withCompletionBlock:^(NSError *error) {
        if (!error) {
            [self getRoomParticipants];
        } else {
            NSLog(@"Error promoting participant to moderator: %@", error.description);
            [self showRoomModificationError:kModificationErrorModeration];
        }
    }];
}

- (void)demoteFromModerator:(NCRoomParticipant *)participant
{
    [self setModifyingRoomUI];
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    NSString *participantId = participant.participantId;
    if ([[NCAPIController sharedInstance] conversationAPIVersionForAccount:activeAccount] >= APIv3) {
        participantId = [NSString stringWithFormat:@"%ld", (long)participant.attendeeId];
    }
    [[NCAPIController sharedInstance] demoteModerator:participantId toParticipantOfRoom:_room.token forAccount:activeAccount withCompletionBlock:^(NSError *error) {
        if (!error) {
            [self getRoomParticipants];
        } else {
            NSLog(@"Error demoting participant from moderator: %@", error.description);
            [self showRoomModificationError:kModificationErrorModeration];
        }
    }];
}

- (void)removeParticipant:(NCRoomParticipant *)participant
{
    TalkAccount *activeAccount = [[NCDatabaseManager sharedInstance] activeAccount];
    NSInteger conversationAPIVersion = [[NCAPIController sharedInstance] conversationAPIVersionForAccount:activeAccount];
    if (conversationAPIVersion >= APIv3) {
        [self setModifyingRoomUI];
        [[NCAPIController sharedInstance] removeAttendee:participant.attendeeId fromRoom:_room.token forAccount:activeAccount withCompletionBlock:^(NSError *error) {
            if (!error) {
                [self getRoomParticipants];
            } else {
                NSLog(@"Error removing attendee from room: %@", error.description);
                [self showRoomModificationError:kModificationErrorRemove];
            }
        }];
    } else {
        if (participant.isGuest) {
            [self setModifyingRoomUI];
            [[NCAPIController sharedInstance] removeGuest:participant.participantId fromRoom:_room.token forAccount:activeAccount withCompletionBlock:^(NSError *error) {
                if (!error) {
                    [self getRoomParticipants];
                } else {
                    NSLog(@"Error removing guest from room: %@", error.description);
                    [self showRoomModificationError:kModificationErrorRemove];
                }
            }];
        } else {
            [self setModifyingRoomUI];
            [[NCAPIController sharedInstance] removeParticipant:participant.participantId fromRoom:_room.token forAccount:activeAccount withCompletionBlock:^(NSError *error) {
                if (!error) {
                    [self getRoomParticipants];
                } else {
                    NSLog(@"Error removing participant from room: %@", error.description);
                    [self showRoomModificationError:kModificationErrorRemove];
                }
            }];
        }
    }
}


#pragma mark - Public switch

- (void)publicValueChanged:(id)sender
{
    _publicSwtich.enabled = NO;
    if (_publicSwtich.on) {
        [self makeRoomPublic];
    } else {
        [self makeRoomPrivate];
    }
}

#pragma mark - Lobby switch

- (void)lobbyValueChanged:(id)sender
{
    _lobbySwtich.enabled = NO;
    if (_lobbySwtich.on) {
        [self enableLobby];
    } else {
        [self disableLobby];
    }
}

#pragma mark - UIGestureRecognizer delegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
    // Allow click on tableview cells
    if ([touch.view isDescendantOfView:self.tableView]) {
        if (![touch.view isDescendantOfView:_roomNameTextField]) {
            [self dismissKeyboard];
        }
        return NO;
    }
    return YES;
}

#pragma mark - UITextField delegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField
{
    if (textField == _roomNameTextField) {
        [self renameRoom];
    }
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    if (textField == _roomNameTextField || textField.tag == k_set_password_textfield_tag) {
        // Prevent crashing undo bug
        // https://stackoverflow.com/questions/433337/set-the-maximum-character-length-of-a-uitextfield
        if (range.length + range.location > textField.text.length) {
            return NO;
        }
        // Set maximum character length
        NSUInteger newLength = [textField.text length] + [string length] - range.length;
        BOOL hasAllowedLength = newLength <= 200;
        // Enable/Disable password confirmation button
        if (hasAllowedLength) {
            NSString *newValue = [[textField.text stringByReplacingCharactersInRange:range withString:string] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            _setPasswordAction.enabled = (newValue.length > 0);
        }
        return hasAllowedLength;
    }
    return YES;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return [self getRoomInfoSections].count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSArray *sections = [self getRoomInfoSections];
    RoomInfoSection infoSection = [[sections objectAtIndex:section] intValue];
    switch (infoSection) {
        case kRoomInfoSectionActions:
            return [self getRoomActions].count;
            break;
            
        case kRoomInfoSectionFile:
            return [self getFileActions].count;
            break;
            
        case kRoomInfoSectionPublic:
            return [self getPublicActions].count;
            break;
            
        case kRoomInfoSectionWebinar:
            return [self getWebinarActions].count;
            break;
            
        case kRoomInfoSectionParticipants:
            return _roomParticipants.count;
            break;
            
        case kRoomInfoSectionDestructive:
            return [self getRoomDestructiveActions].count;
            break;
        default:
            break;
    }
    
    return 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSArray *sections = [self getRoomInfoSections];
    RoomInfoSection infoSection = [[sections objectAtIndex:indexPath.section] intValue];
    switch (infoSection) {
        case kRoomInfoSectionName:
            return 80;
            break;
        case kRoomInfoSectionParticipants:
            return kContactsTableCellHeight;
            break;
        default:
            break;
    }
    return 48;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSArray *sections = [self getRoomInfoSections];
    RoomInfoSection infoSection = [[sections objectAtIndex:section] intValue];
    switch (infoSection) {
        case kRoomInfoSectionFile:
            return NSLocalizedString(@"Linked file", nil);
            break;
        case kRoomInfoSectionPublic:
            return NSLocalizedString(@"Guests", nil);
            break;
        case kRoomInfoSectionWebinar:
            return NSLocalizedString(@"Webinar", nil);
            break;
        default:
            break;
    }
    
    return nil;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    NSArray *sections = [self getRoomInfoSections];
    RoomInfoSection infoSection = [[sections objectAtIndex:section] intValue];
    switch (infoSection) {
        case kRoomInfoSectionParticipants:
        {
            NSString *title = [NSString stringWithFormat:NSLocalizedString(@"%lu participants", nil), (unsigned long)_roomParticipants.count];
            if (_roomParticipants.count == 1) {
                title = NSLocalizedString(@"1 participant", nil);
            }
            _headerView.label.text = [title uppercaseString];
            _headerView.button.hidden = (_room.canModerate) ? NO : YES;
            return _headerView;
        }
            break;
        default:
            break;
    }
    
    return nil;
}

- (CGFloat) tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    switch (section) {
        case kRoomInfoSectionActions:
            return 10;
            break;
        case kRoomInfoSectionFile:
        case kRoomInfoSectionPublic:
        case kRoomInfoSectionWebinar:
            return 36;
            break;
        case kRoomInfoSectionParticipants:
            return 40;
            break;
    }
    
    return 25;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = nil;
    static NSString *favoriteRoomCellIdentifier = @"FavoriteRoomCellIdentifier";
    static NSString *notificationLevelCellIdentifier = @"NotificationLevelCellIdentifier";
    static NSString *shareLinkCellIdentifier = @"ShareLinkCellIdentifier";
    static NSString *passwordCellIdentifier = @"PasswordCellIdentifier";
    static NSString *resendInvitationsCellIdentifier = @"ResendInvitationsCellIdentifier";
    static NSString *sendLinkCellIdentifier = @"SendLinkCellIdentifier";
    static NSString *previewFileCellIdentifier = @"PreviewFileCellIdentifier";
    static NSString *openFileCellIdentifier = @"OpenFileCellIdentifier";
    static NSString *lobbyCellIdentifier = @"LobbyCellIdentifier";
    static NSString *lobbyTimerCellIdentifier = @"LobbyTimerCellIdentifier";
    static NSString *leaveRoomCellIdentifier = @"LeaveRoomCellIdentifier";
    static NSString *deleteRoomCellIdentifier = @"DeleteRoomCellIdentifier";
    
    NSArray *sections = [self getRoomInfoSections];
    RoomInfoSection section = [[sections objectAtIndex:indexPath.section] intValue];
    switch (section) {
        case kRoomInfoSectionName:
        {
            RoomNameTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kRoomNameCellIdentifier];
            if (!cell) {
                cell = [[RoomNameTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kRoomNameCellIdentifier];
            }
            
            cell.roomNameTextField.text = _room.name;
            
            switch (_room.type) {
                case kNCRoomTypeOneToOne:
                {
                    cell.roomNameTextField.text = _room.displayName;
                    [cell.roomImage setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:_room.name andSize:96 usingAccount:[[NCDatabaseManager sharedInstance] activeAccount]]
                                          placeholderImage:nil success:nil failure:nil];
                    [cell.roomImage setContentMode:UIViewContentModeScaleToFill];
                }
                    break;
                    
                case kNCRoomTypeGroup:
                    [cell.roomImage setImage:[UIImage imageNamed:@"group"]];
                    break;
                    
                case kNCRoomTypePublic:
                    [cell.roomImage setImage:[UIImage imageNamed:@"public"]];
                    break;
                    
                case kNCRoomTypeChangelog:
                {
                    cell.roomNameTextField.text = _room.displayName;
                    [cell.roomImage setImage:[UIImage imageNamed:@"changelog"]];
                    [cell.roomImage setContentMode:UIViewContentModeScaleToFill];
                }
                    break;
                    
                default:
                    break;
            }
            
            // Set objectType image
            if ([_room.objectType isEqualToString:NCRoomObjectTypeFile]) {
                [cell.roomImage setImage:[UIImage imageNamed:@"file-conv"]];
            } else if ([_room.objectType isEqualToString:NCRoomObjectTypeSharePassword]) {
                [cell.roomImage setImage:[UIImage imageNamed:@"pass-conv"]];
            }
            
            if (_room.isNameEditable) {
                _roomNameTextField = cell.roomNameTextField;
                _roomNameTextField.delegate = self;
                [_roomNameTextField setReturnKeyType:UIReturnKeyDone];
                cell.userInteractionEnabled = YES;
            } else {
                _roomNameTextField = nil;
                cell.userInteractionEnabled = NO;
            }
            
            if (_room.isFavorite) {
                [cell.favoriteImage setImage:[UIImage imageNamed:@"favorite-room"]];
            }
            
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            
            return cell;
        }
            break;
        case kRoomInfoSectionActions:
        {
            NSArray *actions = [self getRoomActions];
            RoomAction action = [[actions objectAtIndex:indexPath.row] intValue];
            switch (action) {
                case kRoomActionFavorite:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:favoriteRoomCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:favoriteRoomCellIdentifier];
                    }
                    
                    cell.textLabel.text = (_room.isFavorite) ? NSLocalizedString(@"Remove from favorites", nil) : NSLocalizedString(@"Add to favorites", nil);
                    [cell.imageView setImage:(_room.isFavorite) ? [UIImage imageNamed:@"fav-off-setting"] : [UIImage imageNamed:@"fav-setting"]];
                    
                    return cell;
                }
                    break;
                case kRoomActionNotifications:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:notificationLevelCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:notificationLevelCellIdentifier];
                    }
                    
                    cell.textLabel.text = NSLocalizedString(@"Notifications", nil);
                    cell.detailTextLabel.text = _room.notificationLevelString;
                    [cell.imageView setImage:[UIImage imageNamed:@"notifications-settings"]];
                    
                    return cell;
                }
                    break;
                case kRoomActionSendLink:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:sendLinkCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:sendLinkCellIdentifier];
                    }
                    
                    cell.textLabel.text = NSLocalizedString(@"Send conversation link", nil);
                    [cell.imageView setImage:[UIImage imageNamed:@"share-settings"]];
                    
                    return cell;
                }
                    break;
            }
        }
            break;
        case kRoomInfoSectionFile:
        {
            NSArray *actions = [self getFileActions];
            FileAction action = [[actions objectAtIndex:indexPath.row] intValue];
            switch (action) {
                case kFileActionPreview:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:previewFileCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:previewFileCellIdentifier];
                    }
                    
                    cell.textLabel.text = NSLocalizedString(@"Preview", nil);
                    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                    [cell.imageView setImage:[UIImage imageNamed:@"preview-file-settings"]];
                    
                    if (_fileDownloadIndicator) {
                        // Set download indicator in case we're already downloading a file
                        [cell setAccessoryView:_fileDownloadIndicator];
                    }
                    
                    return cell;
                }
                    break;
                case kFileActionOpenInFilesApp:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:openFileCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:openFileCellIdentifier];
                    }
                    
                    cell.textLabel.text = [NSString stringWithFormat:NSLocalizedString(@"Open in %@", nil), filesAppName];
                    
                    UIImage *nextcloudActionImage = [[UIImage imageNamed:@"logo-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                    [cell.imageView setImage:nextcloudActionImage];
                    cell.imageView.tintColor = [UIColor colorWithRed:0.43 green:0.43 blue:0.45 alpha:1];
                                        
                    return cell;
                }
                    break;
            }
        }
            break;
        case kRoomInfoSectionPublic:
        {
            NSArray *actions = [self getPublicActions];
            PublicAction action = [[actions objectAtIndex:indexPath.row] intValue];
            switch (action) {
                case kPublicActionPublicToggle:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:shareLinkCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:shareLinkCellIdentifier];
                    }
                    
                    cell.textLabel.text = NSLocalizedString(@"Share link", nil);
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    cell.accessoryView = _publicSwtich;
                    _publicSwtich.on = (_room.type == kNCRoomTypePublic) ? YES : NO;
                    [cell.imageView setImage:[UIImage imageNamed:@"public-setting"]];
                    
                    return cell;
                }
                    break;
                    
                case kPublicActionPassword:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:passwordCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:passwordCellIdentifier];
                    }
                    
                    cell.textLabel.text = (_room.hasPassword) ? NSLocalizedString(@"Change password", nil) : NSLocalizedString(@"Set password", nil);
                    [cell.imageView setImage:(_room.hasPassword) ? [UIImage imageNamed:@"password-settings"] : [UIImage imageNamed:@"no-password-settings"]];
                    
                    return cell;
                }
                    break;
                    
                case kPublicActionResendInvitations:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:resendInvitationsCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:resendInvitationsCellIdentifier];
                    }
                    
                    cell.textLabel.text = NSLocalizedString(@"Resend invitations", nil);
                    
                    UIImage *nextcloudActionImage = [[UIImage imageNamed:@"mail"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                    [cell.imageView setImage:nextcloudActionImage];
                    cell.imageView.tintColor = [UIColor colorWithRed:0.43 green:0.43 blue:0.45 alpha:1];
                    
                    return cell;
                }
                    break;
            }
        }
            break;
        case kRoomInfoSectionWebinar:
        {
            NSArray *actions = [self getWebinarActions];
            WebinarAction action = [[actions objectAtIndex:indexPath.row] intValue];
            switch (action) {
                case kWebinarActionLobby:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:lobbyCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:lobbyCellIdentifier];
                    }
                    
                    cell.textLabel.text = NSLocalizedString(@"Lobby", nil);
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    cell.accessoryView = _lobbySwtich;
                    _lobbySwtich.on = (_room.lobbyState == NCRoomLobbyStateModeratorsOnly) ? YES : NO;
                    [cell.imageView setImage:[UIImage imageNamed:@"lobby"]];
                    
                    return cell;
                }
                    break;
                case kWebinarActionLobbyTimer:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:lobbyTimerCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:lobbyTimerCellIdentifier];
                    }
                    
                    cell.textLabel.text = NSLocalizedString(@"Start time", nil);
                    cell.textLabel.adjustsFontSizeToFitWidth = YES;
                    cell.textLabel.minimumScaleFactor = 0.6;
                    cell.selectionStyle = UITableViewCellSelectionStyleNone;
                    cell.accessoryView = _lobbyDateTextField;
                    NSDate *date = [[NSDate alloc] initWithTimeIntervalSince1970:_room.lobbyTimer];
                    _lobbyDateTextField.text = _room.lobbyTimer > 0 ? [NCUtils readableDateFromDate:date] : nil;
                    [cell.imageView setImage:[UIImage imageNamed:@"timer"]];
                    
                    return cell;
                }
                    break;
            }
        }
            break;
        case kRoomInfoSectionParticipants:
        {
            NCRoomParticipant *participant = [_roomParticipants objectAtIndex:indexPath.row];
            ContactsTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kContactCellIdentifier forIndexPath:indexPath];
            if (!cell) {
                cell = [[ContactsTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kContactCellIdentifier];
            }
            
            // Display name
            cell.labelTitle.text = participant.displayName;
            
            // Avatar
            if ([participant.actorType isEqualToString:NCAttendeeTypeEmail]) {
                [cell.contactImage setImage:[UIImage imageNamed:@"mail"]];
            } else if (participant.isGroup) {
                [cell.contactImage setImage:[UIImage imageNamed:@"group"]];
            } else if (participant.isGuest) {
                UIColor *guestAvatarColor = [UIColor colorWithRed:0.84 green:0.84 blue:0.84 alpha:1.0]; /*#d5d5d5*/
                NSString *avatarName = ([participant.displayName isEqualToString:@""]) ? @"?" : participant.displayName;
                NSString *guestName = ([participant.displayName isEqualToString:@""]) ? NSLocalizedString(@"Guest", nil) : participant.displayName;
                cell.labelTitle.text = guestName;
                [cell.contactImage setImageWithString:avatarName color:guestAvatarColor circular:true];
            } else {
                [cell.contactImage setImageWithURLRequest:[[NCAPIController sharedInstance] createAvatarRequestForUser:participant.participantId andSize:96 usingAccount:[[NCDatabaseManager sharedInstance] activeAccount]]
                                         placeholderImage:nil success:nil failure:nil];
                [cell.contactImage setContentMode:UIViewContentModeScaleToFill];
            }
            
            // Online status
            if (participant.isOffline) {
                cell.contactImage.alpha = 0.5;
                cell.labelTitle.alpha = 0.5;
            } else {
                cell.contactImage.alpha = 1;
                cell.labelTitle.alpha = 1;
            }
            
            // Call status
            if (participant.callIconImageName) {
                cell.accessoryView = [[UIImageView alloc] initWithImage:[[UIImage imageNamed:participant.callIconImageName] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
                [cell.accessoryView setTintColor:[NCAppBranding placeholderColor]];
            } else {
                cell.accessoryView = nil;
            }
            
            cell.layoutMargins = UIEdgeInsetsMake(0, 72, 0, 0);
            
            [cell setUserStatus:participant.status];
            
            return cell;
        }
            break;
        case kRoomInfoSectionDestructive:
        {
            NSArray *actions = [self getRoomDestructiveActions];
            DestructiveAction action = [[actions objectAtIndex:indexPath.row] intValue];
            switch (action) {
                case kDestructiveActionLeave:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:leaveRoomCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:leaveRoomCellIdentifier];
                    }
                    
                    cell.textLabel.text = NSLocalizedString(@"Leave conversation", nil);
                    cell.textLabel.textColor = [UIColor systemRedColor];
                    [cell.imageView setImage:[[UIImage imageNamed:@"exit-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
                    [cell.imageView setTintColor:[UIColor systemRedColor]];
                    
                    return cell;
                }
                    break;
                case kDestructiveActionDelete:
                {
                    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:deleteRoomCellIdentifier];
                    if (!cell) {
                        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:deleteRoomCellIdentifier];
                    }
                    
                    cell.textLabel.text = NSLocalizedString(@"Delete conversation", nil);
                    cell.textLabel.textColor = [UIColor systemRedColor];
                    [cell.imageView setImage:[[UIImage imageNamed:@"delete-action"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
                    [cell.imageView setTintColor:[UIColor systemRedColor]];
                    
                    return cell;
                }
                    break;
            }
        }
            break;
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *sections = [self getRoomInfoSections];
    RoomInfoSection section = [[sections objectAtIndex:indexPath.section] intValue];
    switch (section) {
        case kRoomInfoSectionName:
            break;
        case kRoomInfoSectionActions:
        {
            NSArray *actions = [self getRoomActions];
            RoomAction action = [[actions objectAtIndex:indexPath.row] intValue];
            switch (action) {
                case kRoomActionFavorite:
                    if (_room.isFavorite) {
                        [self removeRoomFromFavorites];
                    } else {
                        [self addRoomToFavorites];
                    }
                    break;
                case kRoomActionNotifications:
                    [self presentNotificationLevelSelector];
                    break;
                case kRoomActionSendLink:
                    [self shareRoomLinkFromIndexPath:indexPath];
                    break;
            }
        }
            break;
        case kRoomInfoSectionFile:
        {
            NSArray *actions = [self getFileActions];
            FileAction action = [[actions objectAtIndex:indexPath.row] intValue];
            switch (action) {
                case kFileActionPreview:
                    [self previewRoomFile:indexPath];
                    break;
                case kFileActionOpenInFilesApp:
                    [self openRoomFileInFilesApp:indexPath];
                    break;
            }
        }
            break;
        case kRoomInfoSectionPublic:
        {
            NSArray *actions = [self getPublicActions];
            PublicAction action = [[actions objectAtIndex:indexPath.row] intValue];
            switch (action) {
                case kPublicActionPassword:
                    [self showPasswordOptions];
                    break;
                case kPublicActionResendInvitations:
                    [self resendInvitations];
                    break;
                default:
                    break;
            }
        }
            break;
        case kRoomInfoSectionWebinar:
            break;
        case kRoomInfoSectionParticipants:
        {
            NCRoomParticipant *participant = [_roomParticipants objectAtIndex:indexPath.row];
            if (participant.participantType != kNCParticipantTypeOwner && ![self isAppUser:participant] && _room.canModerate) {
                [self showModerationOptionsForParticipantAtIndexPath:indexPath];
            }
        }
            break;
        case kRoomInfoSectionDestructive:
        {
            NSArray *actions = [self getRoomDestructiveActions];
            DestructiveAction action = [[actions objectAtIndex:indexPath.row] intValue];
            [self showConfirmationDialogForDestructiveAction:action];
        }
            break;
    }
    [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark - NCChatFileControllerDelegate

- (void)fileControllerDidLoadFile:(NCChatFileController *)fileController withFileStatus:(NCChatFileStatus *)fileStatus
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_fileDownloadIndicator) {
            [self->_fileDownloadIndicator stopAnimating];
            [self->_fileDownloadIndicator removeFromSuperview];
            self->_fileDownloadIndicator = nil;
        }
            
        NSInteger fileSection = [[self getRoomInfoSections] indexOfObject:@(kRoomInfoSectionFile)];
        NSInteger previewRow = [[self getFileActions] indexOfObject:@(kFileActionPreview)];
        NSIndexPath *previewActionIndexPath = [NSIndexPath indexPathForRow:previewRow inSection:fileSection];
        
        UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:previewActionIndexPath];
        
        if (cell) {
            // Only show preview controller if cell is still visible
            self->_previewControllerFilePath = fileStatus.fileLocalPath;

            QLPreviewController * preview = [[QLPreviewController alloc] init];
            UIColor *themeColor = [NCAppBranding themeColor];
            
            preview.dataSource = self;
            preview.delegate = self;

            preview.navigationController.navigationBar.tintColor = [NCAppBranding themeTextColor];
            preview.navigationController.navigationBar.barTintColor = themeColor;
            preview.tabBarController.tabBar.tintColor = themeColor;

            if (@available(iOS 13.0, *)) {
                UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
                [appearance configureWithOpaqueBackground];
                appearance.backgroundColor = themeColor;
                appearance.titleTextAttributes = @{NSForegroundColorAttributeName:[NCAppBranding themeTextColor]};
                preview.navigationItem.standardAppearance = appearance;
                preview.navigationItem.compactAppearance = appearance;
                preview.navigationItem.scrollEdgeAppearance = appearance;
            }

            [self.navigationController pushViewController:preview animated:YES];
            
            // Make sure disclosure indicator is visible again (otherwise accessoryView is empty)
            cell.accessoryView = nil;
        }
    });
}

- (void)fileControllerDidFailLoadingFile:(NCChatFileController *)fileController withErrorDescription:(NSString *)errorDescription
{
    UIAlertController * alert = [UIAlertController
                                 alertControllerWithTitle:NSLocalizedString(@"Unable to load file", nil)
                                 message:errorDescription
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* okButton = [UIAlertAction
                               actionWithTitle:NSLocalizedString(@"OK", nil)
                               style:UIAlertActionStyleDefault
                               handler:nil];
    
    [alert addAction:okButton];
    
    [[NCUserInterfaceController sharedInstance] presentAlertViewController:alert];
}

#pragma mark - QLPreviewControllerDelegate/DataSource

- (NSInteger)numberOfPreviewItemsInPreviewController:(nonnull QLPreviewController *)controller {
    return 1;
}

- (nonnull id<QLPreviewItem>)previewController:(nonnull QLPreviewController *)controller previewItemAtIndex:(NSInteger)index {
    return [NSURL fileURLWithPath:_previewControllerFilePath];
}


@end
