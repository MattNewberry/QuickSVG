//
//  QuickSVGInstance.h
//  QuickSVG
//
//  Created by Matthew Newberry on 9/28/12.
//  Copyright (c) 2012 Matthew Newberry. All rights reserved.
//

#import "QuickSVGSymbol.h"

@interface QuickSVGInstance : UIView

@property (nonatomic, strong) QuickSVGSymbol *symbol;
@property (nonatomic, strong) id object;
@property (nonatomic, strong) NSDictionary *attributes;

@end






#warning It's redrawing everytime you zoom, every path