//
//  QuickSVGInstance.m
//  QuickSVG
//
//  Created by Matthew Newberry on 9/28/12.
//  Copyright (c) 2012 Matthew Newberry. All rights reserved.
//

#import "QuickSVGInstance.h"
#import "QuickSVG.h"
#import "QuickSVGInstance+Style.h"
#import "UIColor+Additions.h"
#import "QuickSVGUtils.h"
#import "UIBezierPath+Additions.h"

#define kTransformKey @"matrix"
#define kAcceptableBasicShapeTypes @[@"rect", @"circle", @"ellipse"]
#define kAcceptablePathTypes @[@"path", @"polygon", @"line", @"polyline"]

NSInteger const maxPathComplexity	= 1000;
NSInteger const maxParameters		= 64;
NSInteger const maxTokenLength		= 64;
NSString* const separatorCharString = @"-,CcMmLlHhVvZzqQaAsS";
NSString* const commandCharString	= @"CcMmLlHhVvZzqQaAsS";
unichar const invalidCommand		= '*';

@interface Token : NSObject {
@private
	unichar			command;
	NSMutableArray  *values;
}

- (id)initWithCommand:(unichar)commandChar;
- (void)addValue:(CGFloat)value;
- (CGFloat)parameter:(NSInteger)index;
- (NSInteger)valence;

@property(nonatomic, assign) unichar command;

@end

@implementation Token

- (id)initWithCommand:(unichar)commandChar {
	self = [self init];
    if (self) {
		command = commandChar;
		values = [[NSMutableArray alloc] initWithCapacity:maxParameters];
	}
	return self;
}

- (void)addValue:(CGFloat)value {
	[values addObject:[NSNumber numberWithDouble:value]];
}

- (CGFloat)parameter:(NSInteger)index {
	return [[values objectAtIndex:index] doubleValue];
}

- (NSInteger)valence
{
	return [values count];
}


@synthesize command;

@end


@interface QuickSVGInstance ()

@property (nonatomic, assign) CGFloat pathScale;
@property (nonatomic, strong) NSCharacterSet *separatorSet;
@property (nonatomic, strong) NSCharacterSet *commandSet;
@property (nonatomic, assign) CGPoint lastPoint;
@property (nonatomic, assign) CGPoint lastControlPoint;
@property (nonatomic, assign) BOOL validLastControlPoint;
@property (nonatomic, strong) NSMutableArray *tokens;
@property (nonatomic, strong) UIBezierPath *bezierPathBeingDrawn;
@property (nonatomic, strong) NSMutableArray *shapeLayers;
@property (nonatomic, assign) CGFloat scale;

- (QuickSVGElementType) elementTypeForElement:(NSDictionary *) element;
- (CATextLayer *) addTextWithAttributes:(NSDictionary *) attributes;
- (UIBezierPath *) addPath:(NSString *) pathType withAttributes:(NSDictionary *) attributes;
- (UIBezierPath *) addBasicShape:(NSString *) shapeType withAttributes:(NSDictionary *) attributes;
- (UIBezierPath *) drawRectWithAttributes:(NSDictionary *) attributes;
- (UIBezierPath *) drawCircleWithAttributes:(NSDictionary *) attributes;
- (UIBezierPath *) drawEllipseWithAttributes:(NSDictionary *) attributes;
- (UIBezierPath *) drawPathWithAttributes:(NSDictionary *) attributes;
- (UIBezierPath *) drawLineWithAttributes:(NSDictionary *) attributes;
- (UIBezierPath *) drawPolylineWithAttributes:(NSDictionary *) attributes;
- (UIBezierPath *) drawPolygonWithAttributes:(NSDictionary *) attributes;
- (NSMutableArray *)parsePath:(NSString *)attr;
- (CGAffineTransform) svgTransform;
- (void)reset;
- (void)appendSVGMCommand:(Token *)token;
- (void)appendSVGLCommand:(Token *)token;
- (void)appendSVGCCommand:(Token *)token;
- (void)appendSVGSCommand:(Token *)token;
- (NSArray *) arrayFromPointsAttribute:(NSString *) points;

