//
//  PBImageStorage.m
//
//  Image storage with memory cache and thumbnails support.
//
//  Created by Andrej Mihajlov on 8/28/13.
//  Copyright (c) 2013-2014 Andrej Mihajlov. All rights reserved.
//

#import "PBImageStorage.h"

//
// Debug macro
//
#ifndef PBIMAGESTORAGE_DEBUG
	#define PBIMAGESTORAGE_DEBUG 0
#endif

#if PBIMAGESTORAGE_DEBUG
	#ifndef NSLogSuccess
		#define NSLogSuccess NSLog
	#endif
	#ifndef NSLogWarn
		#define NSLogWarn NSLog
	#endif
	#ifndef NSLogInfo
		#define NSLogInfo NSLog
	#endif
	#ifndef NSLogError
		#define NSLogError NSLog
	#endif
#else
	#ifdef NSLogSuccess
		#undef NSLogSuccess
	#endif
	#ifdef NSLogWarn
		#undef NSLogWarn
	#endif
	#ifdef NSLogInfo
		#undef NSLogInfo
	#endif
	#ifdef NSLogError
		#undef NSLogError
	#endif

	#define NSLogSuccess(...)
	#define NSLogWarn(...)
	#define NSLogInfo(...)
	#define NSLogError(...)
#endif

NSString* const kPBImageStorageIOException = @"kPBImageStorageIOException";
static void* kPBImageStorageOperationCountContext = &kPBImageStorageOperationCountContext;

@implementation PBImageStorage {
	NSCache* _memoryCache;
	NSFileManager* _fileManager;
	NSOperationQueue* _ioQueue;
	NSMutableDictionary* _indexStore;
	BOOL _checkStoragePathExists;
	BOOL _indexHasBeenLoaded;
	BOOL _indexStoreIsDirty;
}

- (id)init {
	return [self initWithNamespace:@"default"];
}

- (id)initWithNamespace:(NSString*)name {
	NSString* cachesDirectory = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject];
	NSString* basePath = [cachesDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"ru.codeispoetry.%@", self.class]];
	return [self initWithNamespace:name basePath:basePath];
}

- (id)initWithNamespace:(NSString*)name basePath:(NSString*)basePath {
	NSParameterAssert(name != nil && basePath != nil);
	
	if(self = [super init]) {
		NSInteger maxConcurrentOperations = NSProcessInfo.processInfo.processorCount * 2;
		
		_namespaceName = name;
		_memoryCache = [NSCache new];
		_fileManager = [NSFileManager new];
		_ioQueue = [NSOperationQueue new];
		_indexStore = [NSMutableDictionary new];
		_storagePath = [basePath stringByAppendingPathComponent:name];
		_checkStoragePathExists = YES;
		
		[_ioQueue setMaxConcurrentOperationCount:maxConcurrentOperations];
		[_ioQueue setSuspended:NO];
		
		// add observer for operationCount
		[_ioQueue addObserver:self forKeyPath:@"operationCount" options:NSKeyValueObservingOptionNew context:kPBImageStorageOperationCountContext];
		
#if TARGET_OS_IPHONE
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveMemoryWarningNotification:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
#endif
	}
	return self;
}

