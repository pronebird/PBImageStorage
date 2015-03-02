Pod::Spec.new do |s|
  s.name     = 'PBImageStorage'
  s.version  = '0.1.1'
  s.license  = 'MIT'
  s.summary  = 'Key-value image storage with memory cache, thumbnails support and on-disk persistence.'
  s.homepage = 'https://github.com/pronebird/PBImageStorage'
  s.authors  = {
    'Andrej Mihajlov' => 'and@codeispoetry.ru'
  }
  s.source   = {
    :git => 'https://github.com/pronebird/PBImageStorage.git',
    :tag => s.version.to_s
  }
  s.source_files = '*.{h,m}'
  s.requires_arc = true
  s.ios.deployment_target = '7.0'
end
