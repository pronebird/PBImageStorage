//
//  PBImageStorage+ImageScaleAdditions.h
//
//  Created by pronebird on 10/11/13.
//  Copyright (c) 2013 Andrej Mihajlov. All rights reserved.
//

#import "PBImageStorage.h"

@interface PBImageStorage (ImageScaleAdditions)

//
// Scales original image at key, puts it in storage and returns it in completion handler
// Completion handler is called on main thread.
//
- (void)imageForKey:(NSString*)key scaledToFit:(CGSize)size completion:(void(^)(BOOL cached, UIImage* image))completion;

@end
