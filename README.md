# PBImageStorage

Key-value image storage with memory cache, thumbnails support and on-disk persistence.

## CocoaPods

Drop the following line in your Podfile:

```ruby
pod 'PBImageStorage'
```

## Usage

```objective-c

// initialize myStorage instance
PBImageStorage* storage = [[PBImageStorage alloc] initWithNamespace:@"myStorage"];

// Put image to storage asynchronously
[storage setImage:someImage forKey:@"someKey" diskOnly:NO completion:^{
	NSLog(@"Image has been saved to disk.");
}];

// Get image from storage asynchronously
[storage imageForKey:@"someKey" completion:^(UIImage* image) {
	NSLog(@"Image %p with size %@ has been retrieved from storage.", image, NSStringFromCGSize(image.size));
}];

// Get scaled image from storage asynchronously
[storage imageForKey:@"someKey" scaledToFit:CGSizeMake(200, 200) completion:^(BOOL cached, UIImage* image) {
	NSLog(@"Scaled image %p with size %@ has been retrieved from storage.", image, NSStringFromCGSize(image.size));
	NSLog(@"Scaled image was cached in memory? %@", ((cached) ? @"YES" : @"NO"));
}];

// Copy image from one key to some other key asynchronously
[storage copyImageFromKey:@"someKey" toKey:@"someOtherKey" diskOnly:NO completion:^{
	NSLog(@"Image has been copied.");
}];

// Remove image from storage
[storage removeImageForKey:@"someKey"];
```

## TODO

- Add tests
- Convert documentation to something apple-doc would understand
