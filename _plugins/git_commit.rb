module Jekyll
  class GitCommitGenerator < Generator
    priority :highest

    def generate(site)
      commit_hash = ENV['JEKYLL_BUILD_REVISION'] || `git rev-parse HEAD`.strip
      site.config['commit_hash'] = commit_hash
    end
  end
end