@end

@implementation QuickSVGInstance

- (id) initWithFrame:(CGRect)frame
{
	self = [super initWithFrame:frame];
	
	if(self) {		
		[self setup];
	}
	
	return self;
}

- (void) setup
{
    self.pathScale = 0;
    self.separatorSet = [NSCharacterSet characterSetWithCharactersInString:separatorCharString];
    self.commandSet = [NSCharacterSet characterSetWithCharactersInString:commandCharString];
    self.attributes = [NSMutableDictionary dictionary];
    self.drawingLayer = [CAShapeLayer layer];
    self.shapeLayers = [NSMutableArray array];
    self.opaque = YES;
    [self.layer addSublayer:_drawingLayer];
    
    [self reset];
}

- (void) touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
	BOOL shouldSelect = YES;
	
	if(_quickSVG.delegate == nil)
		return;
	
	if([_quickSVG.delegate respondsToSelector:@selector(quickSVG:shouldSelectInstance:)]) {
		shouldSelect = [_quickSVG.delegate quickSVG:_quickSVG shouldSelectInstance:self];
	}
	
	if(shouldSelect && [_quickSVG.delegate respondsToSelector:@selector(quickSVG:didSelectInstance:)]) {
		[_quickSVG.delegate quickSVG:_quickSVG didSelectInstance:self];
	}
	else {
		[super touchesBegan:touches withEvent:event];
	}
}

- (void) setFrame:(CGRect)frame
{
    self.scale = aspectScale(self.frame.size, frame.size);
    
    if(!isnan(_scale) && _scale != INFINITY && _scale != 1 && !CGRectEqualToRect(frame, CGRectZero) && !CGRectEqualToRect(self.frame, CGRectZero)) {
                
        CGAffineTransform scale = CGAffineTransformMakeScale(_scale, _scale);
        
        if(self.attributes[@"transform"]) {
            CGAffineTransform svgTransform = [self svgTransform];
            scale = CGAffineTransformScale(scale, getXScale(svgTransform), getYScale(svgTransform));
        }
        CGSize shapeSize = CGSizeApplyAffineTransform(_shapePath.bounds.size, scale);
        CGSize frameSize = frame.size;
                
        self.transform = scale;                
        _drawingLayer.frame = CGRectIntegral( CGRectMake((frameSize.width / 2 - shapeSize.width / 2) / _scale / getXScale([self svgTransform]),
                                                         (frameSize.height / 2 - shapeSize.height / 2) / _scale / getYScale([self svgTransform]),
                                                         _shapePath.bounds.size.width,
                                                         _shapePath.bounds.size.height) );
    }
    
    [super setFrame:frame];
}

- (CGAffineTransform) svgTransform
{
    CGAffineTransform transform = CGAffineTransformIdentity;
    
    if(self.attributes[@"transform"]) {
        transform = makeTransformFromSVGMatrix(self.attributes[@"transform"]);
    }
    
    return transform;
}

