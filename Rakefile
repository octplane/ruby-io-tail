# vim: set filetype=ruby et sw=2 ts=2:

require 'gem_hadar'


$: << File.join(File.dirname(__FILE__),'lib')
require 'io/tail/version'


GemHadar do
  name        'io-tail'
  path_name   'io/tail'
  author      'Pierre Baillet'
  email       'pierre@baillet.name'
  homepage    "http://github.com/octplane/ruby-#{name}"
  summary     "#{path_name.camelize} for Ruby"
  description 'Library to tail files and process in Ruby'
  test_dir    'tests'
  ignore      '.*.sw[pon]', 'pkg', 'Gemfile.lock', 'coverage', '*.rbc'
  readme      'README.rdoc'
  version     IO::Tail::VERSION
  executables 'rtail'

  dependency  'tins', '~>0.3'

  development_dependency 'test-unit', '~>2.4.0'

  install_library do
    cd 'lib' do
      libdir = CONFIG["sitelibdir"]

      dest = File.join(libdir, 'file')
      mkdir_p(dest)
      dest = File.join(libdir, path_name)
      install(path_name + '.rb', dest + '.rb', :verbose => true)
      mkdir_p(dest)
      for file in Dir[File.join(path_name, '*.rb')]
        install(file, dest, :verbose => true)
      end
    end
    bindir = CONFIG["bindir"]
    install('bin/rtail', bindir, :verbose => true, :mode => 0755)
  end
end