- (void)dealloc {
#if TARGET_OS_IPHONE
	[[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
#endif
	
	// remove observer for operationCount
	[_ioQueue removeObserver:self forKeyPath:@"operationCount" context:kPBImageStorageOperationCountContext];
	
	NSLogInfo(@"%s", __PRETTY_FUNCTION__);
}

#if TARGET_OS_IPHONE
// Clear memory cache when memory warning received
- (void)didReceiveMemoryWarningNotification:(NSNotification*)notification {
	[self clearMemory];
}
#endif

#pragma mark - indexStore manipulation methods

- (void)_indexStoreMarkDirty {
	@synchronized(_indexStore) {
		_indexStoreIsDirty = YES;
	}
}

- (void)_indexStoreSave {
	NSError* error;
	NSData* data;
	NSString* indexStoreFileName = [self _indexStoreFileName];
	
	NSLogWarn(@"%s", __PRETTY_FUNCTION__);
	
	@synchronized(_indexStore) {
		data = [NSJSONSerialization dataWithJSONObject:_indexStore options:0 error:&error];
		_indexStoreIsDirty = NO;
	}
		
	if(data != nil) {
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
			// write indexStore copy to file
			BOOL success = [data writeToFile:indexStoreFileName atomically:YES];
			
			if(success) {
				NSLogSuccess(@"Saved storage index to file %@", [indexStoreFileName stringByAbbreviatingWithTildeInPath]);
			} else {
				NSLogError(@"Failed to save storage index to file %@", [indexStoreFileName stringByAbbreviatingWithTildeInPath]);
			}
		});
	} else {
		NSLogError(@"Cannot serialize indexStore. Reason: %@", error.localizedDescription);
	}
}

- (void)_indexStoreSaveIfNeeded {
	@synchronized(_indexStore) {
		NSLogSuccess(@"%s", __PRETTY_FUNCTION__);
		
		if(_indexStoreIsDirty) {
			[self _indexStoreSave];
		}
	}
}

- (void)_indexStoreLoad {
	NSData* data = [NSData dataWithContentsOfFile:[self _indexStoreFileName]];
	NSMutableDictionary* dictionary = nil;
	NSError* error = nil;
	
	if(data != nil) {
		dictionary = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&error];
		
		if(error != nil) {
			NSLogError(@"Cannot deserialize indexStore. Reason: %@", error.localizedDescription);
		}
		
		if([dictionary isKindOfClass:NSDictionary.class]) {
			@synchronized(_indexStore) {
				[_indexStore setDictionary:dictionary];
			}
		}

		if(dictionary != nil) {
			NSLogSuccess(@"Read storage index from file %@", [[self _indexStoreFileName] stringByAbbreviatingWithTildeInPath]);
		} else {
			NSLogError(@"Failed to read storage index from file %@", [[self _indexStoreFileName] stringByAbbreviatingWithTildeInPath]);
		}
	}
}

- (void)_indexStoreLoadIfNeeded {
	@synchronized(_indexStore) {
		if(!_indexHasBeenLoaded) {
			[self _indexStoreLoad];
			_indexHasBeenLoaded = YES;
		}
	}
}

- (BOOL)_indexStoreHasKey:(NSString*)key {
	@synchronized(_indexStore) {
		[self _indexStoreLoadIfNeeded];
		return _indexStore[key] != nil;
	}
}

- (BOOL)_indexStoreHasDependentKey:(NSString*)dependentKey forKey:(NSString*)key {
	@synchronized(_indexStore) {
		[self _indexStoreLoadIfNeeded];
		return _indexStore[key] != nil && [_indexStore[key] containsObject:dependentKey];
	}
}

- (void)_indexStoreAddKey:(NSString*)key {
	@synchronized(_indexStore) {
		[self _indexStoreLoadIfNeeded];
		
		_indexStore[key] = [NSMutableArray new];
		
		[self _indexStoreMarkDirty];
	}
}

- (void)_indexStoreAddDependentKey:(NSString*)dependentKey forKey:(NSString*)key {
	@synchronized(_indexStore) {
		[self _indexStoreLoadIfNeeded];
		
		if(_indexStore[key] != nil && ![_indexStore[key] containsObject:dependentKey]) {
			[_indexStore[key] addObject:dependentKey];
			[self _indexStoreMarkDirty];
		}
	}
}

- (void)_indexStoreRemoveKey:(NSString*)key {
	@synchronized(_indexStore) {
		[self _indexStoreLoadIfNeeded];
		
		[_indexStore removeObjectForKey:key];
		
		[self _indexStoreMarkDirty];
	}
}

- (void)_removeDependentImagesForKey:(NSString*)key {
	@synchronized(_indexStore) {
		if(_indexStore[key] != nil) {
			for(NSString* subKey in _indexStore[key]) {
				[self removeImageForKey:subKey];
			}
		}
	}
}

