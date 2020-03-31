FROM ruby:latest

RUN gem install bundler

COPY Gemfile Gemfile
COPY Gemfile.lock Gemfile.lock

RUN bundle install

VOLUME /src
EXPOSE 4000

WORKDIR /src
ENTRYPOINT ["jekyll"]