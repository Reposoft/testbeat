FROM solsson/testbeat

ADD Gemfile /testbeat-watch/

RUN gem install bundler

RUN cd /testbeat-watch/ &&
  bundle

RUN cd /spec/ &&
  bundle exec guard init