- (void)_indexStoreClear {
	@synchronized(_indexStore) {
		// remove all objects from index store
		[_indexStore removeAllObjects];
		
		// remove index store from disk
		[_fileManager removeItemAtPath:[self _indexStoreFileName] error:nil];
	}
}

- (NSString*)_indexStoreFileName {
	return [self.storagePath stringByAppendingPathComponent:@"_indexStore.json"];
}

#pragma mark - Key-value observing
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
	if(context == kPBImageStorageOperationCountContext) {
		NSUInteger operationCount = [change[NSKeyValueChangeNewKey] unsignedIntegerValue];
		NSLogInfo(@"operationCount = %d", operationCount);
		
		if(operationCount == 0) {
			[self _indexStoreSaveIfNeeded];
		}
	}
}


#pragma mark - File locking helpers

- (void)_lockFileHandle:(NSFileHandle*)handle {
	struct flock lock;
	
	lock.l_start = 0;
	lock.l_len = 0;
	lock.l_pid = getpid();
	lock.l_type = F_WRLCK;
	lock.l_whence = SEEK_SET;
	
	if(fcntl(handle.fileDescriptor, F_SETLKW, &lock) == -1) {
		NSLogError(@"%s error: %s", __PRETTY_FUNCTION__, strerror(errno));
	}
}

- (void)_unlockFileHandle:(NSFileHandle*)handle {
	struct flock lock;
	
	lock.l_start = 0;
	lock.l_len = 0;
	lock.l_pid = getpid();
	lock.l_type = F_UNLCK;
	lock.l_whence = SEEK_SET;
	
	if(fcntl(handle.fileDescriptor, F_SETLK, &lock) == -1) {
		NSLogError(@"%s error: %s", __PRETTY_FUNCTION__, strerror(errno));
	}
}

#pragma mark - imageStorage methods

- (void)setImage:(UIImage*)image forKey:(NSString *)key diskOnly:(BOOL)diskOnly {
	[self _setImage:image forKey:key diskOnly:diskOnly completion:nil waitUntilFinished:YES];
}

- (void)setImage:(UIImage*)image forKey:(NSString*)key diskOnly:(BOOL)diskOnly completion:(void (^)(void))completion {
	[self _setImage:image forKey:key diskOnly:diskOnly completion:completion waitUntilFinished:NO];
}

- (void)_setImage:(UIImage*)image forKey:(NSString*)key diskOnly:(BOOL)diskOnly completion:(void (^)(void))completion waitUntilFinished:(BOOL)waitUntilFinished {
	[self _setImage:image forKey:key diskOnly:diskOnly completion:completion dependentOperations:nil waitUntilFinished:waitUntilFinished];
}

- (void)_setImage:(UIImage*)image forKey:(NSString*)key diskOnly:(BOOL)diskOnly completion:(void (^)(void))completion dependentOperations:(NSArray*)dependentOperations waitUntilFinished:(BOOL)waitUntilFinished {
	NSParameterAssert(key != nil && image != nil);
	
	// save image to memory
	if(!diskOnly) {
		[_memoryCache setObject:image forKey:key];
	}
	
	// dump image to disk on background queue
	NSBlockOperation* mainOperation = [self _operationWithBlock:^(NSBlockOperation *currentOperation) {
		if(currentOperation.isCancelled) {
			// remove object from cache if operation was cancelled
			if(!diskOnly) {
				[_memoryCache removeObjectForKey:key];
			}
			
			if(completion != nil) {
				dispatch_async(dispatch_get_main_queue(), completion);
			}
			
			return;
		}
		
		[self _setImage:image forKey:key];
		
		if(completion != nil) {
			dispatch_async(dispatch_get_main_queue(), completion);
		}
	}];
	
	// create operations array
	NSMutableArray* operations = [NSMutableArray arrayWithObject:mainOperation];
	
	// add dependent operations
	if(dependentOperations != nil) {
		for(NSOperation* dependentOperation in dependentOperations) {
			[dependentOperation addDependency:mainOperation];
			[operations addObject:dependentOperation];
		}
	}
	
	[_ioQueue addOperations:operations waitUntilFinished:waitUntilFinished];
}