- (void) setElements:(NSArray *)elements
{	
	if([elements count] == 0)
		return;
    
    _elements = elements;
				    
    CGAffineTransform pathTransform = CGAffineTransformIdentity;
    
    CGFloat transX = self.frame.origin.x;
    CGFloat transY = self.frame.origin.y;

    pathTransform = CGAffineTransformTranslate(pathTransform, -transX, -transY);
    
    // Custom transform previously applied, need to flip the y axis to correspond for CG drawing
    if(self.attributes[@"transform"]) {
        pathTransform = CGAffineTransformScale(pathTransform, 1, -1);
    }
    
	[self.drawingLayer.sublayers makeObjectsPerformSelector:@selector(removeFromSuperlayer)];
	self.shapePath = [UIBezierPath bezierPath];
		
	for(NSDictionary *element in self.elements) {
        
		if(![element isKindOfClass:[NSDictionary class]])
			continue;
		
		UIBezierPath *path;
		
		NSString *shapeKey = [[element allKeys] objectAtIndex:0];
		QuickSVGElementType type = [self elementTypeForElement:element];
		
		if([[element[shapeKey] allKeys] containsObject:@"display"] && [element[shapeKey][@"display"] isEqualToString:@"none"])
			continue;

		CAShapeLayer *shapeLayer = [CAShapeLayer layer];
		
		switch (type) {
			case QuickSVGElementTypeBasicShape:
				path = [self addBasicShape:shapeKey withAttributes:element[shapeKey]];
				break;
			case QuickSVGElementTypePath:
				path = [self addPath:shapeKey withAttributes:element[shapeKey]];
				break;
			case QuickSVGElementTypeText:
            {
				CATextLayer *textLayer = [self addTextWithAttributes:element[shapeKey]];
				[_drawingLayer addSublayer:textLayer];
			}
				break;
			case QuickSVGElementTypeUnknown:
			default:
                continue;
				break;
		}
		
		if(path) {
            [path applyTransform:pathTransform];
			NSMutableDictionary *styles = [NSMutableDictionary dictionaryWithDictionary:element[shapeKey]];
			[styles addEntriesFromDictionary:_attributes];
            
			shapeLayer.path = path.CGPath;
			[self applyStyleAttributes:styles toShapeLayer:shapeLayer];
        
			[_drawingLayer addSublayer:shapeLayer];
			[_shapePath appendPath:path];
            [_shapeLayers addObject:shapeLayer];
		}
	}
}

- (void) setShapeLayers:(NSMutableArray *)shapeLayers
{
    _shapeLayers = shapeLayers;
    
    for(CAShapeLayer *layer in shapeLayers) {
        [_drawingLayer addSublayer:layer];
    }
}

- (QuickSVGElementType) elementTypeForElement:(NSDictionary *) element
{
	NSString *key = [[element allKeys] objectAtIndex:0];

	if([kAcceptableBasicShapeTypes containsObject:key]) {
		return QuickSVGElementTypeBasicShape;
	}
	else if([kAcceptablePathTypes containsObject:key]) {
		return QuickSVGElementTypePath;
	}
	else if([key isEqualToString:@"text"]) {
		return QuickSVGElementTypeText;
	}
	else {
		return QuickSVGElementTypeUnknown;
	}
}

- (CATextLayer *) addTextWithAttributes:(NSDictionary *) attributes
{
	CATextLayer *textLayer = [CATextLayer layer];
	textLayer.string = attributes[@"text"];
	textLayer.fontSize = [attributes[@"font-size"] floatValue];
	textLayer.contentsScale = [[UIScreen mainScreen] scale];
	
	UIFont *font = [UIFont fontWithName:attributes[@"font-family"] size:[attributes[@"font-size"] floatValue]];
	
	if(font == nil) {
		font = [UIFont systemFontOfSize:[attributes[@"font-size"] floatValue]];
	}
		
	CGSize size = [attributes[@"text"] sizeWithFont:font];
	textLayer.bounds = CGRectMake(0,0, size.width, size.height);
	
	CGFontRef fontRef = CGFontCreateWithFontName((__bridge CFStringRef)[font fontName]);
	[textLayer setFont:fontRef];
	CFRelease(fontRef);
	
	if([[attributes allKeys] containsObject:@"fill"]) {
		UIColor *color = [UIColor colorWithHexString:[attributes[@"fill"] substringFromIndex:1] withAlpha:1];
		textLayer.foregroundColor = color.CGColor;
	} else {
        textLayer.foregroundColor = [UIColor blackColor].CGColor;
    }
    
    textLayer.affineTransform = makeTransformFromSVGMatrix(attributes[@"transform"]);

	return textLayer;
}

