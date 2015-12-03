#
# Be sure to run `pod lib lint SMHTTPClient.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = "SMHTTPClient"
  s.version          = "0.2.0"
  s.summary          = "HTTP/1.1 client, based on socket"

  s.description      = <<-DESC
  Use SMHTTPClient if you need a HTTP/1.1 access without TLS.
  This is expected for apps to be used with appliance which speaks HTTP/1.1 without TLS and Bonjour.
                       DESC

  s.homepage         = "https://github.com/soutaro/SMHTTPClient"
  s.license          = 'MIT'
  s.author           = { "Soutaro Matsumoto" => "matsumoto@soutaro.com" }
  s.source           = { :git => "https://github.com/soutaro/SMHTTPClient.git", :tag => s.version.to_s }

  s.requires_arc = true
  s.ios.deployment_target = '8.0'

  s.source_files = 'SMHTTPClient/Classes/**/*'
end
