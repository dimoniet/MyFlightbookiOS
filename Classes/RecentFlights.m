/*
	MyFlightbook for iOS - provides native access to MyFlightbook
	pilot's logbook
 Copyright (C) 2010-2019 MyFlightbook, LLC
 
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
//

#import "RecentFlights.h"
#import "MFBAppDelegate.h"
#import "MFBSoapCall.h"
#import "RecentFlightCell.h"
#import "DecimalEdit.h"
#import "FlightProps.h"
#import "iRate.h"
#import "MFBTheme.h"
#import "WPSAlertController.h"

@interface RecentFlights()
@property (atomic, strong) NSMutableDictionary * dictImages;
@property (atomic, assign) BOOL uploadInProgress;
@property (atomic, strong) NSIndexPath * ipSelectedCell;
@property (atomic, strong) id JSONObjToImport;
@property (nonatomic, strong) NSURL * urlTelemetry;
@property (readwrite, strong) NSMutableArray * rgFlights;
@property (readwrite, strong) NSString * errorString;

- (BOOL) hasPendingFlights;
@end

@implementation RecentFlights

static const int cFlightsPageSize=15;   // number of flights to download at a time by default.

NSInteger iFlightInProgress, cFlightsToSubmit;
BOOL fCouldBeMoreFlights;

@synthesize rgFlights, errorString, fq, cellProgress, uploadInProgress, dictImages, ipSelectedCell, JSONObjToImport, urlTelemetry;

- (void) asyncLoadThumbnailsForFlights:(NSArray *) flights {
    if (flights == nil || ![AutodetectOptions showFlightImages])
        return;
    
    @autoreleasepool {
        for (MFBWebServiceSvc_LogbookEntry * le in flights) {
            // crash if you store into a dictionary using nil key, so check for that
            if (le == nil || le.FlightID == nil || self.dictImages[le.FlightID] != nil)
                continue;
            
            CommentedImage * ci = [CommentedImage new];
            if ([le.FlightImages.MFBImageInfo count] > 0)
                ci.imgInfo = (MFBWebServiceSvc_MFBImageInfo *) (le.FlightImages.MFBImageInfo)[0];
            else  {
                // try to get an aircraft image.
                MFBWebServiceSvc_Aircraft * ac = [[Aircraft sharedAircraft] AircraftByID:[le.AircraftID intValue]];
                if ([ac.AircraftImages.MFBImageInfo count] > 0)
                    ci.imgInfo = (MFBWebServiceSvc_MFBImageInfo *) (ac.AircraftImages.MFBImageInfo)[0];
                else
                    ci.imgInfo = nil;
            }
            
            [ci GetThumbnail];
            @synchronized (self) {
                self.dictImages[le.FlightID] = ci;  // TODO: this line is crashing sometimes.  EXC_BAD_ACCESS.  Why?
            }
        }
        [self performSelectorOnMainThread:@selector(reload) withObject:nil waitUntilDone:NO];
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
    self.tableView.backgroundColor = MFBTheme.currentTheme.tableBackColor;
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
    if (!mfbApp().isOnLine) {
        self.errorString = NSLocalizedString(@"No connection to the Internet is available", @"Error: Offline");
        [self showError:self.errorString withTitle:NSLocalizedString(@"Error loading recent flights", @"Title for error message on recent flights")];
        return;
    }
    
    @synchronized (self) {
        if (self.dictImages == nil)
            self.dictImages = [NSMutableDictionary new];
        else
            [self.dictImages removeAllObjects];
    }
    self.rgFlights = [[NSMutableArray alloc] init];
    fCouldBeMoreFlights = YES;
	MFBAppDelegate * app = mfbApp();
	[app invalidateCachedTotals];
    
    // if we are forcing a resubmit, clear any errors and resubmit; this will cause 
    // loadFlightsForUser to be called (refreshing the existing flights.)
    // Otherwise, just do the refresh directly.
    if (fSubmitPending && self.hasPendingFlights)
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
    @synchronized (self) {
        if (self.dictImages == nil)
            self.dictImages = [NSMutableDictionary new];
        else
            [self.dictImages removeAllObjects];
    }
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
    @synchronized (self) {
        [self.dictImages removeAllObjects];
    }
	[((MFBAppDelegate *) [[UIApplication sharedApplication] delegate]) invalidateCachedTotals];
}

#pragma View a flight
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

#pragma mark Loading recent flights / infinite scroll
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
        
        // Update any high-water mark tach/hobbs
        Aircraft * aircraft = [Aircraft sharedAircraft];
        for (MFBWebServiceSvc_LogbookEntry * le in self.rgFlights) {
            [aircraft setHighWaterHobbs:le.HobbsEnd forAircraft:le.AircraftID];
            if (le.CustomProperties != nil && le.CustomProperties.CustomFlightProperty != nil) {
                for(MFBWebServiceSvc_CustomFlightProperty * cfp in le.CustomProperties.CustomFlightProperty) {
                    if (cfp.PropTypeID.intValue == PropTypeID_TachEnd) {
                        [aircraft setHighWaterTach:cfp.DecValue forAircraft:le.AircraftID];
                        break;
                    }
                }
            }
        }
            
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

#pragma pendingflights
- (BOOL) hasPendingFlights {
	return [mfbApp().rgPendingFlights count] > 0;
}

- (void) submitPendingFlightCompleted:(MFBSoapCall *) sc fromCaller:(LogbookEntry *) le {
    MFBAppDelegate * app = mfbApp();
    if ([le.errorString length] == 0 && !le.entryData.isQueued) { // success
        [app dequeuePendingFlight:le];
        [[iRate sharedInstance] logEvent:NO];   // ask user to rate the app if they have saved the requesite # of flights
        NSLog(@"iRate eventCount: %ld, uses: %ld", (long) [iRate sharedInstance].eventCount, (long) [iRate sharedInstance].usesCount);
        [self.tableView reloadData];
    }
    
    iFlightInProgress++;
    
    if (iFlightInProgress >= cFlightsToSubmit) {
        NSLog(@"No more flights to submit");
        self.uploadInProgress = NO;
        [self refresh:NO];
    }
    else
        [self submitPendingFlight];
}

- (void) submitPendingFlight {
    float progressValue = ((float) iFlightInProgress + 1.0) / ((float) cFlightsToSubmit);
    if (self.cellProgress == nil)
        self.cellProgress = [ProgressCell getProgressCell:self.tableView];

    self.cellProgress.progressBar.progress =  progressValue;
    NSString * flightTemplate = NSLocalizedString(@"Flight %d of %d", @"Progress message when uploading pending flights");
    self.cellProgress.progressLabel.text = [NSString stringWithFormat:flightTemplate, iFlightInProgress + 1, cFlightsToSubmit];
    self.cellProgress.progressDetailLabel.text = @"";

    // Take this off of the BACK of the array, since we're going to remove it if successful and don't want to screw up
    // the other indices.
    MFBAppDelegate * app = mfbApp();
    NSInteger index = cFlightsToSubmit - iFlightInProgress - 1;
    NSLog(@"iFlight=%ld, cFlights=%ld, rgCount=%lu, index=%ld", (long) iFlightInProgress, (long) cFlightsToSubmit, (long) app.rgPendingFlights.count, (long) index);
    if (app.rgPendingFlights == nil || index >= app.rgPendingFlights.count) // should never happen.
        return;
    
    LogbookEntry * le = (LogbookEntry *) (app.rgPendingFlights)[index];
    
    if (!le.entryData.isQueued && le.errorString.length == 0) { // no holdover error
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

- (void) submitPendingFlights {
    if (![self hasPendingFlights] || ![mfbApp() isOnLine])
        return;
    
    cFlightsToSubmit = mfbApp().rgPendingFlights.count;
    
    if (cFlightsToSubmit == 0)
        return;
    
    self.uploadInProgress = YES;
    iFlightInProgress = 0;
    [self.tableView reloadData];
    
    [self submitPendingFlight];
}

#pragma mark Table view methods
typedef enum {sectFlightQuery, sectUploadInProgress, sectPendingFlights, sectExistingFlights} RecentSection;

- (RecentSection) sectionFromIndexPathSection:(NSInteger) section {
    BOOL fHasPendingFlights = self.hasPendingFlights;
    switch (section) {
        case 0:
            return sectFlightQuery;
        case 1:
            return (self.uploadInProgress) ? sectUploadInProgress : (fHasPendingFlights ? sectPendingFlights : sectExistingFlights);
        default:
            return sectExistingFlights;
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return [self hasPendingFlights] ? 3 : 2;
}

// Customize the number of rows in the table view.
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch ([self sectionFromIndexPathSection:section]) {
        case sectFlightQuery:
            return 1;
        case sectUploadInProgress:
            return 1;
        case sectPendingFlights:
            return mfbApp().rgPendingFlights.count;
        case sectExistingFlights:
            return self.rgFlights.count + ((self.callInProgress || fCouldBeMoreFlights) ? 1 : 0);
        default:
            NSAssert(NO, @"Unknown section requested");
            return 0;
    }
}

- (NSString *) tableView:(UITableView *) tableView titleForHeaderInSection:(NSInteger) section
{
    switch ([self sectionFromIndexPathSection:section]) {
        case sectExistingFlights:
            if ([self.rgFlights count] > 0)
                return NSLocalizedString(@"Recent Flights", @"Title for list of recent flights");
            else
                return NSLocalizedString(@"No flights found for selected dates.", @"No flights found in date range");
        case sectPendingFlights:
            return NSLocalizedString(@"Flights pending upload", @"Title for list of flights awaiting upload");
        case sectUploadInProgress:
        case sectFlightQuery:
            return @"";
    }
}

// Customize the appearance of table view cells.
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    MFBWebServiceSvc_LogbookEntry * le = nil;
    CommentedImage * ci = nil;
    NSString * errString = @"";
    
    switch ([self sectionFromIndexPathSection:indexPath.section]) {
        case sectFlightQuery: {
            static NSString * CellQuerySelector = @"querycell";
            UITableViewCell *cellSelector = [tableView dequeueReusableCellWithIdentifier:CellQuerySelector];
            if (cellSelector == nil) {
                cellSelector = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellQuerySelector];
                cellSelector.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            }
            NSAssert(cellSelector, @"cellSelector (flight query) is nil, we are about to crash");
            cellSelector.textLabel.text = NSLocalizedString(@"FlightSearch", @"Choose Flights");
            cellSelector.detailTextLabel.text = [self.fq isUnrestricted] ? NSLocalizedString(@"All Flights", @"All flights are selected") : NSLocalizedString(@"Not all flights", @"Not all flights are selected");
            cellSelector.imageView.image = [UIImage imageNamed:@"search.png"];
            return cellSelector;
        }
        case sectUploadInProgress: {
            if (self.cellProgress == nil)
                self.cellProgress = [ProgressCell getProgressCell:self.tableView];
            NSAssert(self.cellProgress, @"cellProgress is nil, we are about to crash");
            return self.cellProgress;
        }
        case sectPendingFlights: {
            // We could have a race condition where we are fetching a pending flight after it has been submitted.
            LogbookEntry * l;
            
            @try {
                l = (LogbookEntry *) (mfbApp().rgPendingFlights)[indexPath.row];
            }
            @catch (NSException * ex) {
                // shouldn't happen, but if it does, just create a dummy entry
                l = [[LogbookEntry alloc] init];
                l.entryData.Date = [NSDate date];
                l.entryData.TailNumDisplay = @"...";
            }

            errString = l.errorString;
            ci = (l.rgPicsForFlight != nil && l.rgPicsForFlight.count > 0) ? (CommentedImage *) (l.rgPicsForFlight)[0] : nil;
            le = l.entryData;
            NSAssert(le != nil, @"NULL le in pending flights - we are going to crash!!!");
            break;
        }
        case sectExistingFlights: {
            BOOL fIsTriggerRow = (indexPath.row >= self.rgFlights.count);   // is this the row to trigger the next batch of flights?
            if (fIsTriggerRow)
            {
                [self loadFlightsForUser];  // get the next batch
                return [self waitCellWithText:NSLocalizedString(@"Getting Recent Flights...", @"Progress - getting recent flights")];
            }
            
            le = (MFBWebServiceSvc_LogbookEntry *) (self.rgFlights)[indexPath.row];
            @synchronized (self) {
                ci = (le == nil || le.FlightID == nil) ? nil : (CommentedImage *) (self.dictImages)[le.FlightID];
            }
            
            NSAssert(le != nil, @"NULL le in existing flights - we are going to crash!!!"); // TODO: still crash here sometimes.  Why?
            break;
        }
    }
    
    NSAssert(le != nil, @"NULL le - we are going to crash!!!");
    
    // If we are here, we are showing actual flights.
    static NSString * CellIdentifier = @"recentflightcell";
    RecentFlightCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        NSArray *topLevelObjects = [[NSBundle mainBundle] loadNibNamed:@"RecentFlightCell" owner:self options:nil];
        id firstObject = topLevelObjects[0];
        if ([firstObject isKindOfClass:[RecentFlightCell class]] )
            cell = firstObject;
        else
            cell = topLevelObjects[1];
    }
    NSAssert(cell != nil, @"nil flight cell - we are going to crash!!!");
    
    if (le.TailNumDisplay == nil)
        le.TailNumDisplay = [[Aircraft sharedAircraft] AircraftByID:[le.AircraftID intValue]].TailNumber;
    
    [cell setFlight:le withImage:ci withError:errString];
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.callInProgress || isLoading)
        return;

	LogbookEntry * le = nil;
	
    switch ([self sectionFromIndexPathSection:indexPath.section]) {
        case sectFlightQuery: {
            NSAssert(indexPath.row == 0, @"Flight query row must only have one row!");
            FlightQueryForm * fqf = [FlightQueryForm new];
            fqf.delegate = self;
            [fqf setQuery:self.fq];
            [self.navigationController pushViewController:fqf animated:YES];
            return;
        }
        case sectUploadInProgress:
            return;
        case sectExistingFlights:
            le = [[LogbookEntry alloc] init];
            if (self.rgFlights == nil || indexPath.row >= self.rgFlights.count) // should never happen.
                return;
            le.entryData = (MFBWebServiceSvc_LogbookEntry *) (self.rgFlights)[indexPath.row];
            break;
        case sectPendingFlights:
            le = (mfbApp().rgPendingFlights)[indexPath.row];
            break;
    }

    NSAssert(le != nil, @"Unable to find the flight to display!");
    [self pushViewControllerForFlight:le];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    switch ([self sectionFromIndexPathSection:indexPath.section]) {
        case sectFlightQuery:
        case sectUploadInProgress:
            return NO;
        case sectExistingFlights:
        case sectPendingFlights:
            return YES;
    }
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (editingStyle == UITableViewCellEditingStyleDelete) {
        self.ipSelectedCell = indexPath;
        UIAlertController * alert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Confirm Deletion", @"Title of confirm message to delete a flight")
                                                                        message:NSLocalizedString(@"Are you sure you want to delete this flight?  This CANNOT be undone!", @"Delete Flight confirmation") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Cancel (button)") style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"OK") style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
            MFBAppDelegate * app = MFBAppDelegate.threadSafeAppDelegate;
            LogbookEntry * le = [[LogbookEntry alloc] init];
            
            NSIndexPath * ip = self.ipSelectedCell;
            
            RecentSection rs = [self sectionFromIndexPathSection:ip.section];
            
            if (rs == sectExistingFlights) {
                // deleting an existing flight
                le.szAuthToken = app.userProfile.AuthToken;
                MFBWebServiceSvc_LogbookEntry * leToDelete = (MFBWebServiceSvc_LogbookEntry *) (self.rgFlights)[ip.row];
                int idFlightToDelete = [leToDelete.FlightID intValue];
                @synchronized (self) {
                    [self.dictImages removeObjectForKey:leToDelete.FlightID];
                }
                [self.rgFlights removeObjectAtIndex:ip.row];
                [le setDelegate:self completionBlock:^(MFBSoapCall * sc, MFBAsyncOperation * ao) {
                    if ([sc.errorString length] == 0)
                        [self refresh]; // will call invalidatecached totals
                    else {
                        NSString * szError = [NSString stringWithFormat:@"%@ %@", NSLocalizedString(@"Unable to delete the flight.", @"Error deleting flight"), sc.errorString];
                        [self showAlertWithTitle:NSLocalizedString(@"Error deleting flight", @"Title for error message when flight delete fails") message:szError];
                    }
                }];
                [le deleteFlight:idFlightToDelete];
            }
            else if (rs == sectPendingFlights)
                [app dequeuePendingFlight:(LogbookEntry *) (app.rgPendingFlights)[ip.row]];
            self.ipSelectedCell = nil;
            [self.tableView reloadData];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
	}
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

#pragma mark Import
- (void) importFlightFinished:(LogbookEntry *) le {
    // dismiss the progress indicator
    [self dismissViewControllerAnimated:YES completion:nil];
    
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
    [self.tableView reloadData];
}

- (void) importFlightWorker
{
    LogbookEntry * le = [GPSSim ImportTelemetry:self.urlTelemetry];
    [self performSelectorOnMainThread:@selector(importFlightFinished:) withObject:le waitUntilDone:NO];
}

#pragma mark Add flight via URL
- (void) addJSONFlight:(NSString *)szJSON
{
    NSError * error = nil;
    
    self.JSONObjToImport = [NSJSONSerialization JSONObjectWithData:[szJSON dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingMutableContainers error:&error];
    
    if (error != nil)
    {
        [self showErrorAlertWithMessage:error.localizedDescription];
        self.JSONObjToImport = nil;
        return;
    }

    // get the name of the requesting app.
    NSDictionary * dictRoot = (NSDictionary *) self.JSONObjToImport;
    NSDictionary * dictMeta = (NSDictionary *) dictRoot[@"metadata"];
    NSString * szApplication = (NSString *) dictMeta[@"application"];
    
    UIAlertController * alert = [UIAlertController alertControllerWithTitle:@"" message:[NSString stringWithFormat:NSLocalizedString(@"AddFlightPrompt", @"Import Flight"), szApplication] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Cancel (button)") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"OK") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [LogbookEntry addPendingJSONFlights:self.JSONObjToImport];
        self.JSONObjToImport = nil;
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark Add flight via Telemetry
- (void) addTelemetryFlight:(NSURL *) url
{
    self.urlTelemetry = url;
    UIAlertController * alert = [UIAlertController alertControllerWithTitle:@"" message:NSLocalizedString(@"InitFromTelemetry", @"Import Flight Telemetry") preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Cancel (button)") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"OK") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [WPSAlertController presentProgressAlertWithTitle:NSLocalizedString(@"ActivityInProgress", @"Activity In Progress") onViewController:self];
        [NSThread detachNewThreadSelector:@selector(importFlightWorker) toTarget:self withObject:nil];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end