- (UIBezierPath *) addPath:(NSString *) pathType withAttributes:(NSDictionary *) attributes
{
	if([pathType isEqualToString:@"path"]) {
		return [self drawPathWithAttributes:attributes];
	}
	else if([pathType isEqualToString:@"line"]) {
		return [self drawLineWithAttributes:attributes];
	}
	else if([pathType isEqualToString:@"polyline"]) {
		return [self drawPolylineWithAttributes:attributes];
	}
	else if([pathType isEqualToString:@"polygon"]) {
		return [self drawPolygonWithAttributes:attributes];
	}
	
	return nil;
}

- (UIBezierPath *) addBasicShape:(NSString *) shapeType withAttributes:(NSDictionary *) attributes
{
	if([shapeType isEqualToString:@"rect"]) {
		return [self drawRectWithAttributes:attributes];
	}
	else if([shapeType isEqualToString:@"circle"]) {
		return [self drawCircleWithAttributes:attributes];
	}
	else if([shapeType isEqualToString:@"ellipse"]) {
		return [self drawEllipseWithAttributes:attributes];
	}
	else {
//		if (DEBUG) {
			NSLog(@"**** Invalid basic shape: %@", shapeType);
//		}
	}
	
	return nil;
}

#pragma mark -
#pragma mark Shape Drawing

- (UIBezierPath *) drawRectWithAttributes:(NSDictionary *) attributes
{
	CGRect frame = CGRectMake([attributes[@"x"] floatValue], [attributes[@"y"] floatValue], [attributes[@"width"] floatValue], [attributes[@"height"] floatValue]);
	
	UIBezierPath *rect = [UIBezierPath bezierPathWithRect:frame];
	
	return rect;
}

- (UIBezierPath *) drawCircleWithAttributes:(NSDictionary *) attributes
{
	CGPoint center = CGPointMake([attributes[@"cx"] floatValue], [attributes[@"cy"] floatValue]);
	CGSize radii = CGSizeMake([attributes[@"r"] floatValue], [attributes[@"r"] floatValue]);
	
	CGRect frame = CGRectMake(center.x - radii.width / 2, center.y - radii.height / 2, radii.width, radii.height);
	
	UIBezierPath *circle = [UIBezierPath bezierPathWithOvalInRect:frame];
	
	return circle;
}

- (UIBezierPath *) drawEllipseWithAttributes:(NSDictionary *) attributes
{
	CGPoint center = CGPointMake([attributes[@"cx"] floatValue], [attributes[@"cy"] floatValue]);
	CGSize radii = CGSizeMake([attributes[@"rx"] floatValue], [attributes[@"ry"] floatValue]);
	
	CGRect frame = CGRectMake(center.x - radii.width / 2, center.y - radii.height / 2, radii.width, radii.height);
	
	UIBezierPath *ellipse = [UIBezierPath bezierPathWithOvalInRect:frame];
	
	return ellipse;
}

