# frozen_string_literal: true

source "https://rubygems.org"

git_source(:github) {|repo_name| "https://github.com/#{repo_name}" }

gem "jekyll"
gem "webrick"

# Jekyll will automatically activate any plugins
# listed in the :jekyll_plugins group.
group :jekyll_plugins do
  gem 'jekyll-redirect-from'
  gem "jekyll-compose"
  gem "jekyll-seo-tag"
  gem "jekyll-paginate"
  gem "jekyll-feed"
  gem "jekyll-sitemap"
  gem "jekyll-github-metadata"
  gem 'github-pages'
end

group :development do
	gem "rake"
end