//
//  PBImageStorage.h
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

#import <Foundation/Foundation.h>

@interface PBImageStorage : NSObject

@property (strong, readonly) NSString* namespaceName;
@property (strong, readonly) NSString* storagePath;

//
// Initialize storage with default namespace
//
- (id)init;

//
// Initialize storage with namespace at Library/Caches
//
- (id)initWithNamespace:(NSString*)name;

//
// Initialize storage with namespace and custom base path for storage
//
- (id)initWithNamespace:(NSString*)name basePath:(NSString*)basePath;

//
// Save image to disk only, or to memory and disk.
// Blocks current thread execution until operation completed.
//
- (void)setImage:(UIImage*)image forKey:(NSString *)key diskOnly:(BOOL)diskOnly;

//
// Save image to disk only, or to memory and disk
// Completion handler is called on main thread.
//
- (void)setImage:(UIImage*)image forKey:(NSString*)key diskOnly:(BOOL)diskOnly completion:(void(^)(void))completion;

//
// Copy image from one key to another
// Blocks current thread execution until operation completed.
//
- (void)copyImageFromKey:(NSString*)fromKey toKey:(NSString*)toKey diskOnly:(BOOL)diskOnly;

//
// Copy image from one key to another
// Completion handler is called on main thread.
//
- (void)copyImageFromKey:(NSString*)fromKey toKey:(NSString*)toKey diskOnly:(BOOL)diskOnly completion:(void(^)(void))completion;

//
// Retrieve image from memory if available, otherwise load it from
// disk to memory and return it in completion handler
// Completion handler is called on main thread.
//
- (void)imageForKey:(NSString*)key completion:(void(^)(UIImage* image))completion;

//
// Retrieve image from memory if available, otherwise nil
//
- (UIImage*)imageFromMemoryForKey:(NSString*)key;

//
// Remove image by key from disk and memory
//
- (void)removeImageForKey:(NSString*)key;

//
// Removes all objects from memory cache
//
- (void)clearMemory;

//
// Removes all objects from disk and memory
// Blocks current thread execution until operation completed.
//

- (void)clear;

@end