- (UIBezierPath *) drawPathWithAttributes:(NSDictionary *) attributes
{
	self.bezierPathBeingDrawn = [UIBezierPath bezierPath];
	
	NSString *pathData = [attributes[@"d"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    pathData = [pathData stringByReplacingOccurrencesOfString:@" " withString:@","];
	
	[self parsePath:pathData];
	
	[self reset];
	
	NSArray *tokens = [NSArray arrayWithArray:_tokens];
	
	for (Token *thisToken in tokens) {
		unichar command = [thisToken command];
		switch (command) {
			case 'M':
			case 'm':
				[self appendSVGMCommand:thisToken];
				break;
			case 'L':
			case 'l':
			case 'H':
			case 'h':
			case 'V':
			case 'v':
				[self appendSVGLCommand:thisToken];
				break;
			case 'C':
			case 'c':
				[self appendSVGCCommand:thisToken];
				break;
			case 'S':
			case 's':
				[self appendSVGSCommand:thisToken];
				break;
			case 'Z':
			case 'z':
				[_bezierPathBeingDrawn closePath];
				break;
			default:
				NSLog(@"*** Error: Cannot process command : '%c'", command);
				break;
		}
	}
	
	return _bezierPathBeingDrawn;
}

- (UIBezierPath *) drawLineWithAttributes:(NSDictionary *) attributes
{
	UIBezierPath *line = [UIBezierPath bezierPath];
	CGPoint startingPoint = CGPointMake([attributes[@"x1"] floatValue], [attributes[@"y1"] floatValue]);
	CGPoint endingPoint = CGPointMake([attributes[@"x2"] floatValue], [attributes[@"y2"] floatValue]);
	
	[line moveToPoint:startingPoint];
	[line addLineToPoint:endingPoint];
	
	return line;
}

- (UIBezierPath *) drawPolylineWithAttributes:(NSDictionary *) attributes
{
	return [self drawPolyElementWithAttributes:attributes isPolygon:NO];
}

- (UIBezierPath *) drawPolygonWithAttributes:(NSDictionary *) attributes
{
	return [self drawPolyElementWithAttributes:attributes isPolygon:YES];
}

- (UIBezierPath *) drawPolyElementWithAttributes:(NSDictionary *) attributes isPolygon:(BOOL) isPolygon
{	
	NSArray *points = [self arrayFromPointsAttribute:attributes[@"points"]];
	UIBezierPath *polygon = [UIBezierPath bezierPath];
	
	CGPoint firstPoint = CGPointFromString(points[0]);
	[polygon moveToPoint:firstPoint];
	
	for(int x = 0; x < [points count]; x++) {		
		if(x + 1 < [points count]) {
			CGPoint endPoint = CGPointFromString(points[x + 1]);
			[polygon addLineToPoint:endPoint];
		}
	}
	
	if(isPolygon) {
		[polygon addLineToPoint:firstPoint];
		[polygon closePath];
	}
	
	return polygon;
}

#pragma mark -
#pragma mark Path Drawing

- (NSMutableArray *)parsePath:(NSString *)attr
{
	NSMutableArray *stringTokens = [NSMutableArray arrayWithCapacity: maxPathComplexity];
	
	NSInteger index = 0;
	while (index < [attr length]) {
		
		NSMutableString *stringToken = [[NSMutableString alloc] initWithCapacity:maxTokenLength];
		[stringToken setString:@""];
		
		unichar	charAtIndex = [attr characterAtIndex:index];
		
		if (charAtIndex != ',') {
			[stringToken appendString:[NSString stringWithFormat:@"%c", charAtIndex]];
		}
		
		if (![_commandSet characterIsMember:charAtIndex] && charAtIndex != ',') {
			
			while ( (++index < [attr length]) && ![_separatorSet characterIsMember:(charAtIndex = [attr characterAtIndex:index])] ) {
				
				[stringToken appendString:[NSString stringWithFormat:@"%c", charAtIndex]];
			}
		} else {
			index++;
		}
		
		if ([stringToken length]) {
			[stringTokens addObject:stringToken];
		}
	}
	
	if ([stringTokens count] == 0) {
		
		NSLog(@"*** Error: Path string is empty of tokens");
		return nil;
	}
	
	// turn the stringTokens array into Tokens, checking validity of tokens as we go
	_tokens = [[NSMutableArray alloc] initWithCapacity:maxPathComplexity];
	index = 0;
	NSString *stringToken = [stringTokens objectAtIndex:index];
	unichar command = [stringToken characterAtIndex:0];
	while (index < [stringTokens count]) {
		if (![_commandSet characterIsMember:command]) {
			NSLog(@"*** Error: Path string parse error: found float where expecting command at token %d in path %s.",
				  index, [attr cStringUsingEncoding:NSUTF8StringEncoding]);
			return nil;
		}
		Token *token = [[Token alloc] initWithCommand:command];
		
		// There can be any number of floats after a command. Suck them in until the next command.
		while ((++index < [stringTokens count]) && ![_commandSet characterIsMember:
													 (command = [(stringToken = [stringTokens objectAtIndex:index]) characterAtIndex:0])]) {
			
			NSScanner *floatScanner = [NSScanner scannerWithString:stringToken];
			float value;
			if (![floatScanner scanFloat:&value]) {
				NSLog(@"*** Error: Path string parse error: expected float or command at token %d (but found %s) in path %s.",
					  index, [stringToken cStringUsingEncoding:NSUTF8StringEncoding], [attr cStringUsingEncoding:NSUTF8StringEncoding]);
				return nil;
			}
			// Maintain scale.
			_pathScale = (abs(value) > _pathScale) ? abs(value) : _pathScale;
			[token addValue:value];
		}
		
		// now we've reached a command or the end of the stringTokens array
		[_tokens addObject:token];
	}
	//[stringTokens release];
	return _tokens;
}

- (void)reset
{
	_lastPoint = CGPointMake(0, 0);
	_validLastControlPoint = NO;
}

- (void)appendSVGMCommand:(Token *)token
{
	_validLastControlPoint = NO;
	NSInteger index = 0;
	BOOL first = YES;
	while (index < [token valence]) {
		CGFloat x = [token parameter:index] + ([token command] == 'm' ? _lastPoint.x : 0);
		if (++index == [token valence]) {
			NSLog(@"*** Error: Invalid parameter count in M style token");
			return;
		}
		CGFloat y = [token parameter:index] + ([token command] == 'm' ? _lastPoint.y : 0);
		_lastPoint = CGPointMake(x, y);
		if (first) {
			[_bezierPathBeingDrawn moveToPoint:_lastPoint];
			first = NO;
		} else {
			[_bezierPathBeingDrawn addLineToPoint:_lastPoint];
		}
		index++;
	}
}

- (void)appendSVGLCommand:(Token *)token
{
	_validLastControlPoint = NO;
	NSInteger index = 0;
	while (index < [token valence]) {
		CGFloat x = 0;
		CGFloat y = 0;
		switch ( [token command] ) {
			case 'l':
				x = _lastPoint.x;
				y = _lastPoint.y;
			case 'L':
				x += [token parameter:index];
				if (++index == [token valence]) {
					NSLog(@"*** Error: Invalid parameter count in L style token");
					return;
				}
				y += [token parameter:index];
				break;
			case 'h' :
				x = _lastPoint.x;
			case 'H' :
				x += [token parameter:index];
				y = _lastPoint.y;
				break;
			case 'v' :
				y = _lastPoint.y;
			case 'V' :
				y += [token parameter:index];
				x = _lastPoint.x;
				break;
			default:
				NSLog(@"*** Error: Unrecognised L style command.");
				return;
		}
		_lastPoint = CGPointMake(x, y);
		
		[_bezierPathBeingDrawn addLineToPoint:_lastPoint];
		index++;
	}
}

- (void)appendSVGCCommand:(Token *)token
{
	NSInteger index = 0;
	while ((index + 5) < [token valence]) {  // we must have 6 floats here (x1, y1, x2, y2, x, y).
		CGFloat x1 = [token parameter:index++] + ([token command] == 'c' ? _lastPoint.x : 0);
		CGFloat y1 = [token parameter:index++] + ([token command] == 'c' ? _lastPoint.y : 0);
		CGFloat x2 = [token parameter:index++] + ([token command] == 'c' ? _lastPoint.x : 0);
		CGFloat y2 = [token parameter:index++] + ([token command] == 'c' ? _lastPoint.y : 0);
		CGFloat x  = [token parameter:index++] + ([token command] == 'c' ? _lastPoint.x : 0);
		CGFloat y  = [token parameter:index++] + ([token command] == 'c' ? _lastPoint.y : 0);
		_lastPoint = CGPointMake(x, y);
		
		[_bezierPathBeingDrawn addCurveToPoint:_lastPoint
								 controlPoint1:CGPointMake(x1,y1)
								 controlPoint2:CGPointMake(x2, y2)];
		
		_lastControlPoint = CGPointMake(x2, y2);
		_validLastControlPoint = YES;
	}
	
	if (index == 0) {
		NSLog(@"*** Error: Insufficient parameters for C command");
	}
}

- (void)appendSVGSCommand:(Token *)token
{
	if (!_validLastControlPoint) {
		NSLog(@"*** Error: Invalid last control point in S command");
	}
	
	NSInteger index = 0;
	while ((index + 3) < [token valence]) {  // we must have 4 floats here (x2, y2, x, y).
		CGFloat x1 = _lastPoint.x + (_lastPoint.x - _lastControlPoint.x); // + ([token command] == 's' ? lastPoint.x : 0);
		CGFloat y1 = _lastPoint.y + (_lastPoint.y - _lastControlPoint.y); // + ([token command] == 's' ? lastPoint.y : 0);
		CGFloat x2 = [token parameter:index++] + ([token command] == 's' ? _lastPoint.x : 0);
		CGFloat y2 = [token parameter:index++] + ([token command] == 's' ? _lastPoint.y : 0);
		CGFloat x  = [token parameter:index++] + ([token command] == 's' ? _lastPoint.x : 0);
		CGFloat y  = [token parameter:index++] + ([token command] == 's' ? _lastPoint.y : 0);
		_lastPoint = CGPointMake(x, y);
		
		[_bezierPathBeingDrawn addCurveToPoint:_lastPoint
								 controlPoint1:CGPointMake(x1,y1)
								 controlPoint2:CGPointMake(x2, y2)];
		
		_lastControlPoint = CGPointMake(x2, y2);
		_validLastControlPoint = YES;
	}
	
	if (index == 0) {
		NSLog(@"*** Error: Insufficient parameters for S command");
	}
}

- (NSArray *) arrayFromPointsAttribute:(NSString *) points
{
    NSCharacterSet *whitespaces = [NSCharacterSet whitespaceCharacterSet];
	NSPredicate *noEmptyStrings = [NSPredicate predicateWithFormat:@"SELF != ''"];
	
	NSArray *parts = [points componentsSeparatedByCharactersInSet:whitespaces];
	NSArray *filteredArray = [parts filteredArrayUsingPredicate:noEmptyStrings];
	NSString *parsed = [filteredArray componentsJoinedByString:@","];
	
	NSArray *commaPieces = [parsed componentsSeparatedByString:@","];
	
	NSMutableArray *pointsArray = [NSMutableArray arrayWithCapacity:[commaPieces count] / 2];
	
	for(int x = 0; x < [commaPieces count]; x++) {
		if(x % 2 == 0) {
			CGPoint point = CGPointMake([commaPieces[x] floatValue], [commaPieces[x + 1] floatValue]);
			[pointsArray addObject:NSStringFromCGPoint(point)];
		}
	}	
	return pointsArray;
}

- (void) encodeWithCoder:(NSCoder *)aCoder
{
    [super encodeWithCoder:aCoder];
    
	[aCoder encodeObject:_shapeLayers forKey:@"shapeLayers"];
    [aCoder encodeObject:_shapePath forKey:@"shapePath"];
	[aCoder encodeObject:self.attributes forKey:@"attributes"];
}

- (id) initWithCoder:(NSCoder *)aDecoder
{    
	self = [super initWithCoder:aDecoder];
	
	if(self) {
        [self setup];
        
        self.attributes = [aDecoder decodeObjectForKey:@"attributes"];
        self.shapeLayers = [aDecoder decodeObjectForKey:@"shapeLayers"];
        self.shapePath = [aDecoder decodeObjectForKey:@"shapePath"];
        
        for(CAShapeLayer *layer in _shapeLayers) {
            [self applyStyleAttributes:_attributes toShapeLayer:layer];
        }
	}
	
	return self;
}

@end
