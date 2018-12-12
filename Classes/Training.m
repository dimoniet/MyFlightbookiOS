/*
	MyFlightbook for iOS - provides native access to MyFlightbook
	pilot's logbook
 Copyright (C) 2014-2018 MyFlightbook, LLC
 
 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 
 You should have received a copy of the GNU General Public License
 along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

//
//  Training.m
//  MFBSample
//
//  Created by Eric Berman on 5/30/14.
//
//

#import "Training.h"
#import "HostedWebViewViewController.h"
#import "MFBTheme.h"

@interface Training ()

@end

enum _trainingLinks {cidFirst, cidInstructors = cidFirst, cidStudents, cidReqSignatures, cidEndorsements, cid8710, cidAchievements, cidMilestoneProgress, cidLast = cidMilestoneProgress};

@implementation Training

- (void)viewDidLoad
{
    [super viewDidLoad];
}

- (void) viewWillAppear:(BOOL)animated
{
    [self.navigationController setToolbarHidden:YES];
    [self.tableView reloadData];
    [super viewWillAppear:animated];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (BOOL) canViewTraining
{
    return mfbApp().isOnLine && mfbApp().userProfile.isValid;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return cidLast - cidFirst + 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString * cellID = @"TrainingCell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (cell == nil)
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellID];

    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    NSInteger cid = indexPath.row;
    switch (cid)
    {
        case cidEndorsements:
            cell.textLabel.text = NSLocalizedString(@"Endorsements", @"Prompt to view/edit endorsements");
            break;
        case cidAchievements:
            cell.textLabel.text = NSLocalizedString(@"Achievements", @"Prompt to view achievements");
            break;
        case cidMilestoneProgress:
            cell.textLabel.text = NSLocalizedString(@"Ratings Progress", @"Prompt to view Ratings Progress");
            break;
        case cidStudents:
            cell.textLabel.text = NSLocalizedString(@"Students", @"Prompt for students");
            break;
        case cidInstructors:
            cell.textLabel.text = NSLocalizedString(@"Instructors", @"Prompt for Instructors");
            break;
        case cidReqSignatures:
            cell.textLabel.text = NSLocalizedString(@"ReqSignatures", @"Prompt for Requesting Signatures");
            break;
        case cid8710:
            cell.textLabel.text = NSLocalizedString(@"8710Form", @"Prompt for 8710 form");
            break;
    }
    
    if (!self.canViewTraining)
        cell.textLabel.textColor = MFBTheme.currentTheme.dimmedColor;
    [MFBTheme.currentTheme applyThemedImageNamed:@"training.png" toImageView:cell.imageView];
    return cell;
}

#pragma mark - Table view delegate

- (void) pushAuthURL:(NSString *) szDest
{
    if (![self canViewTraining])
    {
        [self showErrorAlertWithMessage:NSLocalizedString(@"TrainingNotAvailable", @"Error message for training if offline or not signed in")];
        return;
    }
    NSString * szProtocol = @"https";
#ifdef DEBUG
    if ([MFBHOSTNAME hasPrefix:@"192."] || [MFBHOSTNAME hasPrefix:@"10."])
        szProtocol = @"http";
#endif
    NSString * szURL = [NSString stringWithFormat:@"%@://%@/logbook/public/authredir.aspx?u=%@&p=%@&d=%@&naked=1",
                   szProtocol, MFBHOSTNAME, [mfbApp().userProfile.UserName stringByURLEncodingString], [mfbApp().userProfile.Password stringByURLEncodingString], szDest];

	HostedWebViewViewController * vwWeb = [[HostedWebViewViewController alloc] initWithURL:szURL];
	[self.navigationController pushViewController:vwWeb animated:YES];
}

// In a xib-based application, navigation from a table can be handled in -tableView:didSelectRowAtIndexPath:
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSInteger cid = indexPath.row;
    switch (cid)
    {
        case cidEndorsements:
            [self pushAuthURL:@"endorse"];
            break;
        case cidAchievements:
            [self pushAuthURL:@"badges"];
            break;
        case cidMilestoneProgress:
            [self pushAuthURL:@"progress"];
            break;
        case cidInstructors:
            [self pushAuthURL:@"instructorsFixed"];
            break;
        case cidReqSignatures:
            [self pushAuthURL:@"reqSigs"];
            break;
        case cidStudents:
            [self pushAuthURL:@"studentsFixed"];
            break;
        case cid8710:
            [self pushAuthURL:@"8710"];
            break;
    }
}

@end
