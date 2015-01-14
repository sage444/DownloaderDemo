//
//  ViewController.m
//  BGLoader
//
//  Created by Sergiy Suprun on 1/14/15.
//  Copyright (c) 2015 Sergiy Suprun. All rights reserved.
//

#import "ViewController.h"

#import "BackgroundDownloadManager.h"

@interface ViewController ()

@end

@implementation ViewController
{
    NSArray * _linksArray;
    __weak IBOutlet UIBarButtonItem *refreshButton;
    UIScrollView * _mainView;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _linksArray = @[
                    @"https://farm8.staticflickr.com/7471/16243974676_b0011b0568_o.jpg",
                    @"https://farm8.staticflickr.com/7506/16245804016_ac760664c7_k.jpg",
                    @"https://farm8.staticflickr.com/7557/15652273134_fabf71f5e5_k.jpg",
                    @"https://farm9.staticflickr.com/8564/16271884135_a46cd0c09b_o.jpg",
                    @"https://farm8.staticflickr.com/7502/16086776289_ddd8ad0027_k.jpg",
                    @"https://farm8.staticflickr.com/7472/16081051288_f3cdf3ae78_b.jpg",
                    @"https://farm9.staticflickr.com/8640/16087156607_e2799d296b_o.jpg",
                    @"https://farm8.staticflickr.com/7503/16085555287_33edadd012_h.jpg"
                    ];
    _mainView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    _mainView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_mainView];

    
    [self initiateDownload:_linksArray];
}


-(void)initiateDownload:(NSArray *)links {
    refreshButton.enabled = NO;
    __block NSInteger counter = links.count;
    
    
    CGFloat width = _mainView.frame.size.width;
    CGRect wholeFrame = CGRectZero;
    for (int index =0 ; index < links.count; index++) {
        
        UIImageView * imv = [[UIImageView alloc] initWithFrame:CGRectMake(0, index * width, width, width)];
        imv.contentMode = UIViewContentModeScaleAspectFill;
        imv.clipsToBounds = YES;
        imv.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        wholeFrame = CGRectUnion(wholeFrame, imv.frame);

        UIProgressView * pv = [[UIProgressView alloc]initWithFrame:imv.bounds];
        [imv addSubview:pv];
        pv.center = CGPointMake(imv.bounds.size.width/2, imv.bounds.size.width/2);
        pv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

        [_mainView addSubview:imv];
        pv.tintColor = [UIColor redColor];
        
        [[BackgroundDownloadManager sharedManager] downloadDataFromURL:links[index] success:^(NSData *responseData) {
            if (responseData) {
                imv.image = [UIImage imageWithData:responseData scale:[UIScreen mainScreen].scale];
                [pv removeFromSuperview];
            }
            counter--;
            refreshButton.enabled = counter <=0;
            
        } failure:^(NSError *error) {

            NSLog(@"error: %@", error.localizedDescription);
            counter--;
            refreshButton.enabled = counter <=0;
            
        } andProgress:^(NSUInteger bytesRead, long long totalBytesRead, long long totalBytesExpectedToRead) {
            pv.progress = (double)totalBytesRead/(double)totalBytesExpectedToRead;
        }];
    }
    _mainView.contentSize = wholeFrame.size;
    
}

- (IBAction)refresh:(id)sender {
    [[BackgroundDownloadManager sharedManager] clearCache];
    for (UIView * v in _mainView.subviews) {
        [v removeFromSuperview];
    }
    [self initiateDownload:_linksArray];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
