//
//  InfoCarouselViewController.m
//  Vialer
//
//  Created by Reinier Wieringa on 09/09/14.
//  Copyright (c) 2014 VoIPGRID. All rights reserved.
//

#import "InfoCarouselViewController.h"

@interface InfoCarouselViewController ()
@property (nonatomic, assign) BOOL pageControlUsed;
@end

@implementation InfoCarouselViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        self.title = NSLocalizedString(@"Information", nil);
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"Config" ofType:@"plist"]];
    NSAssert(config != nil, @"Config.plist not found!");
    
    NSArray *tintColor = [[config objectForKey:@"Tint colors"] objectForKey:@"NavigationBar"];
    NSAssert(tintColor != nil && tintColor.count == 3, @"Tint colors - NavigationBar not found in Config.plist!");
    
    NSArray *currentTintColor = [[config objectForKey:@"Tint colors"] objectForKey:@"TabBar"];
    NSAssert(currentTintColor != nil && currentTintColor.count == 3, @"Tint colors - TabBar not found in Config.plist!");

    self.pageControl.pageIndicatorTintColor = [UIColor colorWithRed:[currentTintColor[0] intValue] / 255.f green:[currentTintColor[1] intValue] / 255.f blue:[currentTintColor[2] intValue] / 255.f alpha:1.f];
    self.pageControl.currentPageIndicatorTintColor = [UIColor colorWithRed:[tintColor[0] intValue] / 255.f green:[tintColor[1] intValue] / 255.f blue:[tintColor[2] intValue] / 255.f alpha:1.f];
    self.pageControl.numberOfPages = 4;

    self.pageControl.frame = CGRectMake(0.f, (self.view.frame.size.height + (([[[UIDevice currentDevice] systemVersion] floatValue] >= 7.0f) ? 0.f : 44.f)) - (self.tabBarController.tabBar.frame.size.height + self.pageControl.frame.size.height * 2.f), self.pageControl.frame.size.width, self.pageControl.frame.size.height);
    self.scrollView.contentSize = CGSizeMake(self.scrollView.frame.size.width * self.pageControl.numberOfPages, 1.f);

    for (int i = 1; i <= self.pageControl.numberOfPages; i++) {
        UIImageView *imageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:[NSString stringWithFormat:@"info-%02d.jpg", i]]];
        imageView.contentMode = UIViewContentModeScaleAspectFill;
        imageView.frame = CGRectMake(self.scrollView.frame.size.width * (i - 1), 0.f, self.view.frame.size.width, self.view.frame.size.height / 3.f);
        [self.scrollView addSubview:imageView];
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Scroll view delegate

- (void)scrollViewDidScroll:(UIScrollView *)sender {
    if (self.pageControlUsed) {
        return;
    }
    
	CGFloat pageWidth = self.scrollView.bounds.size.width ;
    float fractionalPage = self.scrollView.contentOffset.x / pageWidth ;
	NSInteger nearestNumber = lround(fractionalPage) ;
	
	if (self.pageControl.currentPage != nearestNumber) {
		self.pageControl.currentPage = nearestNumber;
		if (self.scrollView.dragging) {
			[self.pageControl updateCurrentPageDisplay];
        }
	}
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    self.pageControlUsed = NO;
}

- (IBAction)pageChanged:(id)sender {
	[self.scrollView setContentOffset:CGPointMake(self.scrollView.bounds.size.width * self.pageControl.currentPage, self.scrollView.contentOffset.y) animated:YES];
    self.pageControlUsed = YES;
}

@end