/*
	MyFlightbook for iOS - provides native access to MyFlightbook
	pilot's logbook
 Copyright (C) 2011-2018 MyFlightbook, LLC
 
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
//  TotalsRow.h
//  MFBSample
//
//  Created by Eric Berman on 6/17/11.
//  Copyright 2011-2017 MyFlightbook LLC. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "MFBWebServiceSvc.h"

@interface TotalsRow : UITableViewCell {
    IBOutlet UILabel * txtLabel;
    IBOutlet UILabel * txtValue;
    IBOutlet UILabel * txtSubDesc;
}

@property (nonatomic, strong) IBOutlet UILabel * txtLabel;
@property (nonatomic, strong) IBOutlet UILabel * txtValue;
@property (nonatomic, strong) IBOutlet UILabel * txtSubDesc;

+ (TotalsRow *) rowForTotal:(MFBWebServiceSvc_TotalsItem *) ti forTableView:tableView usngHHMM:(BOOL) fHHMM;

@end
