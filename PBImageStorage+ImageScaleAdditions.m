//
//  PBImageStorage+ImageScaleAdditions.m
//
//  Created by pronebird on 10/11/13.
//  Copyright (c) 2013 pronebird. All rights reserved.
//

#import "PBImageStorage+ImageScaleAdditions.h"

@implementation PBImageStorage (ImageScaleAdditions)

//
// Scale image to fit in provided size
//
- (UIImage*)_scaleImage:(UIImage*)image toSize:(CGSize)size {
	CGFloat ratio = image.size.height / image.size.width;
	CGFloat scaleFactor;
	CGRect imageRect;
	UIImage* output;
	
	if(ratio > 0) {
		scaleFactor = size.height / image.size.height;
	} else {
		scaleFactor = size.width / image.size.width;
	}
	
	imageRect.size.width = image.size.width * scaleFactor;
	imageRect.size.height = image.size.height * scaleFactor;
	imageRect.origin.x = (size.width - imageRect.size.width) * 0.5f;
	imageRect.origin.y = (size.height - imageRect.size.height) * 0.5f;
	
	UIGraphicsBeginImageContextWithOptions(size, YES, 0.0f);
	
	[[UIColor whiteColor] set];
	UIRectFill(CGRectMake(0, 0, size.width, size.height));
	
	[image drawInRect:imageRect];
	
	output = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	
	return output;
}

//
// Creates a key for scaled image
//
- (NSString*)_keyForScaledImageWithKey:(NSString*)key size:(CGSize)size {
	return [NSString stringWithFormat:@"%@-%.0fx%.0f", key, size.width, size.height];
}

//
// Scales original image at key, puts it in storage and returns in completion handler
//
- (void)imageForKey:(NSString*)key scaledToFit:(CGSize)size completion:(void(^)(BOOL cached, UIImage* image))completion {
	NSString* cachedImageKey = [self _keyForScaledImageWithKey:key size:size];
	
	// get scaled image from memory
	__block UIImage* cachedImage = [self imageFromMemoryForKey:cachedImageKey];
	
	// if it's not there, try loading from disk
	if(cachedImage == nil) {
		NSString* scaledImageKey = [self _keyForScaledImageWithKey:key size:size];
		
		// query scaled image from disk
		[self imageForKey:scaledImageKey completion:^(UIImage *resizedImage) {
			
			if(resizedImage != nil) {
				if(completion != nil) {
					dispatch_async(dispatch_get_main_queue(), ^{
						completion(NO, resizedImage);
					});
				}
				return;
			}
			
			// query original image from disk
			[self imageForKey:key completion:^(UIImage *originalImage) {
				
				// if image lost or something really went wrong
				// bail out and return nil
				if(originalImage == nil) {
					if(completion != nil) {
						dispatch_async(dispatch_get_main_queue(), ^{
							completion(NO, nil);
						});
					}
					return;
				}
				
				// dispatch image scaling on some other queue
				// since completion handler is invoked on background ioQueue
				dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
					// scale image
					cachedImage = [self _scaleImage:originalImage toSize:size];
					
					// set image asynchronously
					[self setImage:cachedImage forKey:cachedImageKey diskOnly:NO completion:^{
						// call completion handler on main thread and pass scaled image there
						if(completion != nil) {
							dispatch_async(dispatch_get_main_queue(), ^{
								completion(NO, cachedImage);
							});
						}
					}];
				});
			}];
		}];
	} else {
		// call completion handler on main thread and pass cached image there
		if(completion != nil) {
			dispatch_async(dispatch_get_main_queue(), ^{
				completion(YES, cachedImage);
			});
		}
	}
}

@end
