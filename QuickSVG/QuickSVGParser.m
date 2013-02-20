//
//  QuickSVGParser.m
//  QuickSVG
//
//  Created by Matthew Newberry on 2/20/13.
//  Copyright (c) 2013 Matthew Newberry. All rights reserved.
//

#import "QuickSVGParser.h"
#import "QuickSVG.h"
#import "SMXMLDocument.h"
#import "QuickSVGElement.h"
#import "QuickSVGUtils.h"

@interface QuickSVGParser ()

@property (nonatomic, strong) SMXMLDocument *document;
@property (nonatomic, assign) BOOL isAborted;

- (void)parseElement:(SMXMLElement *)element;
- (void)handleSVGElement:(SMXMLElement *)element;
- (void)handleDrawingElement:(SMXMLElement *)element;
- (void)handleSymbolElement:(SMXMLElement *)element;
- (void)handleGroupElement:(SMXMLElement *)element;
- (void)handleUseElement:(SMXMLElement *)element;

- (BOOL)shouldIgnoreElement:(SMXMLElement *)element;
- (void)cleanElement:(SMXMLElement *)element;
- (NSMutableArray *)flattenedElementsForElement:(SMXMLElement *)element;

- (void)addInstanceOfSymbol:(SMXMLElement *)symbol child:(SMXMLElement *)child;
- (QuickSVGElement *)elementFromXMLNode:(SMXMLElement *)element;

/* Parser Callbacks */
- (void)notifyDidParseElement:(QuickSVGElement *)element;
- (void)notifyWillParse;
- (void)notifyDidParse;

/* Utilities */
- (CGRect)frameFromAttributes:(NSDictionary *)attributes;

@end

@implementation QuickSVGParser

- (id)initWithQuickSVG:(QuickSVG *)quickSVG
{
	self = [super init];
	
	if(self) {
		self.quickSVG = quickSVG;
		self.symbols = [NSMutableDictionary dictionary];
		self.instances = [NSMutableDictionary dictionary];
		self.groups = [NSMutableDictionary dictionary];
		self.isAborted = NO;
	}
	
	return self;
}

- (BOOL)parseSVGFileWithURL:(NSURL *) url
{
	if (url == nil)
        return NO;
    
    if(_document) {
        [self.document abort];
        self.document = nil;
    }
    
    [self notifyWillParse];
    
    [_symbols removeAllObjects];
    [_instances removeAllObjects];
    [_groups removeAllObjects];
    _isAborted = NO;
    
    NSError *error;
	NSData *data = [NSData dataWithContentsOfURL:url];
    self.document = [[SMXMLDocument alloc] initWithData:data error:&error];
    
    if(error) {
        NSLog(@"%@", error);
        return NO;
    }
    
    self.isParsing = YES;
    
    SMXMLElement *root = self.document.root;
    [self cleanElement:root];
    
    if([root.name isEqualToString:@"svg"])
        [self handleSVGElement:root];
    
    [root.children enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
       
        if(self.isAborted) {
            *stop = YES;
        }
        
        SMXMLElement *element = (SMXMLElement *)obj;
        [self parseElement:element];
    }];
    
    [self notifyDidParse];
    
    return YES;
}

#pragma Elements
- (void)parseElement:(SMXMLElement *)element
{
    if([element.name isEqualToString:@"symbol"]) {
        [self handleSymbolElement:element];
    } else if([element.name isEqualToString:@"g"]) {
        [self handleGroupElement:element];
    } else if([element.name isEqualToString:@"use"]) {
        [self handleUseElement:element];
    } else {
        [self handleDrawingElement:element];
    }
}

- (void)handleSVGElement:(SMXMLElement *)element
{
    self.quickSVG.canvasFrame = [self frameFromAttributes:element.attributes];
}

- (void)handleDrawingElement:(SMXMLElement *)element
{
    QuickSVGElement *instance = [self elementFromXMLNode:element];
    [self notifyDidParseElement:instance];
}

- (void)handleSymbolElement:(SMXMLElement *)element
{
    NSString *key = [[element.attributes allKeys] containsObject:@"id"] ? element.attributes[@"id"] : [NSString stringWithFormat:@"Symbol%i", [_symbols count] + 1];
    
    NSMutableArray *flat = [self flattenedElementsForElement:element];
    [element.children removeAllObjects];
    [element.children addObjectsFromArray:flat];
    self.symbols[key] = element;
}

- (void)handleGroupElement:(SMXMLElement *)element
{
    NSString *key = [[element.attributes allKeys] containsObject:@"id"] ? element.attributes[@"id"] : [NSString stringWithFormat:@"Group%i", [_symbols count] + 1];
    self.groups[key] = element;
    
    NSArray *elements = [self flattenedElementsForElement:element];
    [elements enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        
        SMXMLElement *element = (SMXMLElement *)obj;
        [self parseElement:element];        
    }];
}

