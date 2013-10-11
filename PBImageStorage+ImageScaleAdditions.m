//
//  PBImageStorage+ImageScaleAdditions.m
//
//  Created by pronebird on 10/11/13.
//  Copyright (c) 2013 Andrej Mihajlov. All rights reserved.
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
	NSString* scaledImageKey = [self _keyForScaledImageWithKey:key size:size];
	
	// try getting scaled image from memory
	UIImage* memoryImage = [self imageFromMemoryForKey:scaledImageKey];
	
	// return if image is found in memory cache
	if(memoryImage != nil) {
		if(completion != nil) {
			// no guarantee that this method is called on main thread
			dispatch_async(dispatch_get_main_queue(), ^{
				completion(YES, memoryImage);
			});
		}
		return;
	}
	
	// if image is not in memory, try loading it from disk
	[self imageForKey:scaledImageKey completion:^(UIImage *diskImage) {
		
		// return image if it's found on disk
		if(diskImage != nil) {
			if(completion != nil) {
				completion(NO, diskImage);
			}
			return;
		}
		
		// retrieve original image to generate a scaled copy
		[self imageForKey:key completion:^(UIImage *originalImage) {
			
			// if original image lost or something really went wrong, return nil
			if(originalImage == nil) {
				if(completion != nil) {
					completion(NO, nil);
				}
				return;
			}
			
			// schedule scaling in background
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
				
				// scale image
				UIImage* scaledImage = [self _scaleImage:originalImage toSize:size];
				
				// save scaled image on disk and in memory
				[self setImage:scaledImage forKey:scaledImageKey diskOnly:NO completion:^{
					if(completion != nil) {
						completion(NO, scaledImage);
					}
				}];
			});
		}];
	}];
}

@end
