# Rquire jekyll to compile the site.
require "jekyll"
require 'tmpdir'

namespace :docker do

  file 'Dockerfile'
  file 'Gemfile.lock'

  desc "Builds a docker image named jekyll"
  task :build do
    sh 'docker build -f Dockerfile -t jekyll .'
  end

  desc "Serve the jekyll website via Docker"
  task :serve => :build do
    sh "docker run -p 4000:4000 -p 35729:35729 -v #{Dir.pwd}:/src --rm jekyll serve -H 0.0.0.0 --watch --drafts --incremental --livereload"
  end

end

# Github pages publishing.
namespace :blog do

  desc "Serve the Jekyll blog locally."
  task :serve do
    Jekyll::PluginManager.require_from_bundler

    # Generate the site in server mode.
    puts "Running Jekyll..."
    options = {
      "source"      => ".",
      "destination" => "_site",
      "incremental" => true,
      "profile"     => true,
      "watch"       => true,
      "serving"     => true,
    }
    Jekyll::Commands::Build.process(options)
    Jekyll::Commands::Serve.process(options)
  end
  
  desc "Generate the jekyll blog at _site"
  task :generate do
    Jekyll::PluginManager.require_from_bundler

    Jekyll::Site.new(Jekyll.configuration({
    "source"      => ".",
    "destination" => "_site"
    })).process
  end

  desc "Publish blog to gh-pages on Github"
  task :publish => [:generate] do
    # Make a temporary directory for the build before production release.
    # This will be torn down once the task is complete.
    Dir.mktmpdir do |tmp|
      # Copy accross our compiled _site directory.
      cp_r "_site/.", tmp

      # Switch in to the tmp dir.
      Dir.chdir tmp do
        # Prepare all the content in the repo for deployment.
        # Init the repo.
        system "git init"
        # Add and commit all the files.
        system "git add . && git commit -m 'Site updated at #{Time.now.utc}'"

        # Add the origin remote for the parent repo to the tmp folder.
        system "git remote add origin git@github.com:fzakaria/fzakaria.github.io.git"

        # Push the files to the gh-pages branch, forcing an overwrite.
        system "git push origin master:refs/heads/gh-pages --force"
      end

    end
  end

end