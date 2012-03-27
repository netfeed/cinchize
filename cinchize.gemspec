Gem::Specification.new do |s|
  s.name = "cinchize"
  s.version = File.new("VERSION", 'r').read.chomp
  s.authors = ["Victor Bergoo"]
  s.summary = "Create dynamic Cinch IRC-bots and daemonize them"
  s.description = "Create dynamic Cinch IRC-bots and daemonize them, without the need of writing any code"
  s.email = "victor.bergoo@gmail.com"
  s.executables = ["cinchize"]
  s.extra_rdoc_files = [
    "LICENSE",
    "README.rdoc"
  ]
  s.files = [
    "LICENSE",
    "README.rdoc",
    "Rakefile",
    "VERSION",
    "bin/cinchize",
    "cinchize.gemspec",
    "examples/cinchize.init",
    "lib/cinchize.rb"
  ]
  s.homepage = "http://github.com/netfeed/cinchize"
  s.require_paths = ["lib"]
 
  s.add_runtime_dependency(%q<cinch>, [">= 2.0.1"])
  s.add_runtime_dependency(%q<daemons>, [">= 0"])
end

