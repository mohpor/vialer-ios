//
//  DialerViewController.m
//  Copyright © 2015 VoIPGRID. All rights reserved.
//

#import "DialerViewController.h"

#import "AppDelegate.h"
#import "Configuration.h"
#import "NumberPadViewController.h"
#import "PasteableUILabel.h"
#import "ReachabilityManager.h"
#import "ReachabilityBarViewController.h"
#import "SystemUser.h"
#import "TwoStepCallingViewController.h"
#import "UIViewController+MMDrawerController.h"
#import "Vialer-Swift.h"

#import <AVFoundation/AVAudioSession.h>

static NSString * const DialerViewControllerTabBarItemImage = @"tab-keypad";
static NSString * const DialerViewControllerTabBarItemActiveImage = @"tab-keypad-active";
static NSString * const DialerViewControllerLogoImage = @"logo";
static NSString * const DialerViewControllerLeftDrawerButtonImage = @"menu";
static NSString * const DialerViewControllerTwoStepCallingSegue = @"TwoStepCallingSegue";
static NSString * const DialerViewControllerSIPCallingSegue = @"SIPCallingSegue";

@interface DialerViewController () <PasteableUILabelDelegate, NumberPadViewControllerDelegate, ReachabilityBarViewControllerDelegate>

@property (strong, nonatomic) UIBarButtonItem *leftDrawerButton;
@property (weak, nonatomic) IBOutlet PasteableUILabel *numberLabel;
@property (weak, nonatomic) IBOutlet UIButton *deleteButton;
@property (weak, nonatomic) IBOutlet UIButton *callButton;

@property (nonatomic) ReachabilityManagerStatusType reachabilityStatus;
@property (strong, nonatomic) NSString *numberText;
@property (strong, nonatomic) NSString *lastCalledNumber;

@end

@implementation DialerViewController

#pragma mark - view lifecycle

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
    if (self) {
        self.title = NSLocalizedString(@"Keypad", nil);
        self.tabBarItem.image = [UIImage imageNamed:DialerViewControllerTabBarItemImage];
        self.tabBarItem.selectedImage = [UIImage imageNamed:DialerViewControllerTabBarItemActiveImage];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setupLayout];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [VialerGAITracker trackScreenForControllerWithName:NSStringFromClass([self class])];
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryAmbient error:nil];
    [self setupCallButton];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
}

#pragma mark - setup

- (void)setupLayout {
    self.numberText = @"";
    self.navigationItem.titleView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:DialerViewControllerLogoImage]];
}

- (void)setupCallButton {
    if (self.reachabilityStatus == ReachabilityManagerStatusOffline ||
        (!self.lastCalledNumber.length && !self.numberText.length)) {

        self.callButton.enabled = NO;
    } else {
        self.callButton.enabled = YES;
    }
}

#pragma mark - properties

- (void)setNumberLabel:(PasteableUILabel *)numberLabel {
    _numberLabel = numberLabel;
    _numberLabel.delegate = self;
}

- (void)setNumberText:(NSString *)numberText {
    self.numberLabel.text = [self cleanPhonenumber:numberText];
    self.deleteButton.hidden = self.numberText.length == 0;
    [self setupCallButton];
}

- (NSString *)cleanPhonenumber:(NSString *)phonenumber {
    phonenumber = [[phonenumber componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] componentsJoinedByString:@""];
    return [[phonenumber componentsSeparatedByCharactersInSet:[[NSCharacterSet characterSetWithCharactersInString:@"+0123456789*#"] invertedSet]] componentsJoinedByString:@""];
}

- (NSString *)numberText {
    return self.numberLabel.text;
}

- (void)setLastCalledNumber:(NSString *)lastCalledNumber {
    _lastCalledNumber = lastCalledNumber;
    [self setupCallButton];
}

#pragma mark - actions

- (IBAction)leftDrawerButtonPress:(UIBarButtonItem *)sender{
    [self.mm_drawerController toggleDrawerSide:MMDrawerSideLeft animated:YES completion:nil];
}

- (IBAction)backButtonPressed:(UIButton *)sender {
    self.numberText = [self.numberText substringToIndex:self.numberText.length - 1];
}


- (IBAction)backButtonLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateBegan) {
        self.numberText = @"";
    }
}

- (IBAction)callButtonPressed:(UIButton *)sender {
    // No number filled in yet, use old number (if stored)
    if (![self.numberText length]) {
        self.numberText = self.lastCalledNumber;

    // There is a number, let's call
    } else {
        self.lastCalledNumber = self.numberText;

        if (self.reachabilityStatus == ReachabilityManagerStatusHighSpeed && [SystemUser currentUser].sipEnabled) {
            [VialerGAITracker setupOutgoingSIPCallEvent];
            [self performSegueWithIdentifier:DialerViewControllerSIPCallingSegue sender:self];
        } else {
            [VialerGAITracker setupOutgoingConnectABCallEvent];
            [self performSegueWithIdentifier:DialerViewControllerTwoStepCallingSegue sender:self];
        }
    }
}

#pragma mark - segues

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.destinationViewController isKindOfClass:[NumberPadViewController class]]) {
        NumberPadViewController *npvc = (NumberPadViewController *)segue.destinationViewController;
        npvc.delegate = self;
    } else if ([segue.destinationViewController isKindOfClass:[ReachabilityBarViewController class]]) {
        ReachabilityBarViewController *rbvc = (ReachabilityBarViewController *)segue.destinationViewController;
        rbvc.delegate = self;
    } else if ([segue.destinationViewController isKindOfClass:[TwoStepCallingViewController class]]) {
        TwoStepCallingViewController *tscvc = (TwoStepCallingViewController *)segue.destinationViewController;
        [tscvc handlePhoneNumber:self.numberText];
        self.numberText = @"";
    } else if ([segue.destinationViewController isKindOfClass:[SIPCallingViewController class]]) {
        SIPCallingViewController *sipCallingVC = (SIPCallingViewController *)segue.destinationViewController;
        [sipCallingVC handleOutgoingCallWithPhoneNumber:self.numberText contact:nil];
        self.numberText = @"";
    }
}

#pragma mark - NumberPadViewControllerDelegate

- (void)numberPadPressedWithCharacter:(NSString *)character {
    if ([character isEqualToString:@"+"]) {
        if ([self.numberText isEqualToString:@"0"] || !self.numberText.length) {
            self.numberText = @"+";
        }
    } else {
        self.numberText = [self.numberText stringByAppendingString:character];
    }
}

#pragma mark - PasteableUILabelDelegate

- (void) pasteableUILabel:(UILabel *)label didReceivePastedText:(NSString *)text {
    self.numberText = text;
}

#pragma mark - ReachabilityBarViewControllerDelegate

- (void)reachabilityBar:(ReachabilityBarViewController *)reachabilityBar statusChanged:(ReachabilityManagerStatusType)status {
    self.reachabilityStatus = status;
}

@end
