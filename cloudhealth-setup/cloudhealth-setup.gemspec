Gem::Specification.new do |s|
  s.name        = 'cloudhealth-setup'
  s.version     = '0.0.15'
  s.date        = '2014-01-23'
  s.platform    = Gem::Platform::RUBY
  s.authors     = ['CloudHealth Technologies']
  s.email       = ['support@cloudhealthtech.com']
  s.homepage    = 'http://www.cloudhealthtech.com'
  s.summary     = 'Configures an Amazon AWS account for use with the CloudHealth service'
  s.description = 'Configures an Amazon AWS account for use with the CloudHealth service, including creating a least privilege read only AWS user and enabling the retrieval of cost and usage information.'
  s.license     = 'MIT'
  s.has_rdoc    = false

  s.add_dependency("fog", "= 1.15.0")
  s.add_dependency("multi_json", "= 1.7.7")
  s.add_dependency("excon", "= 0.25.3")
  s.add_dependency("mixlib-cli", "= 1.3.0")
  s.add_dependency("mechanize", "= 2.5.1")
  s.add_dependency("highline", "= 1.6.19")
  s.add_dependency("nokogiri", "= 1.5.8")
  s.add_dependency("json_pure", "= 1.8.1")

  s.bindir        = "bin"
  s.files         = Dir.glob('{bin,lib}/**/*') + %w[cloudhealth-setup.gemspec]
  s.executables   = Dir.glob('bin/**/*').map { |file| File.basename(file) }
  s.require_paths = ['lib']
end
