//
//  PBImageStorage.m
//
//  Image storage that implements memory cache between app and disk.
//  This implementation allows to store tons of images on disk and keep
//  only specific subset in memory.
//
//  Images are lazy loaded in memory upon access and purged
//  from memory on memory warning or when app goes background.
//
//  Created by Andrej Mihajlov on 8/28/13.
//  Copyright (c) 2013 Andrej Mihajlov. All rights reserved.
//

#import "PBImageStorage.h"

@implementation PBImageStorage {
	NSCache* _cache;
	NSFileManager* _fileManager;
	NSOperationQueue* _ioQueue;
	BOOL _checkStoragePathExists;
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
		_cache = [NSCache new];
		_fileManager = [NSFileManager new];
		_ioQueue = [NSOperationQueue new];
		_storagePath = [basePath stringByAppendingPathComponent:name];
		_checkStoragePathExists = YES;
		
		[_ioQueue setMaxConcurrentOperationCount:maxConcurrentOperations];
		[_ioQueue setSuspended:NO];
		
#if TARGET_OS_IPHONE
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveMemoryWarningNotification:) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didEnterBackgroundNotification:) name:UIApplicationDidEnterBackgroundNotification object:nil];
#endif
	}
	return self;
}

- (void)dealloc {
#if TARGET_OS_IPHONE
	[[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
#endif
}

#if TARGET_OS_IPHONE
// Clear memory cache when app enters background
- (void)didEnterBackgroundNotification:(NSNotification*)notification {
	[self clearMemory];
}

// Clear memory cache when memory warning received
- (void)didReceiveMemoryWarningNotification:(NSNotification*)notification {
	[self clearMemory];
}
#endif

- (void)setImage:(UIImage*)image forKey:(NSString *)key diskOnly:(BOOL)diskOnly {
	[self _setImage:image forKey:key diskOnly:diskOnly completion:nil waitUntilFinished:YES];
}

- (void)setImage:(UIImage*)image forKey:(NSString*)key diskOnly:(BOOL)diskOnly completion:(void (^)(void))completion {
	[self _setImage:image forKey:key diskOnly:diskOnly completion:completion waitUntilFinished:NO];
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

- (void)_setImage:(UIImage*)image forKey:(NSString*)key diskOnly:(BOOL)diskOnly completion:(void (^)(void))completion waitUntilFinished:(BOOL)waitUntilFinished {
	NSParameterAssert(key != nil && image != nil);
	
	// save image to memory
	if(!diskOnly) {
		[_cache setObject:image forKey:key];
	}
	
	// dump image to disk on background queue
	NSBlockOperation* operation = [self _operationWithBlock:^(NSBlockOperation *currentOperation) {
		if(currentOperation.isCancelled) {
			// remove object from cache if operation was cancelled
			if(!diskOnly) {
				[_cache removeObjectForKey:key];
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
	
	
	[_ioQueue addOperations:@[ operation ] waitUntilFinished:waitUntilFinished];
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

- (UIImage*)imageFromMemoryForKey:(NSString*)key {
	NSParameterAssert(key != nil);
	
	return [_cache objectForKey:key];
}

- (void)removeImageForKey:(NSString*)key {
	NSParameterAssert(key != nil);
	
	NSBlockOperation *operation = [self _operationWithBlock:^(NSBlockOperation *currentOperation) {
		if(currentOperation.isCancelled) {
			return;
		}
		
		[_fileManager removeItemAtPath:[self _pathForKey:key] error:nil];
	}];
	
	[_cache removeObjectForKey:key];
	[_ioQueue addOperation:operation];
}

- (void)clearMemory {
	[_ioQueue setSuspended:YES];
	[_cache removeAllObjects];
	[_ioQueue setSuspended:NO];
}

- (void)clear {
	[_ioQueue cancelAllOperations];
	[_ioQueue setSuspended:YES];
	
	[_fileManager removeItemAtPath:_storagePath error:nil];
	_checkStoragePathExists = YES;
	
	[self clearMemory];
	[_ioQueue setSuspended:NO];
}

- (NSBlockOperation*)_operationWithBlock:(void(^)(NSBlockOperation* currentOperation))block {
	NSBlockOperation *operation = [[NSBlockOperation alloc] init];
	__weak NSBlockOperation *weakOperation = operation;
	
	[operation addExecutionBlock:^{
		block(weakOperation);
	}];
	
	return operation;
}

- (NSString*)_pathForKey:(NSString*)key {
	NSString* scale = UIScreen.mainScreen.scale == 2 ? @"@2x" : @"";
	return [_storagePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@%@.jpg", key, scale]];
}

- (void)_lockFileHandle:(NSFileHandle*)handle {
	struct flock lock;
	
	lock.l_start = 0;
	lock.l_len = 0;
	lock.l_pid = getpid();
	lock.l_type = F_WRLCK;
	lock.l_whence = SEEK_SET;
	
	if(fcntl(handle.fileDescriptor, F_SETLKW, &lock) == -1) {
		NSLog(@"%s error: %s", __PRETTY_FUNCTION__, strerror(errno));
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
		NSLog(@"%s error: %s", __PRETTY_FUNCTION__, strerror(errno));
	}
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
					[[NSException exceptionWithName:@"IOException" reason:error.localizedFailureReason userInfo:error.userInfo] raise];
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
		[[NSException exceptionWithName:@"IOException" reason:[NSString stringWithFormat:@"Invalid file handle: %@", path] userInfo:nil] raise];
	}
	
	// lock file
	[self _lockFileHandle:handle];
	
	// write data
	[handle writeData:data];
	
	// unlock file
	[self _unlockFileHandle:handle];
}

- (UIImage*)_imageForKey:(NSString*)key {
	NSParameterAssert(key != nil);
	
	UIImage* image = [_cache objectForKey:key];
	
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
			[_cache setObject:image forKey:key];
		}
	}
	
	return image;
}

@end
