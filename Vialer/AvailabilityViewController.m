//
//  AvailabilityViewController.m
//  Copyright (c) 2015 VoIPGRID. All rights reserved.
//

#import "AvailabilityViewController.h"

#import "AvailabilityModel.h"
#import "Configuration.h"
#import "SVProgressHUD.h"
#import "UIAlertController+Vialer.h"
#import "Vialer-Swift.h"
#import "VialerWebViewController.h"
#import "VoIPGRIDRequestOperationManager.h"

@interface AvailabilityViewController()
@property (nonatomic, weak) NSIndexPath *lastSelected;
@property (nonatomic, strong) AvailabilityModel *availabilityModel;
@end

static NSString * const AvailabilityAddFixedDestinationSegue = @"AddFixedDestinationSegue";
static NSString * const AvailabilityViewControllerAddFixedDestinationPageURLWithVariableForClient = @"/client/%@/fixeddestination/add/";

@implementation AvailabilityViewController

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [VialerGAITracker trackScreenForControllerWithName:NSStringFromClass([self class])];
    [self loadUserDestinations];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.tintColor = [[Configuration defaultConfiguration].colorConfiguration colorForKey:ConfigurationAvailabilityTableViewTintColor];
}

- (UIRefreshControl *)refreshControl {
    UIRefreshControl *refreshControl = [super refreshControl];
    if (!refreshControl) {
        self.refreshControl = [[UIRefreshControl alloc] init];
        self.refreshControl.attributedTitle = [[NSAttributedString alloc] initWithString: NSLocalizedString(@"Loading availability options...", nil)];
        [self.refreshControl addTarget:self action:@selector(loadUserDestinations) forControlEvents:UIControlEventValueChanged];
    }
    return [super refreshControl];
}

- (AvailabilityModel *)availabilityModel {
    if (_availabilityModel == nil) {
        _availabilityModel = [[AvailabilityModel alloc] init];
    }
    return _availabilityModel;
}

- (void)loadUserDestinations {
    [self.refreshControl beginRefreshing];
    // A bug in RefreshControl on a tableview within a navigation controller
    // http://stackoverflow.com/a/14719658
    [self.tableView setContentOffset:CGPointMake(0, -self.refreshControl.frame.size.height) animated:YES];

    [self.availabilityModel getUserDestinations:^(NSString *localizedErrorString) {
        [self.tableView setContentOffset:CGPointMake(0,0) animated:YES];
        [self.refreshControl endRefreshing];
        if (localizedErrorString) {
            [self presentViewController:[UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error", nil)
                                                                            message:localizedErrorString
                                                               andDefaultButtonText:NSLocalizedString(@"Ok", nil)]
                               animated:YES
                             completion:nil];
        }else{
            [self.tableView reloadData];
        }
    }];
}

#pragma mark - Table view data source

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.availabilityModel.availabilityOptions count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *DefaultCellIdentifier = @"AvailabilityTableViewDefaultCell";
    static NSString *SubtitleCellIdentifier = @"AvailabilityTableViewSubtitleCell";
    NSDictionary *availabilityDict = self.availabilityModel.availabilityOptions[indexPath.row];

    UITableViewCell *cell;
    if ([[availabilityDict objectForKey:AvailabilityModelPhoneNumber] isEqualToNumber:@0]){
        cell = [self.tableView dequeueReusableCellWithIdentifier:DefaultCellIdentifier];
        cell.textLabel.text = [availabilityDict objectForKey:AvailabilityModelDescription];
    } else {
        cell = [self.tableView dequeueReusableCellWithIdentifier:SubtitleCellIdentifier];
        cell.textLabel.text = [availabilityDict objectForKey:AvailabilityModelDescription];
        cell.detailTextLabel.text = [[availabilityDict objectForKey:AvailabilityModelPhoneNumber] stringValue];
    }
    cell.accessoryType = UITableViewCellAccessoryNone;

    if ([[availabilityDict objectForKey:AvailabilityModelSelected] isEqualToNumber:[NSNumber numberWithBool:YES]]) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
        self.lastSelected = indexPath;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(nonnull NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [tableView cellForRowAtIndexPath:self.lastSelected].accessoryType = UITableViewCellAccessoryNone;
    [tableView cellForRowAtIndexPath:indexPath].accessoryType = UITableViewCellAccessoryCheckmark;

    if (indexPath.row >= [self.availabilityModel.availabilityOptions count]) {
        return;
    }
    self.lastSelected = indexPath;

    [SVProgressHUD showWithStatus:NSLocalizedString(@"Saving availability...", nil)];
    [self.availabilityModel saveUserDestination:self.lastSelected.row withCompletion:^(NSString *localizedErrorString) {
        [SVProgressHUD dismiss];
        if (localizedErrorString) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error", nil)
                                                                           message:localizedErrorString
                                                              andDefaultButtonText:NSLocalizedString(@"Ok", nil)];
            [self presentViewController:alert
                               animated:YES
                             completion:nil];
        } else {
            [self.delegate availabilityViewController:self availabilityHasChanged:self.availabilityModel.availabilityOptions];
            [self.parentViewController dismissViewControllerAnimated:YES completion:nil];
        }
    }];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:AvailabilityAddFixedDestinationSegue]) {
        if ([segue.destinationViewController isKindOfClass:[VialerWebViewController class]]) {
            VialerWebViewController *webController = segue.destinationViewController;

            [VialerGAITracker trackScreenForControllerWithName:[VialerGAITracker GAAddFixedDestinationWebViewTrackingName]];
            webController.title = NSLocalizedString(@"Add destination", nil);
            NSString *nextURL = [NSString stringWithFormat:AvailabilityViewControllerAddFixedDestinationPageURLWithVariableForClient,
                                 [SystemUser currentUser].clientID];
            [webController nextUrl:nextURL];

        } else {
            DDLogWarn(@"Could not segue, destinationViewController is not a \"VialerWebViewController\"");
        }
    }
}

- (IBAction)cancelButtonPressed:(UIBarButtonItem *)sender {
    [self.parentViewController dismissViewControllerAnimated:YES completion:nil];
}
@end
