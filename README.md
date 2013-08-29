PBImageStorage
==============

Image storage that implements memory cache between app and disk. This implementation allows to store tons of images on disk and keep only specific subset in memory. Images are lazy loaded in memory upon access and purged from memory on memory warning or when app goes background. 

The storage internally uses NSCache for in-memory caching and concurrent NSOperationQueue for IO. The maximum number of concurrent operations is defined according to number of cores on device.
