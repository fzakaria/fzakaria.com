# frozen_string_literal: true

source "https://rubygems.org"

git_source(:github) {|repo_name| "https://github.com/#{repo_name}" }

gem "jekyll"

# Jekyll will automatically activate any plugins
# listed in the :jekyll_plugins group.
group :jekyll_plugins do
  gem "jekyll-compose"
  gem "github-pages"
  gem "jekyll-redirect-from"
  gem "kramdown"
  gem "rdiscount"
  gem "rouge"
  # The following are plugins needed by the ddevault theme
  gem "jekyll-theme-ddevault", git: "https://git.sr.ht/~fzakaria/ddjekyll"
  gem "jekyll-seo-tag"
  gem "jekyll-paginate"
  gem "jekyll-feed"
end