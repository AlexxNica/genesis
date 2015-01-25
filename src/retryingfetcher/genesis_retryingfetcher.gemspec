Gem::Specification.new do |gem|
  gem.name = 'genesis_retryingfetcher'
  gem.email = 'opensourcesoftware@tumblr.com'
  gem.homepage = 'https://github.com/Tumblr/genesis'
  gem.license = 'Apache License, 2.0'
  gem.summary = %Q{Genesis remote resource fetcher}
  gem.description = %Q{Genesis is used to manage provisioning of hardware. The retryingfetcher is what fetches resources from remote locations with a specified number of retries and backoff between each.}
  gem.authors = ['Jeremy Johnstone', 'Roy Marantz']
  gem.version = '0.4.0'
  gem.date = '2014-12-08'
  gem.add_dependency('httparty', '~> 0')
  gem.files = Dir['lib/*.rb', '*.md', '*.txt']
end