- (void)handleUseElement:(SMXMLElement *)element
{
    if(!element.attributes[@"xlink:href"])
        return;
    
    NSString *symbolRef = [element.attributes[@"xlink:href"] substringFromIndex:1];
    SMXMLElement *symbol = self.symbols[symbolRef];
    
    [self addInstanceOfSymbol:symbol child:element];
}

- (BOOL)shouldIgnoreElement:(SMXMLElement *)element
{
    BOOL ignore = NO;
    
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF BEGINSWITH %@", self.quickSVG.ignorePattern];
    ignore = [predicate evaluateWithObject:element.attributes[@"id"]];
    
    if(!ignore && [element.attributes[@"display"] isEqualToString:@"none"]) {
        ignore = YES;
    }
    
    return ignore;
}

- (void)cleanElement:(SMXMLElement *)element
{
    if([self shouldIgnoreElement:element]) {
        [element.parent.children removeObject:element];
        return;
    }
    
    NSArray *children = [NSArray arrayWithArray:element.children];
    [children enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        
        SMXMLElement *element = (SMXMLElement *)obj;
        [self cleanElement:element];
    }];
}

- (NSMutableArray *)flattenedElementsForElement:(SMXMLElement *)element
{
    __block NSMutableArray *elements = [NSMutableArray array];
    
    [element.children enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        
        SMXMLElement *child = (SMXMLElement *)obj;
        if([child.children count] > 0) {
            [elements addObjectsFromArray:[self flattenedElementsForElement:child]];
        } else {
            
            // Merge group properties, giving preference to child attributes
            if([child.parent.name isEqualToString:@"g"]) {
                NSMutableDictionary *attributes = [NSMutableDictionary dictionaryWithDictionary:child.parent.attributes];
                [attributes addEntriesFromDictionary:child.attributes];
                [child.attributes removeAllObjects];
                [child.attributes addEntriesFromDictionary:attributes];
            }
            
            [elements addObject:child];
        }
    }];
    
    return elements;
}

#pragma Instance Factory
- (QuickSVGElement *)elementFromXMLNode:(SMXMLElement *)element
{
    CGRect frame = [self frameFromAttributes:element.attributes];

	QuickSVGElement *instance = [[QuickSVGElement alloc] initWithFrame:frame];
    
    if(element.attributes[@"transform"]) {
        instance.transform = makeTransformFromSVGMatrix(element.attributes[@"transform"]);
    }
    
	[instance.attributes addEntriesFromDictionary:element.attributes];
	instance.quickSVG = self.quickSVG;
    instance.elements = [element.children count] > 0 ? [self flattenedElementsForElement:element] : @[element];

	return instance;
}

- (void)addInstanceOfSymbol:(SMXMLElement *)symbol child:(SMXMLElement *)child
{
    QuickSVGElement *instance = [self elementFromXMLNode:child];
    instance.frame = [self frameFromAttributes:symbol.attributes];
    
    NSMutableDictionary *attr = [NSMutableDictionary dictionaryWithDictionary:symbol.attributes];
    [attr addEntriesFromDictionary:child.attributes];
    instance.attributes = attr;
    instance.elements = symbol.children;

    [self notifyDidParseElement:instance];
}

#pragma Delegate callbacks
- (void)notifyDidParseElement:(QuickSVGElement *)element
{    
    if(_delegate && [_delegate respondsToSelector:@selector(quickSVG:didParseElement:)]) {
        [self.delegate quickSVG:self.quickSVG didParseElement:element];
    }
}

- (void)notifyWillParse
{
    if(_delegate && [_delegate respondsToSelector:@selector(quickSVGWillParse:)]) {
        [self.delegate quickSVGWillParse:self.quickSVG];
    }
}

- (void)notifyDidParse
{
    if(_delegate && [_delegate respondsToSelector:@selector(quickSVGDidParse:)]) {
        [self.delegate quickSVGDidParse:self.quickSVG];
    }
}



#pragma Utilities

- (void)abort
{
	self.isAborted = YES;
    [self.document abort];
}

- (CGRect)frameFromAttributes:(NSDictionary *)attributes
{
    CGRect frame = CGRectZero;
    if(attributes[@"viewBox"]) {
        NSArray *pieces = [attributes[@"viewBox"] componentsSeparatedByString:@" "];
        frame = CGRectMake([pieces[0] floatValue], [pieces[1] floatValue], [pieces[2] floatValue], [pieces[3] floatValue]);
    } else if(attributes[@"x"]) {
        frame = CGRectMake([attributes[@"x"] floatValue], [attributes[@"y"] floatValue], [attributes[@"width"] floatValue], [attributes[@"height"] floatValue]);
    } else if(attributes[@"width"]){
        frame = CGRectMake(0,0, [attributes[@"width"] floatValue], [attributes[@"height"] floatValue]);
    }
    
    return frame;
}

@end