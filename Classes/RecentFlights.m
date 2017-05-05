/*
	MyFlightbook for iOS - provides native access to MyFlightbook
	pilot's logbook
 Copyright (C) 2017 MyFlightbook, LLC
 
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
//  RecentFlights.m
//  MFBSample
//
//  Created by Eric Berman on 1/14/10.
//  Copyright 2010-2017 MyFlightbook LLC. All rights reserved.
//

#import "RecentFlights.h"
#import "MFBAppDelegate.h"
#import "MFBSoapCall.h"
#import "RecentFlightCell.h"
#import "DecimalEdit.h"
#import "iRate.h"

@interface RecentFlights()
@property (atomic, strong) NSMutableDictionary * dictImages;
@property (atomic, assign) BOOL uploadInProgress;
@property (atomic, strong) NSIndexPath * ipSelectedCell;
@property (atomic, strong) id JSONObjToImport;
@property (nonatomic, strong) NSURL * urlTelemetry;
@end

@implementation RecentFlights

static const int cFlightsPageSize=15;   // number of flights to download at a time by default.

enum _tagRecentFlightsAlerts {alertConfirmDelete, alertConfirmImport, alertConfirmImportTelemetry};

int iFlightInProgress, cFlightsToSubmit;
BOOL fCouldBeMoreFlights;

@synthesize rgFlights, errorString, fq, cellProgress, uploadInProgress, dictImages, ipSelectedCell, JSONObjToImport, urlTelemetry;

- (void) asyncLoadThumbnailsForFlights:(NSArray *) flights
{
    if (flights == nil)
        return;
    
    if (![AutodetectOptions showFlightImages])
        return;
    
    @autoreleasepool {
    for (MFBWebServiceSvc_LogbookEntry * le in flights)
    {
        CommentedImage * ci = [CommentedImage new];
        if ([le.FlightImages.MFBImageInfo count] > 0)
            ci.imgInfo = (MFBWebServiceSvc_MFBImageInfo *) (le.FlightImages.MFBImageInfo)[0];
        else // try to get an aircraft image.
        {
            MFBWebServiceSvc_Aircraft * ac = [[Aircraft sharedAircraft] AircraftByID:[le.AircraftID intValue]];
            if ([ac.AircraftImages.MFBImageInfo count] > 0)
                ci.imgInfo = (MFBWebServiceSvc_MFBImageInfo *) (ac.AircraftImages.MFBImageInfo)[0];
            else
                ci.imgInfo = nil;
        }
        
        [ci GetThumbnail];
        
        if (le != nil && le.FlightID != nil)    // crash if you store into a dictionary using nil key
            (self.dictImages)[le.FlightID] = ci;
        
        if (ci.imgInfo != nil)
            [self.tableView performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:NO];
    }
    }
}

#pragma mark View lifecycle, management
- (void)viewDidLoad {
    [super viewDidLoad];
    
    fCouldBeMoreFlights = YES;
    
    self.cellProgress = [ProgressCell getProgressCell:self.tableView];
	
	self.rgFlights = [[NSMutableArray alloc] init];
	self.errorString = @"";
    if (self.fq == nil)
        self.fq = [MFBWebServiceSvc_FlightQuery getNewFlightQuery];
    
    // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
    self.navigationItem.rightBarButtonItem = self.editButtonItem;
    	
    // get notifications when the network is acquired.
    MFBAppDelegate * app = mfbApp();
    app.reachabilityDelegate = self;
    
    // get notifications when data is changed OR when user signs out
    [app registerNotifyDataChanged:self];
    [app registerNotifyResetAll:self];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
        self.tableView.rowHeight = 80;
    [self.navigationController setToolbarHidden:YES];
}

- (void)viewWillAppear:(BOOL)animated {
	// put the refresh button up IF we are the top controller
    // else, don't do anything with it because we need a way to navigate back
    if ((self.navigationController.viewControllers)[0] == self)
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(refresh)];
    else
        self.navigationItem.leftBarButtonItem = nil;
    self.navigationController.toolbarHidden = YES;

    if (self.dictImages == nil)
    {
        self.dictImages = [NSMutableDictionary new];
        [NSThread detachNewThreadSelector:@selector(asyncLoadThumbnailsForFlights:) toTarget:self withObject:self.rgFlights];
    }
    
    [super viewWillAppear:animated];
}


- (void) flightUpdated:(LEEditController *) sender
{
	[self.navigationController popViewControllerAnimated:YES];
}

- (void) refresh:(BOOL) fSubmitPending
{
    [self.dictImages removeAllObjects];
    self.dictImages = [NSMutableDictionary new];
    self.rgFlights = [[NSMutableArray alloc] init];
    fCouldBeMoreFlights = YES;
	MFBAppDelegate * app = mfbApp();
	[app invalidateCachedTotals];
    
    // if we are forcing a resubmit, clear any errors and resubmit; this will cause 
    // loadFlightsForUser to be called (refreshing the existing flights.)
    // Otherwise, just do the refresh directly.
    if (fSubmitPending && [app.rgPendingFlights count] > 0)
    {
        // clear the errors from pending flights so that they can potentially go again.
        for (LogbookEntry * le in app.rgPendingFlights)
            le.errorString = @"";
        [self submitPendingFlights];
    }
    else
        [self loadFlightsForUser];
}

- (void) refresh
{
    [self refresh:YES];
}

- (void) invalidateViewController
{
    self.rgFlights = [NSMutableArray new];
    self.dictImages = [NSMutableDictionary new];
    fCouldBeMoreFlights = YES;
    self.fIsValid = NO;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

	MFBAppDelegate * app = mfbApp();
    if ([app isOnLine] && ([self hasPendingFlights] || !self.fIsValid || self.rgFlights == nil))
        [self refresh];
    else
        [self.tableView reloadData];
}

- (void)didReceiveMemoryWarning {
	// Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
	
	// Release any cached data, images, etc that aren't in use.
	self.rgFlights = nil;
    [self.dictImages removeAllObjects];
	[((MFBAppDelegate *) [[UIApplication sharedApplication] delegate]) invalidateCachedTotals];
}

- (void)viewDidUnload {
	// Release any retained subviews of the main view.
	// e.g. self.myOutlet = nil;
    self.cellProgress = nil;
    self.rgFlights = nil;
    self.dictImages = nil;
    self.errorString = nil;
    self.fq = nil;
    self.ipSelectedCell = nil;
    self.JSONObjToImport = nil;
    self.urlTelemetry = nil;
    [super viewDidUnload];
}

#pragma mark Loading recent flights
- (LEEditController *) pushViewControllerForFlight:(LogbookEntry *) le
{
    LEEditController * leView = [[LEEditController alloc]
                                 initWithNibName:(UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) ? @"LEEditController-iPad" : @"LEEditController"
                                 bundle:nil];
    leView.le = le;
    leView.delegate = self;
    [self.navigationController pushViewController:leView animated:YES];
    return leView;
}

- (void) loadFlightsForUser
{
	self.errorString = @"";
	
    if (!fCouldBeMoreFlights || self.callInProgress)
        return;
    
    NSString * authtoken = mfbApp().userProfile.AuthToken;
	if ([authtoken length] == 0)
    {
		self.errorString = NSLocalizedString(@"You must be signed in to view recent flights.", @"Error - must be signed in to view flights");
        [self showError:self.errorString withTitle:NSLocalizedString(@"Error loading recent flights", @"Title for error message on recent flights")];
        fCouldBeMoreFlights = NO;
    }
    else if (![mfbApp() isOnLine])
    {
        self.errorString = NSLocalizedString(@"No connection to the Internet is available", @"Error: Offline");
        [self showError:self.errorString withTitle:NSLocalizedString(@"Error loading recent flights", @"Title for error message on recent flights")];
        fCouldBeMoreFlights = NO;
    }
	else
    {
        [self startCall];

        MFBWebServiceSvc_FlightsWithQueryAndOffset * fbdSVC = [MFBWebServiceSvc_FlightsWithQueryAndOffset new];
        
        fbdSVC.szAuthUserToken = authtoken;
        fbdSVC.fq = self.fq;
        fbdSVC.offset = @((NSInteger) self.rgFlights.count);
        fbdSVC.maxCount = @(cFlightsPageSize);
        
        MFBSoapCall * sc = [[MFBSoapCall alloc] init];
        sc.logCallData = NO;
        sc.delegate = self;
        
        [sc makeCallAsync:^(MFBWebServiceSoapBinding * b, MFBSoapCall * sc) {
            [b FlightsWithQueryAndOffsetAsyncUsingParameters:fbdSVC delegate:sc];
        }];
    }
}

- (void) BodyReturned:(id)body
{
	if ([body isKindOfClass:[MFBWebServiceSvc_FlightsWithQueryAndOffsetResponse class]])
	{
		MFBWebServiceSvc_FlightsWithQueryAndOffsetResponse * resp = (MFBWebServiceSvc_FlightsWithQueryAndOffsetResponse *) body;
        NSArray * rgIncrementalResults = resp.FlightsWithQueryAndOffsetResult.LogbookEntry;
        fCouldBeMoreFlights = (rgIncrementalResults.count >= cFlightsPageSize);
        if (self.rgFlights == nil)
            self.rgFlights = [NSMutableArray arrayWithArray:rgIncrementalResults];
        else
            [self.rgFlights addObjectsFromArray:rgIncrementalResults];
        [NSThread detachNewThreadSelector:@selector(asyncLoadThumbnailsForFlights:) toTarget:self withObject:rgIncrementalResults];
	}
}

- (void) ResultCompleted:(MFBSoapCall *)sc
{
    self.errorString = sc.errorString;
 	if ([self.errorString length] > 0)
    {
        [self showError:self.errorString withTitle:NSLocalizedString(@"Error loading recent flights", @"Title for error message on recent flights")];
        fCouldBeMoreFlights = NO;
    }
    [self endCall];
    
	self.fIsValid = YES;
    
    if (isLoading)
        [self stopLoading];
    
    [self.tableView reloadData];
    
    // update the glance.
    if (self.fq.isUnrestricted && self.rgFlights.count > 0)
        mfbApp().watchData.latestFlight = [((MFBWebServiceSvc_LogbookEntry *) self.rgFlights[0]) toSimpleItem];
}

#pragma mark Section management
- (BOOL) hasPendingFlights
{
	return [mfbApp().rgPendingFlights count] > 0;
}

- (NSInteger) ExistingFlightsSection
{
	return [self hasPendingFlights] ? 2 : 1;
}

- (NSInteger) PendingFlightsSection
{
    return [self hasPendingFlights] ? 1 : -1;
}

- (NSInteger) DateRangeSection
{
    return 0;
}

#pragma submitPendingFlights
- (void) submitPendingFlightCompleted:(MFBSoapCall *) sc fromCaller:(LogbookEntry *) le
{
    MFBAppDelegate * app = mfbApp();
    if ([le.errorString length] == 0) // success!
    {
        [app dequeuePendingFlight:le];
        [[iRate sharedInstance] logEvent:NO];   // ask user to rate the app if they have saved the requesite # of flights
        NSLog(@"iRate eventCount: %ld, uses: %ld", (long) [iRate sharedInstance].eventCount, (long) [iRate sharedInstance].usesCount);
    }
    
    iFlightInProgress++;
    
    if (iFlightInProgress >= cFlightsToSubmit)
    {
        NSLog(@"No more flights to submit");
        self.uploadInProgress = NO;
        [self refresh:NO];
    }
    else
        [self submitPendingFlight];
}

- (void) submitPendingFlight
{
    float progressValue = ((float) iFlightInProgress + 1.0) / ((float) cFlightsToSubmit);
    if (self.cellProgress == nil)
        self.cellProgress = [ProgressCell getProgressCell:self.tableView];

    self.cellProgress.progressBar.progress =  progressValue;
    NSString * flightTemplate = NSLocalizedString(@"Flight %d of %d", @"Progress message when uploading pending flights");
    self.cellProgress.progressLabel.text = [NSString stringWithFormat:flightTemplate, iFlightInProgress + 1, cFlightsToSubmit];
    self.cellProgress.progressDetailLabel.text = @"";

    // Take this off of the BACK of the array, since we're going to remove it if successful and don't want to screw up
    // the other indices.
    int index = cFlightsToSubmit - iFlightInProgress - 1;
    NSLog(@"iFlight=%d, cFlights=%d, rgCount=%lu, index=%d", iFlightInProgress, cFlightsToSubmit, (unsigned long)[mfbApp().rgPendingFlights count], index);
    MFBAppDelegate * app = mfbApp();
    LogbookEntry * le = (LogbookEntry *) (app.rgPendingFlights)[index];
    
    if ([le.errorString length] == 0) // no holdover error
    {
        le.szAuthToken = app.userProfile.AuthToken;
        le.progressLabel = self.cellProgress.progressDetailLabel;
        [le setDelegate:self completionBlock:^(MFBSoapCall * sc, MFBAsyncOperation * ao) {
            [self submitPendingFlightCompleted:sc fromCaller:(LogbookEntry *) ao];
        }];
        [le commitFlight];
    }
    else // skip the commit on this; it needs to be fixed - just go on to the next one.
        [self submitPendingFlightCompleted:nil fromCaller:le];
}

- (void) submitPendingFlights
{
    if (![self hasPendingFlights])
        return;
    
    if (![mfbApp() isOnLine])
        return;
    
    cFlightsToSubmit = (int) [mfbApp().rgPendingFlights count];
    
    if (cFlightsToSubmit == 0)
        return;
    
    self.uploadInProgress = YES;
    iFlightInProgress = 0;
    [self.tableView reloadData];
    
    [self submitPendingFlight];
}
                                            

#pragma mark Table view methods
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return [self hasPendingFlights] ? 3 : 2;
}

// Customize the number of rows in the table view.
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == [self ExistingFlightsSection])
        return self.rgFlights.count + ((self.callInProgress || fCouldBeMoreFlights) ? 1 : 0);
	else if (section == [self DateRangeSection])
        return 1;
    else if (section == [self PendingFlightsSection])
		return self.uploadInProgress ? 1 : [mfbApp().rgPendingFlights count];
    return 0; // should never happen.
}

// Customize the appearance of table view cells.
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    
	static NSString * CellIdentifier = @"recentflightcell";
    static NSString * CellQuerySelector = @"querycell";
    
    if (indexPath.section == [self DateRangeSection])
    {
        UITableViewCell *cellSelector = [tableView dequeueReusableCellWithIdentifier:CellQuerySelector];
        if (cellSelector == nil)
        {
            cellSelector = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellQuerySelector];
            cellSelector.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        cellSelector.textLabel.text = NSLocalizedString(@"FlightSearch", @"Choose Flights");
        cellSelector.detailTextLabel.text = [self.fq isUnrestricted] ? 
        NSLocalizedString(@"All Flights", @"All flights are selected") :
        NSLocalizedString(@"Not all flights", @"Not all flights are selected");
        if (cellSelector == nil)
            NSLog(@"Selector cell is nil!!!  we are about to crash");
        return cellSelector;
    }
    
    // if we are uploading pending flights, show a progress cell instead of the actual pending flights
    if (indexPath.section == [self PendingFlightsSection] && self.uploadInProgress)
    {
        if (self.cellProgress == nil)
            self.cellProgress = [ProgressCell getProgressCell:self.tableView];
        
        if (self.cellProgress == nil)
            NSLog(@"Progress cell is nil!!!; we are about to crash!");
        return self.cellProgress;
    }
    
    // otherwise, we are showing actual flights.
    RecentFlightCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        NSArray *topLevelObjects = [[NSBundle mainBundle] loadNibNamed:@"RecentFlightCell" owner:self options:nil];
        id firstObject = topLevelObjects[0];
        if ([firstObject isKindOfClass:[RecentFlightCell class]] )
            cell = firstObject;     
        else 
            cell = topLevelObjects[1];
	}
    
    // Set up the cell...
	MFBWebServiceSvc_LogbookEntry * le = nil;
    CommentedImage * ci = nil;
	NSString * errString = @"";
	if (indexPath.section == [self ExistingFlightsSection])
    {
        BOOL fIsTriggerRow = (indexPath.row >= self.rgFlights.count);   // is this the row to trigger the next batch of flights?
        if (fIsTriggerRow)
        {
            [self loadFlightsForUser];  // get the next batch
            return [self waitCellWithText:NSLocalizedString(@"Getting Recent Flights...", @"Progress - getting recent flights")];
        }
        
		le = (MFBWebServiceSvc_LogbookEntry *) (self.rgFlights)[indexPath.row];
        ci = (le == nil || le.FlightID == nil) ? nil : (CommentedImage *) (self.dictImages)[le.FlightID];
    }
	else if (indexPath.section == [self PendingFlightsSection])
    {
        LogbookEntry * l = (LogbookEntry *) (mfbApp().rgPendingFlights)[indexPath.row];
        errString = l.errorString;
        if ([l.rgPicsForFlight count] > 0)
            ci = (CommentedImage *) (l.rgPicsForFlight)[0];
		le = l.entryData;
    }

    NSAssert(le != nil, @"NULL le - we are going to crash!!!");
    
	NSDateFormatter * df = [[NSDateFormatter alloc] init];
	[df setDateStyle:NSDateFormatterShortStyle];

    if ([AutodetectOptions showFlightImages]) {
        cell.imgHasPics.image = le.FlightImages.MFBImageInfo.count > 0 ? nil : [UIImage imageNamed:@"noimage"];

        if (ci != nil && [ci hasThumbnailCache])
            cell.imgHasPics.image = [ci GetThumbnail];
        cell.imgHasPics.hidden = NO;
    } else
        cell.imgHasPics.hidden = YES;
    
    cell.lblRoute.textColor = [UIColor blackColor];
    cell.lblComments.textColor = [UIColor blackColor];
    cell.lblComments.text = [le.Comment stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([cell.lblComments.text length] == 0)
    {
        cell.lblComments.text = NSLocalizedString(@"(No Comment)", @"No Comment");
        cell.lblComments.textColor = [UIColor grayColor];
    }
    
    cell.imgSigState.hidden = (le.CFISignatureState == MFBWebServiceSvc_SignatureState_None);
    if (le.CFISignatureState == MFBWebServiceSvc_SignatureState_Valid)
        cell.imgSigState.image = [UIImage imageNamed:@"sigok"];
    else if (le.CFISignatureState == MFBWebServiceSvc_SignatureState_Invalid)
        cell.imgSigState.image = [UIImage imageNamed:@"siginvalid"];
    else
        cell.imgSigState.image = nil;
    
    if ([errString length] == 0)
    {
        cell.lblRoute.text = [le.Route stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([cell.lblRoute.text length] == 0)
        {
            cell.lblRoute.text = NSLocalizedString(@"(No Route)", @"No Route");
            cell.lblRoute.textColor = [UIColor grayColor];
        }
    }
    else
    {
        cell.lblRoute.text = [errString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        cell.lblRoute.textColor = [UIColor redColor];
    }

    if (le.TailNumDisplay == nil)
        le.TailNumDisplay = [[Aircraft sharedAircraft] AircraftByID:[le.AircraftID intValue]].TailNumber;
    
    NSString * szTimeTemplate = NSLocalizedString(@"hrs", @"Template for hours");
    NSString * szTime;
    double decTotal = (le.TotalFlightTime == nil) ? 0.0 : [le.TotalFlightTime doubleValue];
    if ([AutodetectOptions HHMMPref])
        szTime = [UITextField stringFromNumber:@(decTotal) forType:ntTime inHHMM:YES];
    else
        szTime = [NSString stringWithFormat:@"%.1f%@", decTotal, szTimeTemplate];
    
    cell.lblTitle.text = [NSString stringWithFormat:@"%@ - %@ (%@)", 
                          [df stringFromDate:le.Date],
                          le.TailNumDisplay,
                          szTime];
    
    if (cell == nil)
        NSLog(@"Cell in recent flights is nil!!! Section=%ld, row=%ld", (long)indexPath.section, (long)indexPath.row);
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.callInProgress || isLoading)
        return;

	LogbookEntry * le;
	
    if (indexPath.section == [self DateRangeSection])
    {
        if (indexPath.row == 0) // flight criteria
        {
            FlightQueryForm * fqf = [FlightQueryForm new];
            fqf.delegate = self;
            [fqf setQuery:self.fq];
            [self.navigationController pushViewController:fqf animated:YES];
        }
        return;
    }
	else if (indexPath.section == [self ExistingFlightsSection])
	{
		le = [[LogbookEntry alloc] init];
		le.entryData = (MFBWebServiceSvc_LogbookEntry *) (self.rgFlights)[indexPath.row];
	}
	else
		le = (mfbApp().rgPendingFlights)[indexPath.row];

    [self pushViewControllerForFlight:le];
}

// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    // Return NO if you do not want the specified item to be editable.
    return (indexPath.section != [self DateRangeSection]);
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
	if (editingStyle == UITableViewCellEditingStyleDelete)
	{
        self.ipSelectedCell = indexPath;
		UIAlertView * avConfirm = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Confirm Deletion", @"Title of confirm message to delete a flight")
                                                             message:NSLocalizedString(@"Are you sure you want to delete this flight?  This CANNOT be undone!", @"Delete Flight confirmation") delegate:self 
                                                   cancelButtonTitle:NSLocalizedString(@"Cancel", @"Cancel (button)") otherButtonTitles:NSLocalizedString(@"OK", @"OK"), nil];
		avConfirm.tag = alertConfirmDelete;
		[avConfirm show];
	}
}

- (void) importFlightFinished:(LogbookEntry *) le
{
    
    LEEditController * lev = [self pushViewControllerForFlight:le];
    
    // Check for an existing new flight in-progress.
    // If the new flight screen is sitting with an initial hobbs but otherwise empty, then use its starting hobbs and then reset it.
    MFBWebServiceSvc_LogbookEntry * leActiveNew = mfbApp().leMain.le.entryData;
    BOOL fIsInInitialState = leActiveNew.isInInitialState;
    NSNumber * initHobbs = fIsInInitialState ? leActiveNew.HobbsStart : @0.0;
    
    lev.le.entryData.HobbsStart = initHobbs;
    [lev autoHobbs];
    [lev autoTotal];
    
    /// Carry over the ending hobbs as the new starting hobbs for the flight.
    if (fIsInInitialState)
        mfbApp().leMain.le.entryData.HobbsStart = lev.le.entryData.HobbsEnd;
    
    self.urlTelemetry = nil;
}

- (void) importFlightWorker:(UIAlertView *) av
{
    LogbookEntry * le = [GPSSim ImportTelemetry:self.urlTelemetry];
    [av dismissWithClickedButtonIndex:0 animated:NO];
    [self performSelectorOnMainThread:@selector(importFlightFinished:) withObject:le waitUntilDone:NO];
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    switch (alertView.tag)
    {
        case alertConfirmDelete:
            if (buttonIndex == 1)
            {
                MFBAppDelegate * app = mfbApp();
                LogbookEntry * le = [[LogbookEntry alloc] init];
                
                NSIndexPath * ip = self.ipSelectedCell;
                
                if (ip.section == [self ExistingFlightsSection])
                { // deleting an existing flight
                    le.szAuthToken = app.userProfile.AuthToken;
                    MFBWebServiceSvc_LogbookEntry * leToDelete = (MFBWebServiceSvc_LogbookEntry *) (self.rgFlights)[ip.row];
                    int idFlightToDelete = [leToDelete.FlightID intValue];
                    [self.dictImages removeObjectForKey:leToDelete.FlightID];
                    [self.rgFlights removeObjectAtIndex:ip.row];
                    [le setDelegate:self completionBlock:^(MFBSoapCall * sc, MFBAsyncOperation * ao) {
                        if ([sc.errorString length] == 0)
                            [self refresh]; // will call invalidatecached totals
                        else
                        {
                            NSString * szError = [NSString stringWithFormat:@"%@ %@", NSLocalizedString(@"Unable to delete the flight.", @"Error deleting flight"), sc.errorString];
                            UIAlertView * av = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Error deleting flight", @"Title for error message when flight delete fails") message:szError delegate:nil cancelButtonTitle:NSLocalizedString(@"Close", @"Close button on error message") otherButtonTitles:nil];
                            [av show];
                        }
                    }];
                    [le deleteFlight:idFlightToDelete];
                }
                else
                    [app dequeuePendingFlight:(LogbookEntry *) (app.rgPendingFlights)[ip.row]];
                self.ipSelectedCell = nil;
            }
            break;
        case alertConfirmImport:
            {
                if (buttonIndex == 1)
                {
                    [LogbookEntry addPendingJSONFlights:self.JSONObjToImport];
                    self.JSONObjToImport = nil;
                }
            }
            break;
        case alertConfirmImportTelemetry:
            {
                if (buttonIndex == 1)
                {
                    UIAlertView *av = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"ActivityInProgress", @"Activity In Progress") message:nil delegate:nil cancelButtonTitle:nil otherButtonTitles: nil];
                    UIActivityIndicatorView *aiv = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
                    aiv.center = CGPointMake(av.bounds.size.width / 2, av.bounds.size.height - 60);
                    [av setValue:aiv forKey:@"accessoryView"];
                    [aiv startAnimating];
                    [av show];
                    [NSThread detachNewThreadSelector:@selector(importFlightWorker:) toTarget:self withObject:av];
                }
            }
            break;
    }
	
	// No matter what other path happens above, reload the data
	[self.tableView reloadData];
}

- (NSString *) tableView:(UITableView *) tableView titleForHeaderInSection:(NSInteger) section
{
    if (section == [self ExistingFlightsSection])
    {
        if ([self.rgFlights count] > 0)
            return NSLocalizedString(@"Recent Flights", @"Title for list of recent flights");
        else
            return NSLocalizedString(@"No flights found for selected dates.", @"No flights found in date range");
    }
    if (section == [self PendingFlightsSection])
        return NSLocalizedString(@"Flights pending upload", @"Title for list of flights awaiting upload");
    return @"";
}

#pragma mark QueryDelegate
- (void) queryUpdated:(MFBWebServiceSvc_FlightQuery *) f
{
    self.fq = f;
    [self refresh];
}

#pragma mark Reachability Delegate
- (void) networkAcquired
{
    if (self.uploadInProgress)
        return;
    
    NSLog(@"RecentFlights: Network acquired - submitting any pending flights");
    fCouldBeMoreFlights = YES;
    [self performSelectorOnMainThread:@selector(submitPendingFlights) withObject:nil waitUntilDone:NO];
}

#pragma mark Add flight via URL
- (void) addJSONFlight:(NSString *)szJSON
{
    NSError * error = nil;
    
    self.JSONObjToImport = [NSJSONSerialization JSONObjectWithData:[szJSON dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingMutableContainers error:&error];
    
    if (error != nil)
    {
		UIAlertView * av = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Error", @"Title for generic error message")
                                                       message:error.localizedDescription delegate:nil cancelButtonTitle:NSLocalizedString(@"Close", @"Close button on error message") otherButtonTitles:nil];
		[av show];
        self.JSONObjToImport = nil;
        return;
    }

    // get the name of the requesting app.
    NSDictionary * dictRoot = (NSDictionary *) self.JSONObjToImport;
    NSDictionary * dictMeta = (NSDictionary *) dictRoot[@"metadata"];
    NSString * szApplication = (NSString *) dictMeta[@"application"];
    	
    UIAlertView * av = [[UIAlertView alloc] initWithTitle:@""
                                       message:[NSString stringWithFormat:NSLocalizedString(@"AddFlightPrompt", @"Import Flight"), szApplication]
                                       delegate:self
                                       cancelButtonTitle:NSLocalizedString(@"Cancel", @"Cancel (button)") otherButtonTitles:NSLocalizedString(@"OK", @"OK"), nil];
    av.tag = alertConfirmImport;
    [av show];
}

#pragma mark Add flight via Telemetry
- (void) addTelemetryFlight:(NSURL *) url
{
    self.urlTelemetry = url;
    UIAlertView * av = [[UIAlertView alloc] initWithTitle:@""
                                                  message:NSLocalizedString(@"InitFromTelemetry", @"Import Flight Telemetry")
                                                 delegate:self
                                        cancelButtonTitle:NSLocalizedString(@"Cancel", @"Cancel (button)") otherButtonTitles:NSLocalizedString(@"OK", @"OK"), nil];
    av.tag = alertConfirmImportTelemetry;
    [av show];
}
@end