- (void)copyImageFromKey:(NSString*)fromKey toKey:(NSString*)toKey diskOnly:(BOOL)diskOnly {
	UIImage* image = [self _imageForKey:fromKey];
	if(image != nil) {
		[self setImage:image forKey:toKey diskOnly:diskOnly];
	}
}

- (void)copyImageFromKey:(NSString*)fromKey toKey:(NSString*)toKey diskOnly:(BOOL)diskOnly completion:(void(^)(void))completion {
	// dump image to disk on background queue
	NSBlockOperation* operation = [self _operationWithBlock:^(NSBlockOperation *currentOperation) {
		if(!currentOperation.isCancelled) {
			[self copyImageFromKey:fromKey toKey:toKey diskOnly:diskOnly];
		}
		
		if(completion != nil) {
			dispatch_async(dispatch_get_main_queue(), completion);
		}
	}];
	
	[_ioQueue addOperation:operation];
}

- (void)imageForKey:(NSString*)key completion:(void(^)(UIImage* image))completion {
	NSBlockOperation* operation = [self _operationWithBlock:^(NSBlockOperation *currentOperation) {
		UIImage* image = nil;
		
		if(!currentOperation.isCancelled) {
			image = [self _imageForKey:key];
		}
		
		if(completion != nil) {
			dispatch_async(dispatch_get_main_queue(), ^{
				completion(image);
			});
		}
	}];
	
	[_ioQueue addOperation:operation];
}

//
// Scales original image at key, puts it in storage and returns in completion handler
// @TODO: group multiple operations in a single batch
//
- (void)imageForKey:(NSString*)key scaledToFit:(CGSize)size completion:(void(^)(BOOL cached, UIImage* image))completion {
	NSString* scaledImageKey = [self _keyForScaledImageWithKey:key size:size];
	
	NSLogSuccess(@"%s", __PRETTY_FUNCTION__);
	
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
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
				@autoreleasepool {
					__weak typeof(self) weakSelf = self;
					
					// scale image
					UIImage* scaledImage = [self _scaleImage:originalImage toSize:size];
					
					// add dependency to index store
					NSBlockOperation* dependentOperation = [self _operationWithBlock:^(NSBlockOperation *currentOperation) {
						__strong typeof(self) strongSelf = weakSelf;
						if(strongSelf == nil) {
							return;
						}
						
						if(currentOperation.isCancelled) {
							return;
						}
						
						// add dependent key to index store
						[strongSelf _indexStoreAddDependentKey:scaledImageKey forKey:key];
						
						if(completion != nil) {
							dispatch_async(dispatch_get_main_queue(), ^{
								completion(NO, scaledImage);
							});
						}
					}];
					
					// save scaled image on disk and in memory
					[self _setImage:scaledImage forKey:scaledImageKey diskOnly:NO completion:nil dependentOperations:@[ dependentOperation ] waitUntilFinished:NO];
				}
			});
		}];
	}];
}

- (UIImage*)imageFromMemoryForKey:(NSString*)key {
	NSParameterAssert(key != nil);
	
	return [_memoryCache objectForKey:key];
}

- (UIImage*)imageFromMemoryForKey:(NSString*)key scaledToFit:(CGSize)size {
	NSString* scaledImageKey = [self _keyForScaledImageWithKey:key size:size];
	
	return [self imageFromMemoryForKey:scaledImageKey];
}

