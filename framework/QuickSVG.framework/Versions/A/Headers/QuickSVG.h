//
//  QuickSVG.h
//  QuickSVG
//
//  Created by Matthew Newberry on 9/26/12.
//  Copyright (c) 2012 Matthew Newberry. All rights reserved.
//

@class QuickSVGInstance, QuickSVG;

@protocol QuickSVGDelegate <NSObject>

- (void) quickSVG:(QuickSVG *) quickSVG didSelectInstance:(QuickSVGInstance *) instance;
- (BOOL) quickSVG:(QuickSVG *) quickSVG shouldSelectInstance:(QuickSVGInstance *) instance;

@end

@interface QuickSVG : NSObject <NSXMLParserDelegate>

@property (nonatomic, strong) id <QuickSVGDelegate> delegate;
@property (nonatomic, strong) NSMutableDictionary *symbols;
@property (nonatomic, strong) NSMutableArray *instances;
@property (nonatomic, strong) NSMutableArray *groups;
@property (nonatomic, strong) UIView *view;
@property (nonatomic, assign) CGRect canvasFrame;

+ (QuickSVG *) svgFromURL:(NSURL *) url;
- (BOOL) parseSVGFileWithURL:(NSURL *) url;

@end