- (void)removeImageForKey:(NSString*)key {
	NSParameterAssert(key != nil);
	
	NSBlockOperation *operation = [self _operationWithBlock:^(NSBlockOperation *currentOperation) {
		if(currentOperation.isCancelled) {
			return;
		}
		
		[_fileManager removeItemAtPath:[self _pathForKey:key] error:nil];
		
		// remove dependent images first if there were any
		[self _removeDependentImagesForKey:key];
		
		// remove key from index store
		[self _indexStoreRemoveKey:key];
	}];
	
	[_memoryCache removeObjectForKey:key];
	[_ioQueue addOperation:operation];
}

- (void)clearMemory {
	[_ioQueue setSuspended:YES];
	[_memoryCache removeAllObjects];
	[_ioQueue setSuspended:NO];
}

- (void)clear {
	[_ioQueue cancelAllOperations];
	[_ioQueue setSuspended:YES];
	
	[self _indexStoreClear];
	
	[_fileManager removeItemAtPath:_storagePath error:nil];
	_checkStoragePathExists = YES;
	
	[self clearMemory];
	
	[_ioQueue setSuspended:NO];
}

#pragma mark - Internal methods

- (NSBlockOperation*)_operationWithBlock:(void(^)(NSBlockOperation* currentOperation))block {
	NSBlockOperation *operation = [NSBlockOperation new];
	__weak NSBlockOperation *weakOperation = operation;
	
	[operation addExecutionBlock:^{
		@autoreleasepool {
			block(weakOperation);
		}
	}];
	
	return operation;
}

- (NSString*)_pathForKey:(NSString*)key {
	NSString* scale = UIScreen.mainScreen.scale == 2 ? @"@2x" : @"";
	return [_storagePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@%@.jpg", key, scale]];
}

- (void)_setImage:(UIImage*)image forKey:(NSString*)key {
	NSParameterAssert(key != nil && image != nil);
	
	NSData* data = UIImageJPEGRepresentation(image, 1.0f);
	NSString* path = [self _pathForKey:key];
	NSError* error;
	
	// create cache directory if needed
	@synchronized(self) {
		if(_checkStoragePathExists) {
			BOOL isDir;
			if(![_fileManager fileExistsAtPath:_storagePath isDirectory:&isDir]) {
				if(![_fileManager createDirectoryAtPath:_storagePath withIntermediateDirectories:YES attributes:nil error:&error]) {
					[[NSException exceptionWithName:kPBImageStorageIOException reason:error.localizedDescription userInfo:error.userInfo] raise];
				}
			}
			
			_checkStoragePathExists = NO;
		}
	}
	
	// make sure file exists
	[_fileManager createFileAtPath:path contents:nil attributes:nil];
	
	// open handle
	NSFileHandle* handle = [NSFileHandle fileHandleForUpdatingAtPath:path];
	
	// check if handle is valid
	if(handle == nil) {
		[[NSException exceptionWithName:kPBImageStorageIOException reason:[NSString stringWithFormat:@"Invalid file handle: %@", path] userInfo:nil] raise];
	}
	
	// lock file
	[self _lockFileHandle:handle];
	
	// write data
	[handle writeData:data];
	
	// unlock file
	[self _unlockFileHandle:handle];
	
	// remove dependent images first if there were any
	[self _removeDependentImagesForKey:key];
	
	// add key to index store
	[self _indexStoreAddKey:key];
}

- (UIImage*)_imageForKey:(NSString*)key {
	NSParameterAssert(key != nil);
	
	// check if image is in store
	if(![self _indexStoreHasKey:key]) {
		return nil;
	}
	
	UIImage* image = [_memoryCache objectForKey:key];
	
	if(image == nil) {
		NSFileHandle* handle = [NSFileHandle fileHandleForUpdatingAtPath:[self _pathForKey:key]];
		
		if(handle != nil) {
			// lock file
			[self _lockFileHandle:handle];
			
			// read image
			NSData* data = [handle readDataToEndOfFile];
			image = [UIImage imageWithData:data scale:UIScreen.mainScreen.scale];
			
			// unlock file
			[self _unlockFileHandle:handle];
		}
		
		if(image != nil) {
			[_memoryCache setObject:image forKey:key];
		}
	}
	
	return image;
}


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

@end

